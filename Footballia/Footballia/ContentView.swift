import SwiftUI

struct ContentView: View {
    @State private var service = FootballiaService()

    var body: some View {
        Group {
            if service.isCheckingSession {
                ZStack {
                    Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()
                    ProgressView().tint(.green)
                }
            } else if service.isLoggedIn {
                MainView()
                    .environment(service)
            } else {
                LoginView()
                    .environment(service)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: service.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: service.isCheckingSession)
        .task {
            await service.restoreSession()
            if !service.isLoggedIn, let creds = FootballiaService.devCredentials() {
                await service.login(email: creds.email, password: creds.password)
            }
        }
    }
}

#Preview {
    ContentView()
}
