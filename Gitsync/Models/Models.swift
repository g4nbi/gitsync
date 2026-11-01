import Foundation

struct GitHubUser: Codable, Identifiable {
    let id: Int
    let login: String
    let name: String?
    let avatarUrl: String?
}

struct Repository: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let `private`: Bool
    let htmlUrl: String
    let defaultBranch: String
    let description: String?
}

struct CreateRepoRequest: Encodable {
    let name: String
    let description: String?
    let `private`: Bool
    let autoInit: Bool

    enum CodingKeys: String, CodingKey {
        case name, description
        case `private`
        case autoInit = "auto_init"
    }
}

// Git Data API helpers

struct BlobResponse: Codable {
    let sha: String
}

struct TreeEntry: Encodable {
    let path: String
    let mode: String
    let type: String
    let sha: String
}

struct CreateTreeRequest: Encodable {
    let baseTree: String?
    let tree: [TreeEntry]

    enum CodingKeys: String, CodingKey {
        case tree
        case baseTree = "base_tree"
    }
}

struct TreeResponse: Codable {
    let sha: String
}

struct CreateCommitRequest: Encodable {
    let message: String
    let tree: String
    let parents: [String]
}

struct CommitResponse: Codable {
    let sha: String
}

struct RefResponse: Codable {
    let object: RefObject
    struct RefObject: Codable {
        let sha: String
    }
}

struct UpdateRefRequest: Encodable {
    let sha: String
    let force: Bool = false
}

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let relativePath: String
    let isDirectory: Bool
}
