import SwiftUI

@main
struct StudGoApp: App {
    @State private var auth = AuthStore()
    @State private var theme = ThemeStore()
    @State private var preferences = Preferences()

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
