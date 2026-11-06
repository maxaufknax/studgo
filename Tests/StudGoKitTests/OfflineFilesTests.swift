import Foundation
import Testing
@testable import StudGoKit

/// Offline behaltene Dateien: Ablage, Verzeichnis und Aufräumen - rein, auf
/// Linux geprüft. Was davon nicht funktioniert, fiele erst im Flugmodus auf,
/// wenn es nichts mehr zu holen gibt; deshalb der Prüfstand hier.
@Suite("Offline behalten")
struct OfflineFilesTests {

    /// Ein eigener Ablageort je Test: Der Standardordner gehört der App, und
    /// ein Test, der dort herumlöscht, würde den Folgenden den Boden wegziehen.
    private func makeStore() throws -> (OfflineFiles, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("studgo-offline-\(UUID().uuidString)", isDirectory: true)
        return (OfflineFiles(root: root), root)
    }

    private func file(id: String, name: String, size: Int?,
                      changedHoursAgo: Double = 1,
                      changed: Date? = nil) throws -> FileRef {
        // `changed` geht vor `changedHoursAgo`: Wer denselben Stand wie im
        // Manifest prüft, braucht *diesen* Zeitpunkt und keinen frisch
        // gerechneten - zwei separate `Date()` laufen um eine Sekunden-
        // grenze auseinander und ließen den Test gelegentlich scheitern.
        let date = changed ?? Date().addingTimeInterval(-changedHoursAgo * 3600)
        let json = """
        {"data": {"type": "file-refs", "id": "\(id)", "attributes": {
            "name": "\(name)", "filesize": \(size.map(String.init) ?? "null"),
            "chdate": "\(Self.stamp(date))"}}}
        """
        let document = try JSONAPIDocument(data: Data(json.utf8))
        return try #require(FileRef(document.first!))
    }

    private static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func deposit(_ store: OfflineFiles, id: String, name: String) throws -> URL {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("studgo-keep-\(UUID().uuidString).tmp")
        try Data("Inhalt von \(id)".utf8).write(to: source)
        return source
    }

    private func keep(_ store: OfflineFiles, id: String, name: String,
                      courseID: String, chdate: Date?, size: Int) throws {
        let source = try deposit(store, id: id, name: name)
        try store.install(from: source, entry: .init(id: id, name: name,
                                                     courseID: courseID,
                                                     courseTitle: courseID,
                                                     chdate: chdate, size: size,
                                                     keptAt: Date()))
    }

    @Test("Behalten, finden, wieder lesen")
    func rundreise() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try keep(store, id: "d1", name: "Skript.pdf", courseID: "kurs1",
                 chdate: Date(), size: 2_000)

        let entries = store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "Skript.pdf")
        #expect(store.keptIDs() == ["d1"])
        #expect(store.totalSize == 2_000)

        let stored = store.location(for: "d1", name: "Skript.pdf")
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(String(data: try Data(contentsOf: stored), encoding: .utf8)
                == "Inhalt von d1")

        // Ein zweiter Speicher am selben Ort sieht dasselbe - das Manifest
        // ist die Datei, nicht der Speicher.
        #expect(OfflineFiles(root: root).keptIDs() == ["d1"])
    }

    @Test("Gleichnamige Dateien verschiedener Kurse kollidieren nicht")
    func collision() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try keep(store, id: "d1", name: "loesung.pdf", courseID: "kurs1",
                 chdate: Date(), size: 10)
        try keep(store, id: "d2", name: "loesung.pdf", courseID: "kurs2",
                 chdate: Date(), size: 20)

        #expect(store.keptIDs() == ["d1", "d2"])
        #expect(store.totalSize == 30)
        let one = store.location(for: "d1", name: "loesung.pdf")
        let two = store.location(for: "d2", name: "loesung.pdf")
        #expect(one != two)
        #expect(String(data: try Data(contentsOf: one), encoding: .utf8) == "Inhalt von d1")
        #expect(String(data: try Data(contentsOf: two), encoding: .utf8) == "Inhalt von d2")
    }

    @Test("Löschen einzelner Dateien und aller")
    func loeschen() throws {
        let (store, root) = try makeStore()

        try keep(store, id: "d1", name: "a.pdf", courseID: "kurs1",
                 chdate: Date(), size: 10)
        try keep(store, id: "d2", name: "b.pdf", courseID: "kurs1",
                 chdate: Date(), size: 20)

        store.remove(id: "d1")
        #expect(store.keptIDs() == ["d2"])
        #expect(!FileManager.default.fileExists(
            atPath: store.location(for: "d1", name: "a.pdf").path))

        store.removeAll()
        #expect(store.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Veraltete Kopien lassen sich am chdate erkennen")
    func veraltet() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let original = Date().addingTimeInterval(-24 * 3600)
        try keep(store, id: "d1", name: "a.pdf", courseID: "kurs1",
                 chdate: original, size: 10)
        try keep(store, id: "d2", name: "b.pdf", courseID: "kurs1",
                 chdate: original, size: 20)

        // Neue Liste: a.pdf wurde geändert, b.pdf nicht. b.pdf nennt
        // denselben Zeitpunkt wie der Eintrag im Manifest - ein frisch
        // gerechneter läge Sekunden daneben und gilt schon als veraltet.
        let freshList = [try file(id: "d1", name: "a.pdf", size: 10,
                                  changedHoursAgo: 0.5),
                         try file(id: "d2", name: "b.pdf", size: 20,
                                  changed: original)]

        let outdated = store.outdated(in: freshList)
        #expect(outdated.map(\.id) == ["d1"])
    }

    @Test("Die Größenangabe vorab zählt die Dateien zusammen")
    func groesseVorab() throws {
        let files = [try file(id: "d1", name: "a.pdf", size: 1_500),
                     try file(id: "d2", name: "b.pdf", size: nil)]
        // Unbekannte Größe zählt als nichts - die Zahl ist eine Untergrenze.
        #expect(OfflineFiles.expectedSize(of: files) == 1_500)
    }

    @Test("Die Übersicht gruppiert nach Veranstaltung")
    func uebersicht() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try keep(store, id: "d1", name: "a.pdf", courseID: "kurs1",
                 chdate: Date(), size: 10)
        try keep(store, id: "d2", name: "b.pdf", courseID: "kurs1",
                 chdate: Date(), size: 25)
        try keep(store, id: "d3", name: "c.pdf", courseID: "kurs2",
                 chdate: Date(), size: 5)

        let groups = store.groupedByCourse()
        #expect(groups.count == 2)
        #expect(groups.reduce(0) { $0 + $1.count } == 3)
        #expect(groups.contains { $0.courseID == "kurs1" && $0.count == 2 && $0.size == 35 })
    }
}
