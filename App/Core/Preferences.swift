import Observation
import SwiftUI

/// Einstellungen, die kein Aussehen betreffen — Benachrichtigungen und der
/// Umgang mit der Weboberfläche.
///
/// Getrennt von `ThemeStore`, weil das eine die Optik regelt und das andere
/// das Verhalten. Beide liegen in `UserDefaults`: Es sind Vorlieben, keine
/// Geheimnisse.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let webSession = "studgo.web.sharesSession"
        static let eventReminders = "studgo.notify.events"
        static let leadMinutes = "studgo.notify.leadMinutes"
        static let mailbox = "studgo.notify.mailbox"
        static let quietWeekend = "studgo.notify.quietWeekend"
        static let lastMessageDate = "studgo.notify.lastMessage"
        static let lastActivityDate = "studgo.notify.lastActivity"
    }

    // MARK: - Weboberfläche

    /// Darf die Stud.IP-Anmeldung ihre Sitzung mit Safari teilen?
    ///
    /// **Der Handel dahinter:** Mit `true` läuft die Anmeldung in der
    /// gewöhnlichen Safari-Sitzung. Da Stud.IP an der LUH über **Shibboleth**
    /// (`login.uni-hannover.de`) anmeldet, ist man danach auch auf jeder
    /// Seite angemeldet, die StudGo als Rückfallebene öffnet — Eintragen,
    /// Profilbild, QIS-nahes. Kein zweites Mal Kennung eingeben.
    ///
    /// Mit `false` (`prefersEphemeralWebBrowserSession`) bleibt kein Cookie in
    /// Safari zurück: Abmelden in StudGo beendet dann wirklich alles, dafür
    /// verlangt jede Webseite eine eigene Anmeldung.
    ///
    /// Vorgabe ist `true` — der Weg, auf dem die Rückfallebenen ohne Reibung
    /// funktionieren. Wer das nicht will, stellt es um; die Einstellung sagt
    /// beides klar.
    var sharesWebSession: Bool {
        didSet { defaults.set(sharesWebSession, forKey: Key.webSession) }
    }

    // MARK: - Benachrichtigungen

    /// Erinnerung vor Vorlesungen und Terminen.
    var eventReminders: Bool {
        didSet { defaults.set(eventReminders, forKey: Key.eventReminders) }
    }

    /// Wie viele Minuten vorher. 0 heißt: pünktlich zum Beginn.
    var leadMinutes: Int {
        didSet { defaults.set(leadMinutes, forKey: Key.leadMinutes) }
    }

    /// Hinweis auf neue Nachrichten und Beiträge, wenn die App im Hintergrund
    /// nachsehen darf.
    var mailboxAlerts: Bool {
        didSet { defaults.set(mailboxAlerts, forKey: Key.mailbox) }
    }

    /// Am Wochenende still bleiben. Für Kursfäden, die samstags weiterlaufen.
    var quietWeekend: Bool {
        didSet { defaults.set(quietWeekend, forKey: Key.quietWeekend) }
    }

    /// Bis wohin schon gemeldet wurde — verhindert, dass dieselbe Nachricht
    /// nach jedem Hintergrundlauf erneut aufpoppt.
    var lastNotifiedMessage: Date {
        didSet { defaults.set(lastNotifiedMessage.timeIntervalSince1970, forKey: Key.lastMessageDate) }
    }

    var lastNotifiedActivity: Date {
        didSet { defaults.set(lastNotifiedActivity.timeIntervalSince1970, forKey: Key.lastActivityDate) }
    }

    /// Sind überhaupt Benachrichtigungen gewünscht?
    var wantsNotifications: Bool { eventReminders || mailboxAlerts }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: `bool` kann „nie gesetzt"
        // nicht von „ausdrücklich aus" unterscheiden und lieferte für beides
        // `false` — die Vorgabe `true` käme nie zum Zug.
        sharesWebSession = defaults.object(forKey: Key.webSession) as? Bool ?? true
        eventReminders = defaults.object(forKey: Key.eventReminders) as? Bool ?? false
        mailboxAlerts = defaults.object(forKey: Key.mailbox) as? Bool ?? false
        quietWeekend = defaults.object(forKey: Key.quietWeekend) as? Bool ?? false
        leadMinutes = defaults.object(forKey: Key.leadMinutes) as? Int ?? 20
        lastNotifiedMessage = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastMessageDate))
        lastNotifiedActivity = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastActivityDate))
    }

    /// Mögliche Vorlaufzeiten für die Auswahl.
    static let leadOptions = [0, 5, 10, 15, 20, 30, 45, 60]

    static func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "zum Beginn"
        case 60: return "1 Stunde vorher"
        default: return "\(minutes) Minuten vorher"
        }
    }

    /// Der Wert, den `OAuthService` beim Anmelden braucht — ohne dass der
    /// Dienst den ganzen Store kennen müsste.
    ///
    /// **Warum ein statischer Umweg:** `OAuthService` läuft außerhalb der
    /// SwiftUI-Umgebung; ein `@Environment` steht dort nicht zur Verfügung,
    /// und die Einstellung als Parameter durch `AuthStore.signIn()` zu
    /// reichen hieße, sie durch drei Schichten zu fädeln, die sie sonst nichts
    /// angeht.
    static var sharesWebSessionSetting: Bool {
        UserDefaults.standard.object(forKey: Key.webSession) as? Bool ?? true
    }
}
