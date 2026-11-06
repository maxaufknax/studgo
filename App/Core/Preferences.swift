import SwiftUI

/// Einstellungen, die kein Aussehen betreffen - Benachrichtigungen und der
/// Umgang mit der Weboberfläche.
///
/// Getrennt von `ThemeStore`, weil das eine die Optik regelt und das andere
/// das Verhalten. Beide liegen in `UserDefaults`: Es sind Vorlieben, keine
/// Geheimnisse.
///
/// `ObservableObject` statt des `@Observable`-Makros, weil die App auch auf
/// iOS 16 läuft - das `Observation`-Framework gibt es erst ab iOS 17.
@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let webSession = "studgo.web.sharesSession"
        static let eventReminders = "studgo.notify.events"
        static let leadMinutes = "studgo.notify.leadMinutes"
        static let mailbox = "studgo.notify.mailbox"
        static let quietWeekend = "studgo.notify.quietWeekend"
        // Konto­gebunden - beim Sitzungsende weg (siehe `AccountState`).
        static let lastMessageDate = AccountState.Key.lastNotifiedMessage
        static let lastActivityDate = AccountState.Key.lastNotifiedActivity
        static let mensaCanteen = "studgo.mensa.canteen"
        static let calendarSync = AccountState.Key.calendarSync
        // „Neu in deinen Kursen“ - Schalter reine Vorlieben dieses Geräts,
        // Merker und Stummschaltung konto­gebunden.
        static let courseNews = "studgo.notify.courseNews"
        static let lastCourseNewsDate = AccountState.Key.lastNotifiedCourseNews
        static let mutedCourses = AccountState.Key.mutedCourses
        static let lastVisit = AccountState.Key.lastVisit
        // Ausfallsabgleich: Schalter reine Vorliebe, Merker konto­gebunden.
        static let cancellations = "studgo.notify.cancellations"
        static let cancellationReview = AccountState.Key.lastCancellationReview
        static let announcedCancellations = AccountState.Key.announcedCancellations
    }

    // MARK: - Weboberfläche

    /// Darf die Stud.IP-Anmeldung ihre Sitzung mit Safari teilen?
    ///
    /// **Der Handel dahinter:** Mit `true` läuft die Anmeldung in der
    /// gewöhnlichen Safari-Sitzung. Da Stud.IP an der LUH über **Shibboleth**
    /// (`login.uni-hannover.de`) anmeldet, ist man danach auch auf jeder
    /// Seite angemeldet, die StudGo als Rückfallebene öffnet - Eintragen,
    /// Profilbild, QIS-nahes. Kein zweites Mal Kennung eingeben.
    ///
    /// Mit `false` (`prefersEphemeralWebBrowserSession`) bleibt kein Cookie in
    /// Safari zurück: Abmelden in StudGo beendet dann wirklich alles, dafür
    /// verlangt jede Webseite eine eigene Anmeldung.
    ///
    /// Vorgabe ist `true` - der Weg, auf dem die Rückfallebenen ohne Reibung
    /// funktionieren. Wer das nicht will, stellt es um; die Einstellung sagt
    /// beides klar.
    @Published var sharesWebSession: Bool {
        didSet { defaults.set(sharesWebSession, forKey: Key.webSession) }
    }

    // MARK: - Benachrichtigungen

    /// Erinnerung vor Vorlesungen und Terminen.
    @Published var eventReminders: Bool {
        didSet { defaults.set(eventReminders, forKey: Key.eventReminders) }
    }

    /// Wie viele Minuten vorher. 0 heißt: pünktlich zum Beginn.
    @Published var leadMinutes: Int {
        didSet { defaults.set(leadMinutes, forKey: Key.leadMinutes) }
    }

    /// Hinweis auf neue Nachrichten und Beiträge, wenn die App im Hintergrund
    /// nachsehen darf.
    @Published var mailboxAlerts: Bool {
        didSet { defaults.set(mailboxAlerts, forKey: Key.mailbox) }
    }

    /// Über frisch abgesagte Sitzungen informieren, wenn der seltene
    /// Ausfallsabgleich im Hintergrund läuft. **Vorgabe aus** (neue Art von
    /// Mitteilung) und nur für die nächsten sieben Tage, je Sitzung einmal.
    @Published var cancellationAlerts: Bool {
        didSet { defaults.set(cancellationAlerts, forKey: Key.cancellations) }
    }

    /// Wann der Ausfallsabgleich zuletzt gelaufen ist - Drossel auf etwa
    /// einmal am Tag. Wird gesetzt, sobald der Lauf *beendet* ist (mit oder
    /// ohne Befund): Ein gescheiterter Abruf soll beim nächsten Wecken
    /// erneut probieren, aber nicht jede Stunde.
    var lastCancellationReview: Date {
        didSet { defaults.set(lastCancellationReview.timeIntervalSince1970, forKey: Key.cancellationReview) }
    }

    /// Bereits über den Ausfall informierte Sitzungen, gesäubert um alles,
    /// was der Kalender nicht mehr kennt.
    @Published private(set) var announcedCancellations: Set<String> {
        didSet { defaults.set(announcedCancellations.sorted(), forKey: Key.announcedCancellations) }
    }

    func replaceAnnouncedCancellations(_ ids: Set<String>) {
        announcedCancellations = ids
    }

    /// Am Wochenende still bleiben. Für Kursfäden, die samstags weiterlaufen.
    @Published var quietWeekend: Bool {
        didSet { defaults.set(quietWeekend, forKey: Key.quietWeekend) }
    }

    /// Auf Neuigkeiten aus den Kursen hinweisen, wenn der Hintergrundlauf
    /// läuft. **Vorgabe aus** ( siehe „Neue Benachrichtigungsarten sind
    /// standardmäßig aus“): Der Strom aus Dateien, Forum, Wiki und
    /// Ankündigungen füllt eine Mitteilung schnell, und niemand hat darum
    /// gebeten, bevor der erste Lauf kommt.
    @Published var courseNewsAlerts: Bool {
        didSet { defaults.set(courseNewsAlerts, forKey: Key.courseNews) }
    }

    /// Welche Veranstaltungen keine Mitteilung mehr auslösen dürfen - die
    /// Stummschaltung pro Kurs. Der Bereich auf „Heute“ zeigt sie trotzdem.
    private(set) var mutedCourseIDs: Set<String> {
        didSet { defaults.set(mutedCourseIDs.sorted(), forKey: Key.mutedCourses) }
    }

    func isMuted(_ courseID: String) -> Bool {
        mutedCourseIDs.contains(courseID)
    }

    func setMuted(_ muted: Bool, courseID: String) {
        if muted { mutedCourseIDs.insert(courseID) } else { mutedCourseIDs.remove(courseID) }
    }

    /// Bis wohin der Hintergrundlauf über Kursnachrichten gemeldet hat. Wird
    /// erst nach einem erfolgreichen Lauf weitergesetzt - ein gescheiterter
    /// darf nichts als „gemeldet“ markieren.
    var lastNotifiedCourseNews: Date {
        didSet { defaults.set(lastNotifiedCourseNews.timeIntervalSince1970, forKey: Key.lastCourseNewsDate) }
    }

    /// Wann „Heute“ zuletzt geladen war - der Maßstab für „Neu seit deinem
    /// letzten Besuch“. Vorgabe weit in der Vergangenheit: Der Bereich greift
    /// dann auf `CourseNews.fallbackHorizon` zurück.
    var lastVisit: Date {
        didSet { defaults.set(lastVisit.timeIntervalSince1970, forKey: Key.lastVisit) }
    }

    /// Bis wohin schon gemeldet wurde - verhindert, dass dieselbe Nachricht
    /// nach jedem Hintergrundlauf erneut aufpoppt.
    var lastNotifiedMessage: Date {
        didSet { defaults.set(lastNotifiedMessage.timeIntervalSince1970, forKey: Key.lastMessageDate) }
    }

    var lastNotifiedActivity: Date {
        didSet { defaults.set(lastNotifiedActivity.timeIntervalSince1970, forKey: Key.lastActivityDate) }
    }

    // MARK: - Kalender

    /// Den Stundenplan in den iOS-Kalender „StudGo“ übertragen und aktuell
    /// halten (siehe `CalendarSync`). Vorgabe aus: Der Kalender eines Geräts
    /// ist privat, dorthin schreibt StudGo nur auf ausdrücklichen Wunsch.
    @Published var calendarSync: Bool {
        didSet { defaults.set(calendarSync, forKey: Key.calendarSync) }
    }

    // MARK: - Mensa

    /// Welche Mensa der Speiseplan zeigt. Kennungen nach OpenMensa; die
    /// Hauptmensa (6) ist die naheliegendste Vorgabe.
    @Published var mensaCanteenID: Int {
        didSet { defaults.set(mensaCanteenID, forKey: Key.mensaCanteen) }
    }

    /// Sind überhaupt Benachrichtigungen gewünscht?
    var wantsNotifications: Bool { eventReminders || mailboxAlerts || courseNewsAlerts }

    private let defaults: UserDefaults
    /// Sitzungsende: Merker und Kalender-Schalter zurückholen, sobald ihr
    /// Konto endet - die Instanz der Oberfläche lebt darüber hinaus.
    private var sessionReset: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: `bool` kann „nie gesetzt"
        // nicht von „ausdrücklich aus" unterscheiden und lieferte für beides
        // `false` - die Vorgabe `true` käme nie zum Zug.
        sharesWebSession = defaults.object(forKey: Key.webSession) as? Bool ?? true
        eventReminders = defaults.object(forKey: Key.eventReminders) as? Bool ?? false
        mailboxAlerts = defaults.object(forKey: Key.mailbox) as? Bool ?? false
        // Ohne diese Zeile wäre die Initialisierung unvollständig - ein Fehler,
        // den nur der echte Swift-Compiler sieht, weil diese Datei im
        // Linux-Testsatz ausgeschlossen ist. Zur gleichen Stelle wie `mailboxAlerts`,
        // damit künftige Mitteilungsarten daneben weiterwachsen.
        courseNewsAlerts = defaults.object(forKey: Key.courseNews) as? Bool ?? false
        quietWeekend = defaults.object(forKey: Key.quietWeekend) as? Bool ?? false
        leadMinutes = defaults.object(forKey: Key.leadMinutes) as? Int ?? 20
        lastNotifiedMessage = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastMessageDate))
        lastNotifiedActivity = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastActivityDate))
        mutedCourseIDs = Set(defaults.stringArray(forKey: Key.mutedCourses) ?? [])
        lastNotifiedCourseNews = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastCourseNewsDate))
        lastVisit = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastVisit))
        cancellationAlerts = defaults.object(forKey: Key.cancellations) as? Bool ?? false
        lastCancellationReview = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.cancellationReview))
        announcedCancellations = Set(defaults.stringArray(forKey: Key.announcedCancellations) ?? [])
        mensaCanteenID = defaults.object(forKey: Key.mensaCanteen) as? Int ?? 6
        calendarSync = defaults.object(forKey: Key.calendarSync) as? Bool ?? false
        sessionReset = NotificationCenter.default.addObserver(
            forName: AccountState.dataDidReset, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.applySessionReset() }
            }
    }

    deinit {
        // Der Beobachter hängt am globalen Zentrum; ohne das Abmelden lief er
        // nach dem Wegwerfen der Instanz weiter.
        if let sessionReset { NotificationCenter.default.removeObserver(sessionReset) }
    }

    /// Am Sitzungsende zurück auf den Stand der gelöschten Schlüssel: Der
    /// Kalender-Abgleich ist aus (sein Kalender wurde gerade entfernt), die
    /// Meldemerker stehen auf dem Anfang. Die übrigen Einstellungen sind
    /// reine Vorlieben dieses Geräts und bleiben, wo sie stehen.
    ///
    /// **Kein Objektzugriff, sondern NeuLesen:** Die Schlüssel löscht
    /// `AccountState.removeFrom`, nicht diese Runde - deshalb auch kein
    /// Schreiben, nur das Zurückholen in die veröffentlichten Werte.
    private func applySessionReset() {
        calendarSync = defaults.object(forKey: Key.calendarSync) as? Bool ?? false
        lastNotifiedMessage = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastMessageDate))
        lastNotifiedActivity = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastActivityDate))
        lastNotifiedCourseNews = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastCourseNewsDate))
        lastVisit = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.lastVisit))
        mutedCourseIDs = Set(defaults.stringArray(forKey: Key.mutedCourses) ?? [])
        lastCancellationReview = Date(timeIntervalSince1970:
            defaults.double(forKey: Key.cancellationReview))
        announcedCancellations = Set(defaults.stringArray(forKey: Key.announcedCancellations) ?? [])
    }

    /// Ob eine Funktion überhaupt den Hintergrundlauf braucht - beim Start
    /// und nach einer erneuten Anmeldung ohne Neustart die Bedingung dafür,
    /// den Weckruf überhaupt zu planen (siehe `AuthStore`).
    static var wantsBackgroundRefresh: Bool {
        let mailbox = UserDefaults.standard.object(forKey: Key.mailbox) as? Bool ?? false
        let courseNews = UserDefaults.standard.object(forKey: Key.courseNews) as? Bool ?? false
        return mailbox || courseNews
    }

    /// Mögliche Vorlaufzeiten für die Auswahl.
    static let leadOptions = [0, 5, 10, 15, 20, 30, 45, 60]

    static func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return String(localized: "zum Beginn")
        case 60: return String(localized: "1 Stunde vorher")
        default: return String(localized: "\(minutes) Minuten vorher")
        }
    }

    /// Der Wert, den `OAuthService` beim Anmelden braucht - ohne dass der
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
