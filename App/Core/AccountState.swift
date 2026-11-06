import Foundation

/// Alles, was in den Standardeinstellungen vom Konto abhängt - und deshalb
/// beim Sitzungsende verschwinden muss.
///
/// **Warum eine Stelle:** PRIVACY.md („Deine Rechte“) verspricht, dass Abmelden
/// die Daten des Kontos auf dem Gerät vollständig löscht. Bis 1.9 stimmte das
/// nur teilweise: Tokens und Zwischenspeicher gingen, aber die Blockliste, die
/// ausgeblendeten Termine, die Merker der Hintergrund-Mitteilungen und die
/// Annahme der Nutzungsbedingungen blieben liegen - das nächste Konto auf
/// demselben Gerät hätte sie gesehen. Die Schlüssel liegen deshalb an dieser
/// Stelle gesammelt und in reiner Form, damit das Aufräumen an einem Ort
/// passiert und der Testsatz prüfen kann, dass alles Kontogebundene geht und
/// reine Anzeigeeinstellungen (Farbwelt, Mensa-Wahl und so weiter) bleiben.
///
/// Die Speicher, denen die Schlüssel gehören, schreiben weiter über ihre
/// eigenen Schlüssel; die Namen hier sind dieselben Konstanten, nicht
/// abgeschrieben.
enum AccountState {

    enum Key {
        /// Dass die Nutzungsbedingungen angenommen wurden. Ein neues Konto
        /// (oder dasselbe nach `seit 1.9`-Aufräumen) stimmt erneut zu.
        static let termsVersion = "studgo.moderation.termsVersion"

        /// Wen die Person blockiert hat - Namen und Kennungen, also
        /// personenbezogen auf beide Seiten.
        static let blockedIDs = "studgo.moderation.blockedIDs"
        static let blockedNames = "studgo.moderation.blockedNames"

        /// Welche Turnusfenster ausgeblendet sind: eine persönliche Meinung
        /// über Veranstaltungen des Kontos.
        static let hiddenEvents = "studgo.calendar.hiddenEvents"

        /// Bis wohin der Hintergrundlauf schon gemeldet hat. Ein neues Konto
        /// wäre sonst stumm (der Merker stünde weit in der Zukunft) - oder
        /// bekäme beim ersten Lauf alles Alte auf einmal.
        static let lastNotifiedMessage = "studgo.notify.lastMessage"
        static let lastNotifiedActivity = "studgo.notify.lastActivity"

        /// Dasselbe für „Neu in deinen Kursen“ samt Stummschaltung je
        /// Veranstaltung - beides Aussagen über die belegten Kurse.
        static let lastNotifiedCourseNews = "studgo.notify.courseNews.last"
        static let mutedCourses = "studgo.notify.courseNews.muted"

        /// Wann „Heute“ zuletzt geöffnet war - der Maßstab für „Neu seit
        /// deinem letzten Besuch“.
        static let lastVisit = "studgo.today.lastVisit"

        /// Der Schalter des Kalender-Abgleichs. Sein Kalender wird am
        /// Sitzungsende gelöscht - ein stehengelassener Schalter würde beim
        /// nächsten Konto ohne Rückfrage wieder einsynchronisieren.
        static let calendarSync = "studgo.calendar.sync"
    }

    /// Alle kontogebundenen Schlüssel - die Grundlage fürs Aufräumen und für
    /// den Test, der neue Schlüssel hier nicht vergessen lässt.
    static var accountBoundKeys: [String] {
        [Key.termsVersion,
         Key.blockedIDs,
         Key.blockedNames,
         Key.hiddenEvents,
         Key.lastNotifiedMessage,
         Key.lastNotifiedActivity,
         Key.lastNotifiedCourseNews,
         Key.mutedCourses,
         Key.lastVisit,
         Key.calendarSync]
    }

    /// Sagt den lebenden Speichern, dass ihr Konto gerade endet: Sie setzen
    /// ihre Werte im Arbeitsspeicher zurück, sonst klänge die Ansicht nach
    /// einer Anmeldung ohne Neustart noch mit den Daten des vorigen Kontos.
    static let dataDidReset = Notification.Name("studgo.account.dataReset")

    /// Entfernt alle kontogebundenen Schlüssel aus den übergebenen
    /// Standardeinstellungen. Für die laufenden Instanzen ist `dataDidReset`
    /// da - wer beides nur halb aufruft, hat bald zwei Wahrheiten auf einem
    /// Gerät.
    static func removeFrom(_ defaults: UserDefaults) {
        for key in accountBoundKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
