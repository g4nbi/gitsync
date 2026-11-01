import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showPAT = false
    @State private var pat = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.primary)

                    Text("Gitsync")
                        .font(.largeTitle.weight(.semibold))

                    Text("Push file & folder ke GitHub")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if auth.isWaitingForApproval {
                    VStack(spacing: 20) {
                        Text("Buka GitHub & masukkan kode ini:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(auth.userCode ?? "······")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                        if let uri = auth.verificationURI, let url = URL(string: uri) {
                            Link(destination: url) {
                                Label("Buka github.com/login/device", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text("Setelah Authorize, app akan otomatis lanjut.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Batal") {
                            auth.cancelDeviceFlow()
                        }
                        .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("GitHub OAuth Client ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Ov23li…", text: $auth.clientIDInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            Task { await auth.startDeviceFlow() }
                        } label: {
                            Label("Authorize dengan GitHub", systemImage: "person.badge.key.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(auth.clientIDInput.trimmingCharacters(in: .whitespaces).isEmpty || auth.isLoading)

                        HStack {
                            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                            Text("atau").font(.caption).foregroundStyle(.secondary)
                            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                        }

                        if showPAT {
                            SecureField("Personal Access Token (ghp_…)", text: $pat)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                            Button {
                                Task { await auth.loginWithPAT(pat) }
                            } label: {
                                Text("Login dengan Token")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.bordered)
                            .disabled(pat.trimmingCharacters(in: .whitespaces).isEmpty || auth.isLoading)
                        } else {
                            Button("Pakai Personal Access Token") {
                                withAnimation { showPAT = true }
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                if let err = auth.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if auth.isLoading && !auth.isWaitingForApproval {
                    ProgressView()
                }

                Spacer()

                Text("Client ID & token hanya disimpan di perangkat ini\n(Keychain + fallback UserDefaults).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }
            .navigationBarHidden(true)
        }
    }
}
