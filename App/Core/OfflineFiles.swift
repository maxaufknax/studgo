import Foundation

/// Dauerhaft offline behaltene Dateien - Ablage, Verzeichnis und Aufräumen,
/// reines Foundation und damit auf Linux prüfbar.
///
/// **Der Unterschied zum Download:** Der tmp-Ordner räumt iOS nach Belieben
/// aus - Dateien dort sind eine Vorschau, kein Besitz. Offline behaltene
/// Dateien liegen deshalb im Application-Support-Ordner der App.
///
/// **Vom Backup ausgeschlossen:** Es sind abgeleitete Daten - Stud.IP hat
/// die Originale, und auf einem neuen Gerät holt sie die App erneut. Damit
/// landen sie nicht im iCloud-Backup und zählen nicht gegen dessen Platz.
///
/// **Schutzklasse:** `completeFileProtection` - eine offline behaltene Datei
/// ist ohne entsichertes Gerät niemandem zu lesen. Beim Flugmodus ist das
/// kein Nachteil: Wer das Gerät bedient, hat es ohnehin entsperrt.
///
/// **Beim Sitzungsende weg** (siehe `AuthStore.clearAccountTraces`): Das
/// nächste Konto auf dem Gerät hat in den Dateien des vorigen nichts zu
/// suchen.
struct OfflineFiles {

    /// Eine dauerhaft behaltene Datei.
    struct Entry: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var courseID: String
        var courseTitle: String?
        /// Der Stand von Stud.IP, als die Datei geholt wurde. Weicht eine
        /// neue Liste davon ab, ist die Kopie veraltet und wird ersetzt
        /// (siehe `updated`).
        var chdate: Date?
        var size: Int
        var keptAt: Date
    }

    /// Wo die Dateien liegen. Im Betrieb der Application-Support-Ordner der
    /// App; der Testsatz übergibt seinen eigenen.
    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("StudGo-Offline", isDirectory: true)
    }

    let root: URL

    init(root: URL = OfflineFiles.defaultRoot) {
        self.root = root
    }

    // MARK: - Verzeichnis

    private var manifestURL: URL { root.appendingPathComponent("Manifest.json", isDirectory: false) }

    /// Die gehaltenen Dateien - aus dem Manifest, nicht aus dem Ordner
    /// gelesen: Das Verzeichnis ist die Quelle der Wahrheit, sobald eine
    /// Datei fehlt, fällt der Eintrag unten von selbst auf.
    func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    func keptIDs() -> Set<String> {
        Set(entries().map(\.id))
    }

    func entry(id: String) -> Entry? {
        entries().first { $0.id == id }
    }

    private func save(_ list: [Entry]) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        excludeFromBackup(root)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    // MARK: - Ablegen

    /// Wohin eine Datei gehört: ein Unterordner je Datei-Kennung, wie beim
    /// Download-Kollisionsschutz in `StudIPClient` - derselbe Name in zwei
    /// Kursen ist keine Seltenheit.
    func location(for id: String, name: String) -> URL {
        root.appendingPathComponent(id.sanitizedFileName, isDirectory: true)
            .appendingPathComponent(name.sanitizedFileName)
    }

    /// Nimmt eine bereits geladene Datei auf - der Download läuft über die
    /// bestehende `StudIPClient.download`, deren Token- und 401-Behandlung
    /// hier niemand nachbauen will.
    func install(from temporary: URL, entry: Entry) throws {
        let destination = location(for: entry.id, name: entry.name)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: temporary, to: destination)
        protect(destination)
        excludeFromBackup(destination.deletingLastPathComponent())
        var list = entries().filter { $0.id != entry.id }
        list.append(entry)
        save(list)
    }

    /// Entfernt eine gehaltene Datei - samt Eintrag.
    func remove(id: String) {
        if let entry = entry(id: id) {
            try? FileManager.default.removeItem(
                at: location(for: id, name: entry.name).deletingLastPathComponent())
        }
        save(entries().filter { $0.id != id })
    }

    /// Räumt alles - am Sitzungsende und beim „Alle löschen“ der Einstellungen.
    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Was zu tun ist

    /// Welche der gehaltenen Dateien im Vergleich mit einer frischen Liste
    /// veraltet sind: `chdate` hat sich geändert.
    ///
    /// Verglichen wird auf ganze Sekunden: Stud.IP schreibt Unix-Zeit -
    /// alles darunter ist Rundung auf irgendeinem Weg, kein neuer Stand.
    /// Rein, weil hier nur verglichen wird - ob die Aktualisierung danach
    /// gelingt, ist eine Netzfrage.
    func outdated(in files: [FileRef]) -> [FileRef] {
        let kept = Dictionary(entries().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func wholeSeconds(_ date: Date) -> Int {
            date.timeIntervalSince1970.rounded(.down) > Double(Int.max)
                ? Int.max : Int(date.timeIntervalSince1970.rounded(.down))
        }
        return files.filter { file in
            guard let entry = kept[file.id], let entryDate = entry.chdate,
                  let fresh = file.changedAt else { return false }
            return wholeSeconds(entryDate) != wholeSeconds(fresh)
        }
    }

    /// Ersetzt eine vorhandene Kopie durch den neuen Stand - dasselbe
    /// Ablegen mit dem Eintrag von heute.
    func refresh(from temporary: URL, file: FileRef, course: Course) throws {
        let old = entry(id: file.id)
        try install(from: temporary, entry: Entry(
            id: file.id,
            name: file.name,
            courseID: course.id,
            courseTitle: course.title,
            chdate: file.changedAt,
            size: file.size ?? old?.size ?? 0,
            keptAt: Date()))
    }

    // MARK: - Summen

    /// Bytes aller gehaltenen Dateien - für die Einstellungen; hier steht
    /// die Größe, die beim Behalten angegeben wurde.
    var totalSize: Int {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Bytes der Dateien, die zu behalten anstehen - die Angabe vorab.
    static func expectedSize(of files: [FileRef]) -> Int {
        files.reduce(0) { $0 + ($1.size ?? 0) }
    }

    /// Gehaltene Dateien je Veranstaltung - für die Übersicht.
    func groupedByCourse() -> [(courseID: String, title: String, count: Int, size: Int)] {
        let list = entries()
        return Dictionary(grouping: list, by: \.courseID)
            .map { (courseID: $0.key, title: $0.value.first?.courseTitle ?? $0.key,
                    count: $0.value.count,
                    size: $0.value.reduce(0) { $0 + $1.size }) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: - Attribute

    /// Vom iCloud-Backup ausgeschlossen - abgeleitete Daten, die das
    /// nächste Gerät ohnehin neu holt. Unter Apple-Systemen gesetzt; der
    /// Testsatz unter Linux braucht kein Backup-Merkmal.
    private func excludeFromBackup(_ url: URL) {
        #if canImport(UIKit)
        var mutable = url
        try? mutable.setResourceValue(true, forKey: .isExcludedFromBackupKey)
        #endif
    }

    private func protect(_ url: URL) {
        #if canImport(UIKit)
        // Nur vollständig entsichert lesbar - die stärkste Klasse, die für
        // eine Datei sinnvoll ist, die man selbst erst entsperrt betrachtet.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }
}
