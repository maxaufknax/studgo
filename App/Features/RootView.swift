import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

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
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: NotificationRouter
    /// Bei einem Themenwechsel bauen sich die Reiter mit neuen Farben auf -
    /// `Tint.color(_:)` verzeichnet selbst nichts, siehe `Palette`.
    @ObservedObject private var palette = Palette.shared

    @State private var selection: AppTab = MainTabView.initialTab

    /// Der Reiter beim Start - immer „Heute“, außer in Debug-Bauten mit dem
    /// Startargument `-studgo.initialTab <plan|kurse|postfach|campus>`.
    ///
    /// Nur für die Bildschirmfotos (tools/screenshots.sh): `simctl openurl`
    /// fragt erst „In StudGo öffnen?“, und diese Rückfrage kann kein Skript
    /// bestätigen. In Release-Bauten fällt der Zweig ganz weg.
    private static var initialTab: AppTab {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "studgo.initialTab") {
        case "plan": return .schedule
        case "kurse": return .courses
        case "postfach": return .postfach
        case "campus": return .campus
        default: return .today
        }
        #else
        return .today
        #endif
    }
    /// Die Einführung - einmal je Gerät, gleich nach der ersten Anmeldung.
    @State private var showsOnboarding = false

    /// Fünf Reiter, benannt nach dem, was dahinter liegt, nicht nach dem
    /// Stud.IP-Fachbegriff: „Postfach" statt „Nachrichten", weil dort auch
    /// die Blubber-Unterhaltungen liegen, und „Campus" statt „Mehr", weil
    /// „Mehr" nichts darüber verrät, was man dort findet. Profil und
    /// Einstellungen sitzen als Knopf oben auf „Heute" - ein eigener Reiter
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
        .onChange(of: router.target) { target in
            guard let target else { return }
            selection = target
            router.target = nil
        }
        // Das App-Symbol trägt die Zahl der ungelesenen Nachrichten mit.
        .task(id: auth.unreadCount) { await Notifications.setBadge(auth.unreadCount) }
        // Irgendwann bittet die App um eine App-Store-Bewertung - wann genau,
        // entscheidet `ReviewGate`; hier steht nur der Aufruf, einmal je
        // App-Start und nur für angemeldete Konten.
        .task {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
            ReviewPrompt.registerLaunch(scene: scene)
        }
        .task {
            if !OnboardingView.hasBeenSeen { showsOnboarding = true }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView()
        }
    }
}

/// Angemeldet, aber der Server antwortet nicht - etwa beim ersten Start ohne
/// Empfang. Abmelden wäre hier die falsche Antwort: die Sitzung ist in
/// Ordnung, nur die Leitung nicht.
struct UnreachableView: View {
    let message: String
    @EnvironmentObject private var auth: AuthStore
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
