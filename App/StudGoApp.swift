import SwiftUI

@main
struct StudGoApp: App {
    @State private var auth = AuthStore()
    @State private var theme = ThemeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(theme)
                // Akzentfarbe und Erscheinungsbild wirken auf die gesamte
                // Oberfläche — deshalb ganz oben und nicht je Ansicht.
                .tint(theme.theme.accent)
                .preferredColorScheme(theme.appearance.colorScheme)
                .task { await auth.restore() }
        }
    }
}
