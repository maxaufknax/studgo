import Foundation
import Testing
@testable import StudGoKit

/// Stud.IP antwortet in JSON:API. Die Tücken stecken nicht im Format, sondern
/// in Stud.IPs Umgang damit: Zahlen kommen mal als Zahl, mal als Zeichenkette,
/// und Attribute fehlen je nach Rechtelage ganz. Beides ist hier festgehalten,
/// weil beides schon einmal zu falschem Verhalten in der App geführt hat.
@Suite("JSON:API")
struct JSONAPITests {
    static func dokument(_ json: String) throws -> JSONAPIDocument {
        try JSONAPIDocument(data: Data(json.utf8))
    }

    @Test("Einzelne Ressource")
    func einzelneRessource() throws {
        let doc = try Self.dokument("""
        {"data": {"type": "users", "id": "u1",
                  "attributes": {"username": "mpaasch", "formatted-name": "Maximilian Paasch"}}}
        """)
        let user = try #require(doc.first)
        #expect(user.type == "users")
        #expect(user.id == "u1")
        #expect(user.string("formatted-name") == "Maximilian Paasch")
        #expect(user.string("gibt-es-nicht") == nil)
    }

    @Test("Liste mit Gesamtzahl aus meta.page.total")
    func liste() throws {
        let doc = try Self.dokument("""
        {"data": [{"type": "courses", "id": "c1", "attributes": {"title": "Analysis I"}},
                  {"type": "courses", "id": "c2", "attributes": {"title": "Lineare Algebra"}}],
         "meta": {"page": {"total": 47}}}
        """)
        #expect(doc.resources.count == 2)
        #expect(doc.total == 47)
        #expect(doc.resources.map { $0.string("title") } == ["Analysis I", "Lineare Algebra"])
    }

    @Test("Beziehungen werden gegen included aufgelöst")
    func beziehungen() throws {
        let doc = try Self.dokument("""
        {"data": [{"type": "course-memberships", "id": "m1",
                   "attributes": {"permission": "autor"},
                   "relationships": {
                       "course": {"data": {"type": "courses", "id": "c1"}},
                       "lecturers": {"data": [{"type": "users", "id": "u1"},
                                              {"type": "users", "id": "u2"}]}}}],
         "included": [{"type": "courses", "id": "c1", "attributes": {"title": "Analysis I"}},
                      {"type": "users", "id": "u1", "attributes": {"formatted-name": "Prof. A"}},
                      {"type": "users", "id": "u2", "attributes": {"formatted-name": "Prof. B"}}]}
        """)
        let membership = try #require(doc.first)

        let course = try #require(doc.related("course", of: membership))
        #expect(course.string("title") == "Analysis I")

        let lecturers = doc.relatedList("lecturers", of: membership)
        #expect(lecturers.map { $0.string("formatted-name") } == ["Prof. A", "Prof. B"])

        // Was nicht in `included` steht, fällt weg statt zu stören.
        #expect(doc.related("gibt-es-nicht", of: membership) == nil)
    }

    @Test("Nicht aufgelöste to-many-Gegenstücke fallen still weg")
    func unvollstaendigeBeziehung() throws {
        let doc = try Self.dokument("""
        {"data": {"type": "courses", "id": "c1",
                  "relationships": {"members": {"data": [{"type": "users", "id": "u1"},
                                                         {"type": "users", "id": "fehlt"}]}}},
         "included": [{"type": "users", "id": "u1", "attributes": {"formatted-name": "A"}}]}
        """)
        let course = try #require(doc.first)
        #expect(doc.relatedList("members", of: course).count == 1)
    }

    @Test("Zahlen kommen mal als Zahl, mal als Zeichenkette")
    func zahlenInBeidenFormen() throws {
        // Genau das macht Stud.IP: `course-type` ist im Schema ein (int),
        // steht in der Antwort aber als Text. Wer nur `as? Int` fragt,
        // bekommt nil und zeigt den Kurstyp nicht an.
        let doc = try Self.dokument("""
        {"data": {"type": "courses", "id": "c1",
                  "attributes": {"course-type": "1", "filesize": 20480, "kaputt": "abc"}}}
        """)
        let course = try #require(doc.first)
        #expect(course.int("course-type") == 1)
        #expect(course.int("filesize") == 20480)
        #expect(course.int("kaputt") == nil)
    }

    @Test("Fehlendes Bool ist nicht dasselbe wie false")
    func fehlendesBool() throws {
        let doc = try Self.dokument("""
        {"data": {"type": "folders", "id": "f1",
                  "attributes": {"is-visible": false, "is-readable": true}}}
        """)
        let folder = try #require(doc.first)
        #expect(folder.optionalBool("is-visible") == false)
        #expect(folder.optionalBool("is-readable") == true)
        // `is-downloadable` fehlt: „unbekannt", nicht „verboten". Als false
        // gelesen sperrte das einmal Dateien, die sehr wohl ladbar waren.
        #expect(folder.optionalBool("is-downloadable") == nil)
        #expect(folder.bool("is-downloadable") == false)
    }

    @Test("Zeitstempel nach ISO 8601")
    func zeitstempel() throws {
        let doc = try Self.dokument("""
        {"data": {"type": "news", "id": "n1", "attributes": {"mkdate": "2026-08-24T14:30:00+02:00"}}}
        """)
        let news = try #require(doc.first)
        let date = try #require(news.date("mkdate"))
        #expect(date.timeIntervalSince1970 == 1787574600)
        #expect(news.date("chdate") == nil)
    }

    @Test("Fehlerdokumente werfen mit den Meldungen des Servers")
    func fehlerdokument() {
        let json = """
        {"errors": [{"status": "403", "title": "Zugriff verweigert",
                     "detail": "Sie sind in dieser Veranstaltung nicht angemeldet."}]}
        """
        #expect(throws: (any Error).self) {
            try JSONAPIDocument(data: Data(json.utf8))
        }
    }

    @Test("Kein JSON-Objekt wirft")
    func keinObjekt() {
        #expect(throws: (any Error).self) {
            try JSONAPIDocument(data: Data("[1,2,3]".utf8))
        }
    }

    @Test("Leeres data ergibt keine Ressourcen")
    func leeresData() throws {
        let doc = try Self.dokument(#"{"data": []}"#)
        #expect(doc.resources.isEmpty)
        #expect(doc.first == nil)
        #expect(doc.total == nil)
    }
}
