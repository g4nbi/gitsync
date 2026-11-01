import SwiftUI
import UniformTypeIdentifiers

struct PushView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    var preselectedRepo: Repository? = nil

    @State private var repos: [Repository] = []
    @State private var selectedRepo: Repository?
    @State private var commitMessage = "Update from Gitsync"
    @State private var selectedFiles: [FileItem] = []
    @State private var isImporting = false
    @State private var isPushing = false
    @State private var progressText = ""
    @State private var error: String?
    @State private var successURL: URL?
    @State private var showRepoPicker = false
    @State private var flattenFolder = true   // isi folder langsung di root repo

    var body: some View {
        NavigationStack {
            Form {
                Section("Target Repo") {
                    if let repo = selectedRepo {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(repo.fullName)
                                    .font(.body.weight(.medium))
                                Text(repo.private ? "Private" : "Public")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Ganti") { showRepoPicker = true }
                                .font(.subheadline)
                        }
                    } else {
                        Button("Pilih Repo") { showRepoPicker = true }
                    }
                }

                Section {
                    Button {
                        isImporting = true
                    } label: {
                        Label(
                            selectedFiles.isEmpty ? "Pilih File atau Folder" : "Ganti File / Folder",
                            systemImage: "folder.badge.plus"
                        )
                    }

                    if !selectedFiles.isEmpty {
                        Toggle("Folder langsung di root (jadi main)", isOn: $flattenFolder)

                        ForEach(selectedFiles.prefix(30)) { item in
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(displayPath(for: item))
                                    .lineLimit(1)
                                    .font(.footnote)
                            }
                        }
                        if selectedFiles.count > 30 {
                            Text("… +\(selectedFiles.count - 30) file")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(selectedFiles.count) file siap di-push")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Konten")
                }

                Section("Commit Message") {
                    TextField("Pesan commit", text: $commitMessage, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if let url = successURL {
                    Section {
                        Text("Berhasil di-push!")
                            .foregroundStyle(.green)
                        Link(destination: url) {
                            Label("Buka di GitHub", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle("Push")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Push") {
                        Task { await performPush() }
                    }
                    .disabled(
                        selectedRepo == nil ||
                        selectedFiles.isEmpty ||
                        commitMessage.trimmingCharacters(in: .whitespaces).isEmpty ||
                        isPushing
                    )
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if isPushing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(progressText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.item, .folder],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showRepoPicker) {
                RepoPickerView(repos: repos, selected: $selectedRepo)
            }
            .task {
                await loadRepos()
                if let pre = preselectedRepo {
                    selectedRepo = pre
                }
            }
        }
    }

    private func displayPath(for item: FileItem) -> String {
        if flattenFolder, let root = item.rootFolderName {
            // hapus nama folder di depan supaya langsung di root
            let prefix = root + "/"
            if item.relativePath.hasPrefix(prefix) {
                return String(item.relativePath.dropFirst(prefix.count))
            }
        }
        return item.relativePath
    }

    private func loadRepos() async {
        guard let token = auth.currentToken else { return }
        do {
            repos = try await GitHubService.shared.listRepos(token: token)
            if selectedRepo == nil, let first = repos.first {
                selectedRepo = first
            }
        } catch {}
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Copy ke temp directory supaya security-scoped access tidak hilang
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitsync-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            var items: [FileItem] = []

            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                if isDir.boolValue {
                    // Folder → recurse & copy
                    let rootName = url.lastPathComponent
                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for case let fileURL as URL in enumerator {
                        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        guard values?.isRegularFile == true else { continue }

                        // relative path from the selected folder
                        let relFromFolder = fileURL.path
                            .replacingOccurrences(of: url.path, with: "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let relativePath = "\(rootName)/\(relFromFolder)"

                        // copy to temp
                        let dest = tempRoot.appendingPathComponent(relativePath)
                        try? FileManager.default.createDirectory(
                            at: dest.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try? FileManager.default.copyItem(at: fileURL, to: dest)

                        items.append(FileItem(
                            url: dest,
                            relativePath: relativePath,
                            isDirectory: false,
                            rootFolderName: rootName
                        ))
                    }
                } else {
                    // Single file
                    let name = url.lastPathComponent
                    let dest = tempRoot.appendingPathComponent(name)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    items.append(FileItem(
                        url: dest,
                        relativePath: name,
                        isDirectory: false,
                        rootFolderName: nil
                    ))
                }
            }

            selectedFiles = items
            error = items.isEmpty ? "Tidak ada file yang bisa dibaca" : nil
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func performPush() async {
        guard let token = auth.currentToken,
              let repo = selectedRepo else { return }

        guard !selectedFiles.isEmpty else {
            error = "Tidak ada file"
            return
        }

        isPushing = true
        error = nil
        successURL = nil
        progressText = "Membaca \(selectedFiles.count) file…"

        do {
            var payloads: [(path: String, content: Data)] = []
            for item in selectedFiles {
                let data = try Data(contentsOf: item.url)
                if data.count > 50 * 1024 * 1024 { continue } // skip > 50MB

                var path = item.relativePath
                if flattenFolder, let root = item.rootFolderName {
                    let prefix = root + "/"
                    if path.hasPrefix(prefix) {
                        path = String(path.dropFirst(prefix.count))
                    }
                }
                // skip empty path
                guard !path.isEmpty else { continue }
                payloads.append((path, data))
            }

            guard !payloads.isEmpty else {
                throw GitHubError.emptyFiles
            }

            progressText = "Upload \(payloads.count) file ke GitHub…"

            let owner = repo.fullName.split(separator: "/").first.map(String.init) ?? ""
            let repoName = repo.name

            let commitSHA = try await GitHubService.shared.pushFiles(
                token: token,
                owner: owner,
                repo: repoName,
                branch: repo.defaultBranch,
                files: payloads,
                message: commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            progressText = "Selesai"
            if let url = URL(string: "\(repo.htmlUrl)/commit/\(commitSHA)") {
                successURL = url
            } else {
                successURL = URL(string: repo.htmlUrl)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isPushing = false
    }
}

struct RepoPickerView: View {
    let repos: [Repository]
    @Binding var selected: Repository?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(repos) { repo in
                Button {
                    selected = repo
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(repo.name)
                            Text(repo.fullName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected?.id == repo.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle("Pilih Repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}
