import SwiftUI
import UserNotifications

@main
struct StudGoApp: App {
    @State private var auth = AuthStore()
    @State private var theme = ThemeStore()
    @State private var preferences = Preferences()
    // Auffangnetz: Jeder Reiter legt in seinem `StudGoStack` einen eigenen
    // `Navigator` an, der den seinen überschreibt. Dieser hier greift nur,
    // falls eine `PushLink`-Zeile je außerhalb eines solchen Stapels landete —
    // dann tut sie nichts, statt mangels Navigator abzustürzen.
    @State private var fallbackNavigator = Navigator()
    // Fängt zugestellte und angetippte Mitteilungen ab. Ohne einen Delegate
    // zeigt iOS im Vordergrund **nichts** an — genau der Fall „scheint nicht zu
    // funktionieren", weil die App beim Testen ja offen ist.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // **Muss im `init` stehen.** `BGTaskScheduler.register` verlangt, dass
        // alle Kennungen angemeldet sind, bevor die App fertig gestartet ist;
        // später abgegeben wirft es eine Ausnahme. Der Lauf baut sich seinen
        // eigenen Zustand auf (siehe `BackgroundSync`), weil iOS die App dafür
        // auch aus dem kalten Zustand starten kann — einen `AuthStore` aus der
        // Oberfläche gibt es dann noch gar nicht.
        Notifications.registerBackgroundTask {
            await BackgroundSync.run()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(theme)
                .environment(preferences)
                .environment(NotificationRouter.shared)
                .environment(fallbackNavigator)
                // Akzentfarbe und Erscheinungsbild wirken auf die gesamte
                // Oberfläche — deshalb ganz oben und nicht je Ansicht.
                .tint(theme.theme.accent)
                .preferredColorScheme(theme.appearance.colorScheme)
                .task { await auth.restore() }
                .task {
                    guard preferences.mailboxAlerts else { return }
                    Notifications.scheduleBackgroundRefresh()
                }
        }
    }
}

/// Der Brückenkopf zu `UNUserNotificationCenter`.
///
/// SwiftUI allein stellt keinen Delegate; ohne einen bleibt eine Mitteilung
/// im Vordergrund unsichtbar, und ein Tipp darauf führt nirgendwohin. Beides
/// holt dieser Adapter nach.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Vor dem Ende des Starts setzen, sonst entgeht die Mitteilung, die die
        // App gerade geweckt hat.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Im Vordergrund trotzdem als Banner zeigen — sonst käme beim Testen mit
    /// offener App scheinbar nie etwas an.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Antippen führt in den passenden Reiter — Postfach für Nachrichten und
    /// Beiträge, Plan für Terminerinnerungen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.content.threadIdentifier
        await MainActor.run {
            NotificationRouter.shared.route(threadIdentifier: identifier)
        }
    }
}
