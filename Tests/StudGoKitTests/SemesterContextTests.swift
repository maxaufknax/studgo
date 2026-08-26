import Foundation
import Testing
@testable import StudGoKit

/// Ob die App „Vorlesungszeit" oder „vorlesungsfreie Zeit" anzeigt, hängt
/// allein an diesen Rechnungen. Die Semester werden hier über den echten Weg
/// gebaut — aus einer JSON:API-Antwort —, damit der Test denselben Pfad geht
/// wie die App.
@Suite("Semester")
struct SemesterContextTests {
    static func semester(id: String, titel: String,
                         vorlesungVon: String, vorlesungBis: String,
                         von: String, bis: String) throws -> Semester {
        let json = """
        {"data": {"type": "semesters", "id": "\(id)", "attributes": {
            "title": "\(titel)",
            "start": "\(von)", "end": "\(bis)",
            "start-of-lectures": "\(vorlesungVon)", "end-of-lectures": "\(vorlesungBis)"}}}
        """
        let doc = try JSONAPIDocument(data: Data(json.utf8))
        let resource = try #require(doc.first)
        return try #require(Semester(resource))
    }

    static func wise2627() throws -> Semester {
        try semester(id: "ws2627", titel: "Wintersemester 2026/27",
                     vorlesungVon: "2026-10-12T00:00:00+02:00", vorlesungBis: "2027-02-06T00:00:00+01:00",
                     von: "2026-10-01T00:00:00+02:00", bis: "2027-03-31T00:00:00+02:00")
    }

    static func sose27() throws -> Semester {
        try semester(id: "ss27", titel: "Sommersemester 2027",
                     vorlesungVon: "2027-04-12T00:00:00+02:00", vorlesungBis: "2027-07-17T00:00:00+02:00",
                     von: "2027-04-01T00:00:00+02:00", bis: "2027-09-30T00:00:00+02:00")
    }

    static func am(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test("Semester werden aus der API-Antwort gelesen")
    func ausDerAntwort() throws {
        let semester = try Self.wise2627()
        #expect(semester.id == "ws2627")
        #expect(semester.title == "Wintersemester 2026/27")
        #expect(semester.lectureStart == Self.am("2026-10-12T00:00:00+02:00"))
        #expect(semester.lectureEnd != nil)
    }

    @Test("Mitten in der Vorlesungszeit")
    func waehrendVorlesung() throws {
        let context = SemesterContext([try Self.wise2627(), try Self.sose27()])
        let phase = context.phase(on: Self.am("2026-11-15T10:00:00+01:00"))
        guard case .lectures(let titel, _) = phase else {
            Issue.record("Erwartet: Vorlesungszeit, bekommen: \(phase)"); return
        }
        #expect(titel == "Wintersemester 2026/27")
    }

    @Test("In der vorlesungsfreien Zeit zeigt die nächste Vorlesungszeit")
    func zwischenDenSemestern() throws {
        let context = SemesterContext([try Self.wise2627(), try Self.sose27()])
        // Ende Februar: Winter vorbei, Sommer noch nicht angefangen.
        let phase = context.phase(on: Self.am("2027-02-20T10:00:00+01:00"))
        guard case .semesterBreak(let naechster, let ab) = phase else {
            Issue.record("Erwartet: vorlesungsfreie Zeit, bekommen: \(phase)"); return
        }
        #expect(naechster == "Sommersemester 2027")
        #expect(ab == Self.am("2027-04-12T00:00:00+02:00"))
    }

    @Test("Ohne Semesterdaten bleibt die Lage unbekannt")
    func ohneDaten() {
        #expect(SemesterContext([]).phase(on: Date()) == .unknown)
    }

    @Test("Die Vorlesungszeit deckt ihre Ränder ab")
    func raender() throws {
        let context = SemesterContext([try Self.wise2627()])
        // Der erste und der letzte Tag gehören dazu — ein „<" statt „<="
        // an dieser Stelle kostet genau zwei Tage im Jahr, und zwar die,
        // an denen es am meisten auffällt.
        let ersterTag = Self.am("2026-10-12T00:00:00+02:00")
        let letzterTag = Self.am("2027-02-06T00:00:00+01:00")
        for tag in [ersterTag, letzterTag] {
            guard case .lectures = context.phase(on: tag) else {
                Issue.record("\(tag) sollte in der Vorlesungszeit liegen"); return
            }
        }
    }
}
