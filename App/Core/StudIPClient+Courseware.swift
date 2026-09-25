import Foundation

// MARK: - Courseware (lesen)

/// Die Lese-Routen der Courseware.
///
/// Die Courseware ist das Modul, in dem Lehrende interaktive Lerninhalte
/// aufbauen: Kapitel, Abschnitte, Blöcke. An der LUH läuft sie als Teil von
/// Stud.IP 6.0 — die Routen stehen in `/v1/discovery` und verlangen, wie
/// alles in der JSON:API, eine Anmeldung mit Recht auf die Veranstaltung.
///
/// Vollständig integriert ist hier die **Lese**-Seite: die Baumstruktur und
/// die textnahen Blöcke zeigt die App selbst. Das Bearbeiten — Kapitel
/// anlegen, Blöcke verschieben, Inhalte schreiben — ist ein Editor mit
/// eigenem Zustand pro Blocktyp; dafür bleibt der Weg in die Weboberfläche
/// (`WebLinks.courseware`).
extension StudIPClient {

    /// Die Courseware-Instanz einer Veranstaltung — ihr `root` zeigt auf das
    /// Wurzelkapitel.
    ///
    /// Die Route antwortet mit 404/403, wenn die Veranstaltung keine
    /// Courseware hat oder der Courseware-Tab gesperrt ist; beides heißt
    /// hier: keine Courseware, kein Fehlerbild.
    func coursewareRootID(of courseID: String) async throws -> String? {
        do {
            let document = try await get("/v1/courses/\(courseID)/courseware")
            return document.first?.relatedID("root")
        } catch let error as APIError {
            if case .http(404, _) = error { return nil }
            if case .http(403, _) = error { return nil }
            throw error
        }
    }

    /// Ein Kapitel im Einzelnen. Show-Route — **ohne** `page[...]`
    /// (`StructuralElementsShow` erbt die leere Paging-Liste).
    ///
    /// Nicht-optional mit eigenem Fehler statt `nil`: Die Kennung kommt aus
    /// der Instanz, ein leeres Kapitel wäre ein Serverfehler, kein Zustand.
    func coursewareChapter(id: String) async throws -> CoursewareChapter {
        guard let chapter = try await get("/v1/courseware-structural-elements/\(id)")
            .first.flatMap(CoursewareChapter.init) else {
            throw APIError.decoding("Kapitel konnte nicht gelesen werden")
        }
        return chapter
    }

    /// Die Unterkapitel eines Kapitels. Index-Route mit erlaubtem
    /// `page[limit]` (`ChildrenOfStructuralElementsIndex`).
    func coursewareChildren(of chapterID: String) async throws -> [CoursewareChapter] {
        try await listAllowingAbsence {
            try await get("/v1/courseware-structural-elements/\(chapterID)/children", limit: 100)
                .resources.compactMap(CoursewareChapter.init)
                .sorted { $0.position < $1.position }
        }
    }

    /// Die Abschnitte eines Kapitels — die Container der Blöcke.
    func coursewareSections(of chapterID: String) async throws -> [CoursewareSection] {
        try await listAllowingAbsence {
            try await get("/v1/courseware-structural-elements/\(chapterID)/containers", limit: 100)
                .resources.compactMap(CoursewareSection.init)
                .sorted { $0.position < $1.position }
        }
    }

    /// Die Blöcke eines Abschnitts. Die Beziehung `blocks` am Container
    /// nennt nur Kennungen — die Inhalte brauchen die eigene Index-Route
    /// (`BlocksIndex`, `page[limit]` erlaubt).
    func coursewareBlocks(of sectionID: String) async throws -> [CoursewareBlock] {
        try await listAllowingAbsence {
            try await get("/v1/courseware-containers/\(sectionID)/blocks", limit: 200)
                .resources.compactMap(CoursewareBlock.init)
                .sorted { $0.position < $1.position }
        }
    }
}
