import Foundation
import Testing

/// Die englische Fassung (seit 1.8.2) - geprüft, bevor sie ein Gerät erreicht.
///
/// Eine Übersetzung mit anderem Platzhalter als ihr Schlüssel („%@“ statt
/// „%lld“, einer zu wenig) übersetzt klaglos und fällt erst zur Laufzeit auf -
/// im besten Fall als Kauderwelsch, im schlimmsten als Absturz beim
/// Formatieren. Diese Suite liest die Tabellen aus dem Quelltext und hält
/// jede Zeile gegen ihren Schlüssel.
@Suite("Übersetzungen")
struct LocalizationTests {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let tables = ["App/Resources/en.lproj/Localizable.strings",
                         "Widgets/en.lproj/Localizable.strings"]

    /// Schlüssel und Wert je Zeile `"…" = "…";`, Kommentare ausgenommen.
    static func entries(_ path: String) throws -> [(key: String, value: String)] {
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        let withoutComments = text.replacingOccurrences(of: "(?s)/\\*.*?\\*/", with: "",
                                                        options: .regularExpression)
        let line = try NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$"#)
        return withoutComments
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { row in
                let range = NSRange(row.startIndex..., in: row)
                guard let match = line.firstMatch(in: row, range: range),
                      let key = Range(match.range(at: 1), in: row),
                      let value = Range(match.range(at: 2), in: row) else { return (row, "\u{0}") }
                return (String(row[key]), String(row[value]))
            }
    }

    /// Die Platzhalter eines Formats, nach Argumentstelle geordnet:
    /// „%1$@ bis %2$lld“ und „%@ bis %lld“ ergeben dasselbe.
    static func placeholders(_ format: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(@|lld|ld|d)"#)
        let cleaned = format.replacingOccurrences(of: "%%", with: "")
        var auto = 0
        return pattern.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            .map { match -> (Int, String) in
                let type = Range(match.range(at: 2), in: cleaned).map { String(cleaned[$0]) } ?? "?"
                if let position = Range(match.range(at: 1), in: cleaned).flatMap({ Int(cleaned[$0]) }) {
                    return (position, type == "@" ? "@" : "lld")
                }
                auto += 1
                return (auto, type == "@" ? "@" : "lld")
            }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0):\($0.1)" }
    }

    @Test("Jede Zeile der Tabellen ist lesbar", arguments: tables)
    func lesbar(_ table: String) throws {
        let rows = try Self.entries(table)
        #expect(!rows.isEmpty)
        let broken = rows.filter { $0.value == "\u{0}" }.map(\.key)
        #expect(broken.isEmpty, "Unlesbare Zeilen: \(broken)")
    }

    @Test("Übersetzungen haben dieselben Platzhalter wie ihr Schlüssel", arguments: tables)
    func platzhalter(_ table: String) throws {
        let mismatches = try Self.entries(table)
            .filter { Self.placeholders($0.key) != Self.placeholders($0.value) }
            .map(\.key)
        #expect(mismatches.isEmpty, "Platzhalter weichen ab: \(mismatches)")
    }

    @Test("Kein Schlüssel steht doppelt", arguments: tables)
    func eindeutig(_ table: String) throws {
        let keys = try Self.entries(table).map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("Deutsch ist eine eigene Sprache der App")
    func deutschVorhanden() {
        // Ohne de.lproj kennt das Bündel nur Englisch - und zeigt es auch
        // deutschen Geräten, weil iOS dann keine bessere Wahl hat.
        for path in ["App/Resources/de.lproj/Localizable.strings",
                     "Widgets/de.lproj/Localizable.strings"] {
            #expect(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent(path).path))
        }
    }
}
