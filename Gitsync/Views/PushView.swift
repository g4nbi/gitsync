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
                            Button("Ganti") {
                                showRepoPicker = true
                            }
                            .font(.subheadline)
                        }
                    } else {
                        Button("Pilih Repo") {
                            showRepoPicker = true
                        }
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
                        ForEach(selectedFiles.prefix(20)) { item in
                            HStack {
                                Image(systemName: item.isDirectory ? "folder" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(item.relativePath)
                                    .lineLimit(1)
                                    .font(.footnote)
                            }
                        }
                        if selectedFiles.count > 20 {
                            Text("… dan \(selectedFiles.count - 20) file lainnya")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(selectedFiles.filter { !$0.isDirectory }.count) file")
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
            var items: [FileItem] = []
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        let rootName = url.lastPathComponent
                        for case let fileURL as URL in enumerator {
                            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                            if values?.isRegularFile == true {
                                let rel = fileURL.path.replacingOccurrences(of: url.path, with: rootName)
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                items.append(FileItem(url: fileURL, relativePath: rel, isDirectory: false))
                            }
                        }
                    }
                } else {
                    items.append(FileItem(url: url, relativePath: url.lastPathComponent, isDirectory: false))
                }
            }
            selectedFiles = items
            error = nil
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func performPush() async {
        guard let token = auth.currentToken,
              let repo = selectedRepo else { return }

        let fileItems = selectedFiles.filter { !$0.isDirectory }
        guard !fileItems.isEmpty else {
            error = "Tidak ada file"
            return
        }

        isPushing = true
        error = nil
        successURL = nil
        progressText = "Membaca \(fileItems.count) file…"

        do {
            var payloads: [(path: String, content: Data)] = []
            for item in fileItems {
                let accessing = item.url.startAccessingSecurityScopedResource()
                defer { if accessing { item.url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: item.url)
                if data.count > 50 * 1024 * 1024 { continue }
                payloads.append((item.relativePath, data))
            }

            guard !payloads.isEmpty else {
                throw GitHubError.emptyFiles
            }

            progressText = "Mengupload \(payloads.count) file…"

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
