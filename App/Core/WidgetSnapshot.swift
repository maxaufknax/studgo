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

    var nextEvent: NextEvent?
    var unreadMessages: Int
    var updatedAt: Date
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
