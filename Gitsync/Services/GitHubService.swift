import Foundation

actor GitHubService {
    static let shared = GitHubService()

    private let base = "https://api.github.com"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - User

    func fetchUser(token: String) async throws -> GitHubUser {
        var req = URLRequest(url: URL(string: "\(base)/user")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
        return try decoder.decode(GitHubUser.self, from: data)
    }

    // MARK: - Repos

    func listRepos(token: String) async throws -> [Repository] {
        var req = URLRequest(url: URL(string: "\(base)/user/repos?per_page=100&sort=updated")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
        return try decoder.decode([Repository].self, from: data)
    }

    func createRepo(token: String, name: String, description: String?, isPrivate: Bool) async throws -> Repository {
        var req = URLRequest(url: URL(string: "\(base)/user/repos")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateRepoRequest(
            name: name,
            description: description,
            private: isPrivate,
            autoInit: true
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
        return try decoder.decode(Repository.self, from: data)
    }

    func deleteRepo(token: String, owner: String, repo: String) async throws {
        var req = URLRequest(url: URL(string: "\(base)/repos/\(owner)/\(repo)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
    }

    // MARK: - Push multiple files (Git Data API)

    func pushFiles(
        token: String,
        owner: String,
        repo: String,
        branch: String = "main",
        files: [(path: String, content: Data)],
        message: String
    ) async throws -> String {
        // 1. Get current ref SHA
        let refURL = URL(string: "\(base)/repos/\(owner)/\(repo)/git/ref/heads/\(branch)")!
        var refReq = URLRequest(url: refURL)
        refReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        refReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (refData, refResp) = try await URLSession.shared.data(for: refReq)
        try check(refResp, data: refData)
        let ref = try decoder.decode(RefResponse.self, from: refData)
        let parentSHA = ref.object.sha

        // 2. Create blobs
        var treeEntries: [TreeEntry] = []
        for file in files {
            let blobSHA = try await createBlob(token: token, owner: owner, repo: repo, content: file.content)
            treeEntries.append(TreeEntry(
                path: file.path,
                mode: "100644",
                type: "blob",
                sha: blobSHA
            ))
        }

        // 3. Create tree (based on current so we keep existing files + add/overwrite)
        let treeSHA = try await createTree(
            token: token,
            owner: owner,
            repo: repo,
            baseTree: parentSHA,
            entries: treeEntries
        )

        // 4. Create commit
        let commitSHA = try await createCommit(
            token: token,
            owner: owner,
            repo: repo,
            message: message,
            treeSHA: treeSHA,
            parentSHA: parentSHA
        )

        // 5. Update ref
        try await updateRef(
            token: token,
            owner: owner,
            repo: repo,
            branch: branch,
            sha: commitSHA
        )

        return commitSHA
    }

    private func createBlob(token: String, owner: String, repo: String, content: Data) async throws -> String {
        var req = URLRequest(url: URL(string: "\(base)/repos/\(owner)/\(repo)/git/blobs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "content": content.base64EncodedString(),
            "encoding": "base64"
        ]
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
        let blob = try decoder.decode(BlobResponse.self, from: data)
        return blob.sha
    }

    private func createTree(
        token: String,
        owner: String,
        repo: String,
        baseTree: String,
        entries: [TreeEntry]
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "\(base)/repos/\(owner)/\(repo)/git/trees")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateTreeRequest(baseTree: baseTree, tree: entries)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
        let tree = try decoder.decode(TreeResponse.self, from: data)
        return tree.sha
    }

    private func createCommit(
        token: String,
        owner: String,
        repo: String,
        message: String,
        treeSHA: String,
        parentSHA: String
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "\(base)/repos/\(owner)/\(repo)/git/commits")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateCommitRequest(
            message: message,
            tree: treeSHA,
            parents: [parentSHA]
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
        let commit = try decoder.decode(CommitResponse.self, from: data)
        return commit.sha
    }

    private func updateRef(
        token: String,
        owner: String,
        repo: String,
        branch: String,
        sha: String
    ) async throws {
        var req = URLRequest(url: URL(string: "\(base)/repos/\(owner)/\(repo)/git/refs/heads/\(branch)")!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = UpdateRefRequest(sha: sha)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data: data)
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw GitHubError.unauthorized
        case 403: throw GitHubError.forbidden
        case 404: throw GitHubError.notFound
        case 422:
            if let msg = String(data: data, encoding: .utf8) {
                throw GitHubError.apiMessage(msg)
            }
            throw GitHubError.validationFailed
        default:
            if let msg = String(data: data, encoding: .utf8), !msg.isEmpty {
                throw GitHubError.apiMessage("HTTP \(http.statusCode): \(msg)")
            }
            throw GitHubError.http(http.statusCode)
        }
    }
}

enum GitHubError: LocalizedError {
    case invalidResponse, unauthorized, forbidden, notFound, validationFailed, http(Int), noToken, emptyFiles, apiMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Response tidak valid"
        case .unauthorized: return "Token tidak valid / expired"
        case .forbidden: return "Akses ditolak (cek scope token: repo + delete_repo)"
        case .notFound: return "Repo atau branch tidak ditemukan"
        case .validationFailed: return "Validasi gagal (nama repo sudah ada?)"
        case .http(let code): return "HTTP \(code)"
        case .noToken: return "Belum login"
        case .emptyFiles: return "Tidak ada file untuk di-push"
        case .apiMessage(let msg): return msg
        }
    }
}
