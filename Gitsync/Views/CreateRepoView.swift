import SwiftUI

struct CreateRepoView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true
    @State private var isCreating = false
    @State private var error: String?
    @State private var createdRepo: Repository?

    var onCreated: ((Repository) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nama repo", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Deskripsi (opsional)", text: $description)

                    Toggle("Private", isOn: $isPrivate)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if let repo = createdRepo {
                    Section {
                        Text("Repo berhasil dibuat!")
                            .foregroundStyle(.green)
                        Link(destination: URL(string: repo.htmlUrl)!) {
                            Label(repo.fullName, systemImage: "link")
                        }
                    }
                }
            }
            .navigationTitle("Buat Repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Buat") {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .overlay {
                if isCreating {
                    ProgressView("Membuat…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func create() async {
        guard let token = auth.currentToken else { return }
        isCreating = true
        error = nil
        defer { isCreating = false }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()

        do {
            let repo = try await GitHubService.shared.createRepo(
                token: token,
                name: cleanName,
                description: description.isEmpty ? nil : description,
                isPrivate: isPrivate
            )
            createdRepo = repo
            onCreated?(repo)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
