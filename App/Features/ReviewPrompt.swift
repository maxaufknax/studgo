import SwiftUI
import StoreKit

/// Zählt die Starts und bittet irgendwann um eine App-Store-Bewertung.
///
/// **Warum überhaupt zählen:** Der Bewertungsdialog von iOS
/// (`AppStore.requestReview`) lässt sich nicht erzwingen und wird vom System
/// gedrosselt — mehr als drei Dialoge im Jahr sieht niemand. Das Limit ist
/// also nicht „fragen, so oft es geht", sondern „an einem Moment fragen, in
/// dem die Bewertung gut ausfällt". Die Regel, welcher Moment das ist, steht
/// geprüft in `ReviewGate`; diese Datei zählt nur und ruft den Dialog auf.
///
/// Der Zähler gehört niemandem sonst: Nicht der Ansicht (die verschwindet),
/// nicht dem AuthStore (Bewertungen haben mit der Anmeldung nichts zu tun).
enum ReviewPrompt {
    private enum Key {
        static let launches = "studgo.review.launches"
        static let firstLaunch = "studgo.review.firstLaunch"
        static let lastAsked = "studgo.review.lastAskedLaunch"
    }

    /// Zählt einmal je App-Start — nicht je Ansicht. `MainTabView` kann
    /// mehrfach erscheinen (Kontowechsel), gezählt wird trotzdem nur der
    /// Start.
    private static var didCountThisLaunch = false

    private static var defaults: UserDefaults { .standard }

    /// Beim Erscheinen der App rufen. Zählt den Start und bittet
    /// gegebenenfalls um die Bewertung.
    static func registerLaunch(scene: UIWindowScene?) {
        guard !didCountThisLaunch else { return }
        didCountThisLaunch = true

        let defaults = self.defaults
        let today = Calendar.current.startOfDay(for: Date())

        var launches = defaults.integer(forKey: Key.launches) + 1
        defaults.set(launches, forKey: Key.launches)

        let firstLaunch = defaults.object(forKey: Key.firstLaunch) as? Date
            ?? today
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(firstLaunch, forKey: Key.firstLaunch)
        }
        let days = Calendar.current.dateComponents([.day],
                                                    from: firstLaunch, to: today).day ?? 0
        let lastAsked = defaults.object(forKey: Key.lastAsked) as? Int

        guard ReviewGate.shouldAsk(launches: launches,
                                   daysSinceFirstLaunch: days,
                                   lastAskedLaunch: lastAsked) else { return }
        defaults.set(launches, forKey: Key.lastAsked)
        guard let scene else { return }
        AppStore.requestReview(in: scene)
    }
}
