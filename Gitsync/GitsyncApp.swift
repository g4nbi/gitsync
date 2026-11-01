import SwiftUI

@main
struct GitsyncApp: App {
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .preferredColorScheme(nil) // follow system
        }
    }
}
