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
    @Environment(NotificationRouter.self) private var router

    @State private var selection: AppTab = .today

    /// Fünf Reiter, benannt nach dem, was dahinter liegt, nicht nach dem
    /// Stud.IP-Fachbegriff: „Postfach" statt „Nachrichten", weil dort auch
    /// die Blubber-Unterhaltungen liegen, und „Campus" statt „Mehr", weil
    /// „Mehr" nichts darüber verrät, was man dort findet. Profil und
    /// Einstellungen sitzen als Knopf oben auf „Heute" — ein eigener Reiter
    /// dafür wäre der am seltensten benutzte von fünf.
    ///
    /// Die `selection`-Bindung trägt zweierlei: die angetippte Benachrichtigung
    /// (über den `NotificationRouter`) landet im richtigen Reiter, und das
    /// App-Symbol zeigt die ungelesenen Nachrichten.
    var body: some View {
        TabView(selection: $selection) {
            TodayView(user: user)
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }
                .tag(AppTab.today)

            ScheduleView(user: user)
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.schedule)

            CoursesView(user: user)
                .tabItem { Label("Kurse", systemImage: "books.vertical.fill") }
                .tag(AppTab.courses)

            PostfachView(user: user)
                .tabItem { Label("Postfach", systemImage: "tray.full.fill") }
                .badge(auth.unreadCount)
                .tag(AppTab.postfach)

            CampusView(user: user)
                .tabItem { Label("Campus", systemImage: "person.2.fill") }
                .tag(AppTab.campus)
        }
        .task { await auth.loadSemTypes() }
        // Eine angetippte Mitteilung schaltet den Reiter um, dann Merker leeren.
        .onChange(of: router.target) { _, target in
            guard let target else { return }
            selection = target
            router.target = nil
        }
        // Das App-Symbol trägt die Zahl der ungelesenen Nachrichten mit.
        .task(id: auth.unreadCount) { await Notifications.setBadge(auth.unreadCount) }
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
