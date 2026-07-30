import SwiftUI

struct ContentView: View {
    @State private var service = FootballiaService()

    var body: some View {
        Group {
            if service.isLoggedIn {
                MainView()
                    .environment(service)
            } else {
                LoginView()
                    .environment(service)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: service.isLoggedIn)
        .task {
            if let creds = FootballiaService.devCredentials() {
                await service.login(email: creds.email, password: creds.password)
            }
        }
    }
}

#Preview {
    ContentView()
}
