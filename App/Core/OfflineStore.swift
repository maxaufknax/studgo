import Combine
import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Die Oberfläche-Seite der offline behaltenen Dateien: hält den Stand im
/// Arbeitsspeicher, damit jeder Streifen grün wird, sobald eine Datei dazu
/// gekommen ist - und meldet das an SwiftUI.
///
/// Das Ablage-Verzeichnis selbst liegt in `OfflineFiles` (reines Foundation,
/// Prüfstand ist `OfflineFilesTests`); hier geht es nur darum, dieselbe
/// Liste allen Ansichten zur Verfügung zu stellen, die sie zeigen. Der Klient
/// kommt als Parameter: Er gehört zur Anmeldung, und die kennt nur die
/// Ansicht, die ihn gerade benutzt.
@MainActor
final class OfflineStore: ObservableObject {
    static let shared = OfflineStore()

    private let storage = OfflineFiles()

    @Published private(set) var keptIDs: Set<String> = []

    private init() {
        reload()
    }

    private func reload() {
        keptIDs = storage.keptIDs()
    }

    func contains(_ file: FileRef) -> Bool {
        keptIDs.contains(file.id)
    }

    /// Die lokale Adresse einer gehaltenen Datei - existiert sie nicht
    /// (etwa weil ein Backup-Restore sie verschluckt hat), fällt die Ansicht
    /// auf den gewöhnlichen Download zurück.
    func localURL(for file: FileRef) -> URL? {
        guard let entry = storage.entry(id: file.id) else { return nil }
        let url = storage.location(for: file.id, name: entry.name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Behält eine Datei: was schon geladen ist, wird genommen, sonst
    /// geladen - und dann in den Application-Support-Ordner gehoben.
    func keep(_ file: FileRef,
              in course: Course,
              client: StudIPClient,
              alreadyLoaded: URL?) async throws {
        let temporary: URL
        if let alreadyLoaded, FileManager.default.fileExists(atPath: alreadyLoaded.path) {
            temporary = alreadyLoaded
        } else {
            temporary = try await client.download(file)
        }
        try storage.install(from: temporary, entry: .init(
            id: file.id, name: file.name,
            courseID: course.id, courseTitle: course.title,
            chdate: file.changedAt, size: file.size ?? 0,
            keptAt: Date()))
        reload()
    }

    /// Ersetzt eine veraltete Kopie durch den neuen Stand (für das „Wann“,
    /// siehe `OfflineFiles.outdated`).
    func refresh(_ file: FileRef,
                 in course: Course,
                 client: StudIPClient) async throws {
        let temporary = try await client.fresh.download(file)
        try storage.refresh(from: temporary, file: file, course: course)
        reload()
    }

    func remove(_ file: FileRef) {
        storage.remove(id: file.id)
        reload()
    }

    func removeAll() {
        storage.removeAll()
        reload()
    }

    /// Was von einer Liste frischer Dateien veraltet ist - für das
    /// Nachziehen, sobald eine Ordnerliste lädt.
    func outdated(in files: [FileRef]) -> [FileRef] {
        storage.outdated(in: files)
    }

    /// Bytes aller gehaltenen Dateien - für die Einstellungen.
    var totalSize: Int { storage.totalSize }

    func groupedByCourse() -> [(courseID: String, title: String, count: Int, size: Int)] {
        storage.groupedByCourse()
    }
}
