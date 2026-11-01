import Foundation
import SwiftUI

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var user: GitHubUser?
    @Published var errorMessage: String?
    @Published var isLoading = false

    // Device flow state
    @Published var userCode: String?
    @Published var verificationURI: String?
    @Published var isWaitingForApproval = false
    @Published var clientIDInput = ""

    private var token: String?
    private var deviceCode: String?
    private var pollInterval: TimeInterval = 5
    private var pollTask: Task<Void, Never>?

    // Scopes as requested
    private let scopes = "repo delete_repo workflow"

    private init() {
        // Prefer Keychain, fallback UserDefaults
        if let saved = KeychainService.loadToken() ?? UserDefaults.standard.string(forKey: "github_token") {
            self.token = saved
            self.isAuthenticated = true
            Task { await fetchUser() }
        }
        if let savedClient = UserDefaults.standard.string(forKey: "github_client_id") {
            clientIDInput = savedClient
        }
    }

    var currentToken: String? { token }

    // MARK: - Device Code Flow

    /// Step 1: Request device + user code from GitHub
    func startDeviceFlow() async {
        errorMessage = nil
        userCode = nil
        verificationURI = nil
        isWaitingForApproval = false

        let clientID = clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            errorMessage = "Masukkan Client ID dulu"
            return
        }

        // Persist client ID for next time
        UserDefaults.standard.set(clientID, forKey: "github_client_id")

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["error_description"] as? String ?? json["error"] as? String {
                    errorMessage = msg
                } else {
                    errorMessage = "Gagal minta device code"
                }
                return
            }

            var deviceCodeStr: String?
            var userCodeStr: String?
            var verificationURIStr: String?
            var interval: TimeInterval = 5

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                deviceCodeStr = json["device_code"] as? String
                userCodeStr = json["user_code"] as? String
                verificationURIStr = json["verification_uri"] as? String
                if let i = json["interval"] as? Int { interval = TimeInterval(i) }
            } else if let str = String(data: data, encoding: .utf8) {
                let pairs = str.components(separatedBy: "&")
                for pair in pairs {
                    let kv = pair.components(separatedBy: "=")
                    guard kv.count == 2 else { continue }
                    let key = kv[0]
                    let val = kv[1].removingPercentEncoding ?? kv[1]
                    switch key {
                    case "device_code": deviceCodeStr = val
                    case "user_code": userCodeStr = val
                    case "verification_uri": verificationURIStr = val
                    case "interval": interval = TimeInterval(val) ?? 5
                    default: break
                    }
                }
            }

            guard let dc = deviceCodeStr, let uc = userCodeStr else {
                errorMessage = "Response device code tidak lengkap"
                return
            }

            self.deviceCode = dc
            self.userCode = uc
            self.verificationURI = verificationURIStr ?? "https://github.com/login/device"
            self.pollInterval = max(interval, 5)
            self.isWaitingForApproval = true

            startPolling(clientID: clientID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling(clientID: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                if Task.isCancelled { break }

                let success = await pollOnce(clientID: clientID)
                if success { break }
            }
        }
    }

    private func pollOnce(clientID: String) async -> Bool {
        guard let deviceCode else { return true }

        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            var accessToken: String?
            var errorCode: String?

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                accessToken = json["access_token"] as? String
                errorCode = json["error"] as? String
            } else if let str = String(data: data, encoding: .utf8) {
                let pairs = str.components(separatedBy: "&")
                for pair in pairs {
                    let kv = pair.components(separatedBy: "=")
                    guard kv.count == 2 else { continue }
                    if kv[0] == "access_token" {
                        accessToken = kv[1].removingPercentEncoding ?? kv[1]
                    } else if kv[0] == "error" {
                        errorCode = kv[1]
                    }
                }
            }

            if let token = accessToken {
                await MainActor.run {
                    self.token = token
                    _ = KeychainService.saveToken(token)
                    UserDefaults.standard.set(token, forKey: "github_token")
                    self.isWaitingForApproval = false
                    self.userCode = nil
                    self.deviceCode = nil
                    self.isLoading = true
                }
                do {
                    let u = try await GitHubService.shared.fetchUser(token: token)
                    await MainActor.run {
                        self.user = u
                        self.isAuthenticated = true
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Token didapat tapi /user gagal: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
                return true
            }

            if let err = errorCode {
                switch err {
                case "authorization_pending":
                    return false
                case "slow_down":
                    await MainActor.run { self.pollInterval += 5 }
                    return false
                case "expired_token", "access_denied":
                    await MainActor.run {
                        self.errorMessage = err == "access_denied" ? "Kamu menolak authorize" : "Kode expired, coba lagi"
                        self.isWaitingForApproval = false
                        self.userCode = nil
                        self.deviceCode = nil
                    }
                    return true
                default:
                    await MainActor.run {
                        self.errorMessage = "Error: \(err)"
                        self.isWaitingForApproval = false
                    }
                    return true
                }
            }
        } catch {
            // keep polling
        }
        return false
    }

    func cancelDeviceFlow() {
        pollTask?.cancel()
        pollTask = nil
        isWaitingForApproval = false
        userCode = nil
        deviceCode = nil
        errorMessage = nil
    }

    // MARK: - PAT Login (fallback)

    func loginWithPAT(_ pat: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Token kosong"
            return
        }

        token = trimmed
        do {
            let u = try await GitHubService.shared.fetchUser(token: trimmed)
            user = u
            _ = KeychainService.saveToken(trimmed)
            UserDefaults.standard.set(trimmed, forKey: "github_token")
            isAuthenticated = true
        } catch {
            token = nil
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        pollTask?.cancel()
        KeychainService.deleteToken()
        UserDefaults.standard.removeObject(forKey: "github_token")
        token = nil
        user = nil
        isAuthenticated = false
        userCode = nil
        isWaitingForApproval = false
    }

    private func fetchUser() async {
        guard let token else { return }
        do {
            user = try await GitHubService.shared.fetchUser(token: token)
        } catch {
            logout()
        }
    }
}
