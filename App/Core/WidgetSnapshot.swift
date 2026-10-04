import Foundation

/// Der Stand, den die Widgets zeigen - als schlichtes, kodierbares Stück
/// geschrieben, damit App und Widget-Erweiterung ihn **ohne gemeinsames
/// Ziel** übersetzen können: Die Extension bekommt genau diese eine Datei
/// (siehe `project.yml`), nicht den ganzen Rest der App.
///
/// **Warum ein Schnappschuss und kein Live-Zugriff:** Eine Widget-
/// Erweiterung läuft im eigenen Prozess, ohne Anmeldung und meist ohne
/// Netz. Widgets fragen deshalb nie selbst beim Stud.IP-Server an - sie
/// lesen, was die App beim letzten Lauf hinterlegt hat, und die Timeline
/// weiß anhand `updatedAt`, wie frisch das ist.
struct WidgetSnapshot: Codable, Equatable {
    struct NextEvent: Codable, Equatable {
        let title: String
        let start: Date
        let end: Date
        var location: String?
    }

    /// Bis 1.8.1 der **einzige** Termin im Schnappschuss. Bleibt stehen, damit
    /// ein Stand, den eine ältere Fassung geschrieben hat, nach dem Update
    /// lesbar bleibt - bis die App ihn beim nächsten Öffnen ersetzt.
    var nextEvent: NextEvent?
    /// Die kommenden Termine samt dem laufenden, chronologisch - seit 1.8.2.
    ///
    /// **Warum eine Liste:** Mit nur einem Termin stand nach dessen Ende ein
    /// vergangener „Nächster Termin" auf dem Sperrbildschirm, bis die App
    /// wieder geöffnet wurde. Mit der Liste rechnet die Timeline im Voraus,
    /// wann welcher Termin dran ist, und springt von selbst weiter.
    /// Optional, weil ältere Schnappschüsse das Feld nicht kennen.
    var upcoming: [NextEvent]?
    var unreadMessages: Int
    var updatedAt: Date

    init(nextEvent: NextEvent? = nil,
         upcoming: [NextEvent]? = nil,
         unreadMessages: Int,
         updatedAt: Date) {
        self.nextEvent = nextEvent
        self.upcoming = upcoming
        self.unreadMessages = unreadMessages
        self.updatedAt = updatedAt
    }

    /// Alle bekannten Termine, chronologisch: die Liste, oder bei einem
    /// Schnappschuss aus 1.8.1 der eine.
    var events: [NextEvent] {
        (upcoming ?? nextEvent.map { [$0] } ?? []).sorted { $0.start < $1.start }
    }

    /// Was zum Zeitpunkt `date` gezeigt wird: der laufende Termin, sonst der
    /// nächste - dieselbe Regel wie die Karte auf „Heute“.
    ///
    /// Ein Termin gilt bis **vor** seinem Ende als laufend. Zum Endzeitpunkt
    /// legt die Timeline einen Eintrag an; dort soll schon der nächste stehen,
    /// nicht der eben beendete mit „endet in 0 Min.“.
    func current(at date: Date) -> NextEvent? {
        let all = events
        if let running = all.first(where: { $0.start <= date && date < $0.end }) {
            return running
        }
        return all.first { $0.start > date }
    }

    /// Läuft der gezeigte Termin zum Zeitpunkt `date` schon?
    func isRunning(_ event: NextEvent, at date: Date) -> Bool {
        event.start <= date && date < event.end
    }

    /// Was nach dem gezeigten Termin kommt - für „Danach“ im mittleren Widget.
    func following(at date: Date, limit: Int) -> [NextEvent] {
        let shown = current(at: date)
        return Array(events
            .filter { $0.start > date && $0 != shown }
            .prefix(limit))
    }

    /// Wann sich die Anzeige ändert: Beginn und Ende jedes Termins nach
    /// `date`. Genau dort legt die Timeline Einträge an.
    func changeDates(after date: Date, limit: Int = 40) -> [Date] {
        Array(Set(events.flatMap { [$0.start, $0.end] })
            .filter { $0 > date }
            .sorted()
            .prefix(limit))
    }

    /// Wählt aus, was in den Schnappschuss wandert: Termine, die noch nicht
    /// vorbei sind, höchstens `horizon` voraus und höchstens `limit` Stück.
    ///
    /// Sieben Tage tragen über ein Wochenende ohne Öffnen der App hinweg; mehr
    /// bläht nur den Schnappschuss auf, den die Erweiterung bei jedem Eintrag
    /// liest.
    static func upcoming(_ candidates: [NextEvent],
                         now: Date,
                         horizon: TimeInterval = 7 * 24 * 3600,
                         limit: Int = 16) -> [NextEvent] {
        Array(candidates
            .filter { $0.end > now && $0.start < now.addingTimeInterval(horizon) }
            .sorted { $0.start < $1.start }
            .prefix(limit))
    }
}

/// Lesen und Schreiben des Schnappschusses - über eine App-Group geteilt,
/// denn App und Widget-Erweiterung teilen sich keinen Ablageort von selbst.
///
/// Die Kennung muss in `project.yml`, im Entwicklerportal und in App Store
/// Connect übereinstimmen (einmalig, siehe docs/CODEMAGIC.md). Im Portal ist
/// die Gruppe **ohne** Präfix angemeldet, in den Entitlements und im Code
/// trägt sie das übliche `group.` davor - Apple ergänzt das Präfix selbst,
/// wenn es die Provisioning-Profile schreibt. Fehlt die
/// Gruppe - etwa in einem unsignierten Schnellbau -, greift der Zweitweg
/// über die normalen Benutzerdaten: Das Widget sieht dann nichts, die App
/// bleibt aber benutzbar; ein Defekt im Widget darf nie die App kosten.
enum WidgetSnapshotStore {
    static let appGroupID = "group.de.maxaufknax.studgo.shared"
    private static let key = "studgo.widget.snapshot"

    private static let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Beim Abmelden muss der Schnappschuss weg - er trägt Termine und
    /// Nachrichten des bisherigen Kontos auf den Sperrbildschirm.
    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
