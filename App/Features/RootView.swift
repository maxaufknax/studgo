import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        switch auth.state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Anmeldung wird geprüft…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .signedOut:
            LoginView()
        case .signedIn(let user):
            MainTabView(user: user)
                // Beim Kontowechsel alle Ansichten frisch aufbauen.
                .id(user.id)
        }
    }
}

struct MainTabView: View {
    let user: StudIPUser

    var body: some View {
        TabView {
            TodayView(user: user)
                .tabItem { Label("Heute", systemImage: "sun.max") }
            ScheduleView(user: user)
                .tabItem { Label("Plan", systemImage: "calendar") }
            CoursesView(user: user)
                .tabItem { Label("Kurse", systemImage: "books.vertical") }
            MessagesView(user: user)
                .tabItem { Label("Nachrichten", systemImage: "envelope") }
            MoreView(user: user)
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
        }
    }
}
