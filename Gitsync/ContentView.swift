import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        Group {
            if auth.isAuthenticated {
                HomeView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
    }
}
