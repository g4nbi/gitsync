import SwiftUI

struct HomeView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showCreate = false
    @State private var showPush = false
    @State private var repos: [Repository] = []
    @State private var isLoadingRepos = false
    @State private var selectedRepo: Repository?

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
                    } else if repos.isEmpty {
                        Text("Belum ada repo atau gagal load")
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
            .task {
                await loadRepos()
            }
        }
    }

    private func loadRepos() async {
        guard let token = auth.currentToken else { return }
        isLoadingRepos = true
        defer { isLoadingRepos = false }
        do {
            repos = try await GitHubService.shared.listRepos(token: token)
        } catch {
            // silent
        }
    }
}
