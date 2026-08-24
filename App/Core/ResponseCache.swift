import CryptoKit
import Foundation

/// Legt Antworten der JSON:API auf der Platte ab.
///
/// Zwei Gründe: Die App zeigt beim Öffnen sofort den letzten Stand, statt in
/// jeden Tab mit einem Spinner zu starten — und in der Bahn ohne Empfang
/// bleibt sie benutzbar, statt überall Fehler zu zeigen.
///
/// Gespeichert wird der rohe Antwortkörper. Damit muss keine einzige
/// Modellstruktur `Codable` sein, und ein späterer Feldzuwachs im Modell
/// erreicht auch die schon abgelegten Einträge.
enum ResponseCache {
    /// Wie lange eine Antwort ohne Rückfrage beim Server gilt. Kurz genug,
    /// dass ein Tabwechsel aktuelle Daten zeigt; lang genug, dass das
    /// Hin- und Herspringen zwischen Tabs nicht jedes Mal nachlädt.
    static let maxAge: TimeInterval = 300

    private static let directory: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("StudGoAPI", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static func location(for key: String) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    static func store(_ data: Data, for key: String) {
        guard !data.isEmpty, let url = location(for: key) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Liefert einen Eintrag samt Alter — ob er noch frisch genug ist,
    /// entscheidet der Aufrufer.
    static func load(for key: String) -> (data: Data, age: TimeInterval)? {
        guard let url = location(for: key),
              let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return (data, Date().timeIntervalSince(modified))
    }

    /// Beim Abmelden muss der Zwischenspeicher weg — sonst sähe das nächste
    /// Konto auf diesem Gerät die Daten des vorherigen.
    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
