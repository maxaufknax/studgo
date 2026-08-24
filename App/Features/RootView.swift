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
        case .unavailable(let message):
            UnreachableView(message: message)
        case .signedIn(let user):
            MainTabView(user: user)
                // Beim Kontowechsel alle Ansichten frisch aufbauen.
                .id(user.id)
        }
    }
}

struct MainTabView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

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
                .badge(auth.unreadCount)
            MoreView(user: user)
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
        }
        .task { await auth.loadSemTypes() }
    }
}

/// Angemeldet, aber der Server antwortet nicht — etwa beim ersten Start ohne
/// Empfang. Abmelden wäre hier die falsche Antwort: die Sitzung ist in
/// Ordnung, nur die Leitung nicht.
struct UnreachableView: View {
    let message: String
    @Environment(AuthStore.self) private var auth
    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label("Stud.IP nicht erreichbar", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button {
                Task {
                    isRetrying = true
                    await auth.retryProfile()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Erneut versuchen")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)

            Button("Abmelden", role: .destructive) { auth.signOut() }
                .font(.footnote)
        }
    }
}
