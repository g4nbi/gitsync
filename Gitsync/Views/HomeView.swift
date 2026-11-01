import SwiftUI

struct HomeView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showCreate = false
    @State private var showPush = false
    @State private var repos: [Repository] = []
    @State private var isLoadingRepos = false
    @State private var selectedRepo: Repository?
    @State private var loadError: String?
    @State private var repoToDelete: Repository?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = auth.user {
                        HStack(spacing: 14) {
                            AsyncImage(url: URL(string: user.avatarUrl ?? "")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(.quaternary)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name ?? user.login)
                                    .font(.headline)
                                Text("@\(user.login)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Aksi") {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Buat Repo Baru", systemImage: "plus.rectangle.on.folder")
                    }

                    Button {
                        showPush = true
                    } label: {
                        Label("Push File / Folder", systemImage: "arrow.up.doc")
                    }
                }

                Section {
                    if isLoadingRepos {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let loadError {
                        Text(loadError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    } else if repos.isEmpty {
                        Text("Belum ada repo")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(repos) { repo in
                            Button {
                                selectedRepo = repo
                                showPush = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(repo.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if let desc = repo.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if repo.private {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    repoToDelete = repo
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Hapus", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Repo terbaru")
                        Spacer()
                        Button {
                            Task { await loadRepos() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Gitsync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Logout") {
                        auth.logout()
                    }
                    .foregroundStyle(.red)
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateRepoView { newRepo in
                    repos.insert(newRepo, at: 0)
                }
            }
            .sheet(isPresented: $showPush) {
                PushView(preselectedRepo: selectedRepo)
                    .onDisappear { selectedRepo = nil }
            }
            .confirmationDialog(
                "Hapus repo \(repoToDelete?.fullName ?? "")?\nTindakan ini tidak bisa dibatalkan.",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Hapus Permanen", role: .destructive) {
                    Task { await deleteRepo() }
                }
                Button("Batal", role: .cancel) {}
            }
            .task {
                await loadRepos()
            }
        }
    }

    private func loadRepos() async {
        guard let token = auth.currentToken else { return }
        isLoadingRepos = true
        loadError = nil
        defer { isLoadingRepos = false }
        do {
            repos = try await GitHubService.shared.listRepos(token: token)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteRepo() async {
        guard let token = auth.currentToken,
              let repo = repoToDelete else { return }
        let owner = repo.fullName.split(separator: "/").first.map(String.init) ?? ""
        do {
            try await GitHubService.shared.deleteRepo(token: token, owner: owner, repo: repo.name)
            repos.removeAll { $0.id == repo.id }
        } catch {
            loadError = "Gagal hapus: \(error.localizedDescription)"
        }
        repoToDelete = nil
    }
}
