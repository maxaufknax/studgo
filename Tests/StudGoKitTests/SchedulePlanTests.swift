import Foundation
import Testing
@testable import StudGoKit

/// Welcher Wochenplan im Raster landet.
///
/// Der Anlass für diese Suite steht ausführlich in `SchedulePlan`: Fassung
/// 1.4.0 entschied anhand von „ist der Plan des kommenden Semesters leer?",
/// und zwei selbst angelegte Tutorien machten ihn nicht-leer. Die Folge war
/// ein Raster, das erst nur diese zwei Blöcke zeigte und nach ihrem Löschen
/// schlagartig alle Veranstaltungen des laufenden Semesters.
///
/// Jeder Test hier steht für einen Schritt dieser Beobachtung.
@Suite("Wochenplan auswählen")
struct SchedulePlanTests {

    static func entry(id: String, titel: String, kurs: Bool) throws -> ScheduleEntry {
        let type = kurs ? "seminar-cycle-dates" : "schedule-entries"
        let owner = kurs
            ? """
              , "relationships": {"owner": {"data": {"type": "courses", "id": "kurs-\(id)"}}}
              """
            : ""
        let json = """
        {"data": {"type": "\(type)", "id": "\(id)", "attributes": {
            "title": "\(titel)", "weekday": 1, "start": "10:00", "end": "12:00"}\(owner)}}
        """
        let doc = try JSONAPIDocument(data: Data(json.utf8))
        return try #require(ScheduleEntry(doc.first!))
    }

    /// Die beiden Tutorien aus der Rückmeldung.
    static func tutorien() throws -> [ScheduleEntry] {
        [try entry(id: "t1", titel: "Tutorium Philosophie", kurs: false),
         try entry(id: "t2", titel: "Tutorium Philosophie II", kurs: false)]
    }

    static func vorlesungen() throws -> [ScheduleEntry] {
        [try entry(id: "c1", titel: "Analysis I", kurs: true),
         try entry(id: "c2", titel: "Logik", kurs: true)]
    }

    /// **Der eigentliche Fehler.** In den Semesterferien enthielt die Antwort
    /// für das kommende Semester nur die eigenen Termine — dort ist man noch
    /// in keiner Veranstaltung eingetragen. Als „Plan des kommenden
    /// Semesters" gelesen, verdrängte das den laufenden Plan komplett.
    @Test("Eigene Termine allein machen noch keinen Plan des kommenden Semesters")
    func eigeneTermineSindKeinKommenderPlan() throws {
        let plan = SchedulePlan.resolve(current: try Self.vorlesungen() + Self.tutorien(),
                                        upcoming: try Self.tutorien(),
                                        isSemesterBreak: true)

        #expect(plan.scope == .current)
        #expect(plan.entries.filter(\.isCourse).count == 2)
    }

    /// **Der Sprung danach.** Nach dem Löschen der Tutorien war die Antwort
    /// für das kommende Semester leer — und das Raster zeigte auf einmal alle
    /// Veranstaltungen. Das Ergebnis ist richtig; falsch war nur, dass es sich
    /// vorher anders verhielt. Mit der Kursbedingung ist es in beiden Fällen
    /// dasselbe.
    @Test("Ohne eigene Termine bleibt es beim selben Plan")
    func löschenÄndertDieAuswahlNicht() throws {
        let plan = SchedulePlan.resolve(current: try Self.vorlesungen(),
                                        upcoming: [],
                                        isSemesterBreak: true)

        #expect(plan.scope == .current)
        #expect(plan.entries.count == 2)
    }

    /// Sobald man im kommenden Semester wirklich eingetragen ist, lohnt der
    /// Blick nach vorn — dafür war die Vorschau von Anfang an gedacht.
    @Test("Mit Veranstaltungen im kommenden Semester wird vorausgeschaut")
    func vorschauWennDortKurseStehen() throws {
        let kommend = [try Self.entry(id: "c9", titel: "Datenbanken", kurs: true)]
        let plan = SchedulePlan.resolve(current: try Self.vorlesungen(),
                                        upcoming: kommend + (try Self.tutorien()),
                                        isSemesterBreak: true)

        #expect(plan.scope == .upcoming)
        #expect(plan.entries.filter(\.isCourse).map(\.title) == ["Datenbanken"])
    }

    /// In der Vorlesungszeit gilt der laufende Plan, auch wenn für das
    /// kommende Semester schon etwas eingetragen ist.
    @Test("In der Vorlesungszeit gilt der laufende Plan")
    func währendDerVorlesungszeit() throws {
        let plan = SchedulePlan.resolve(current: try Self.vorlesungen(),
                                        upcoming: [try Self.entry(id: "c9", titel: "Datenbanken", kurs: true)],
                                        isSemesterBreak: false)

        #expect(plan.scope == .current)
    }

    /// Eigene Termine gehören in **jeden** Plan — sie laufen ganzjährig.
    @Test("Eigene Termine stehen in beiden Plänen")
    func eigeneTermineImmerDabei() throws {
        for scope in SchedulePlanScope.allCases {
            let plan = SchedulePlan.resolve(current: try Self.vorlesungen() + Self.tutorien(),
                                            upcoming: try Self.tutorien(),
                                            isSemesterBreak: true,
                                            preferred: scope)
            #expect(plan.entries.filter { !$0.isCourse }.count == 2,
                    "Plan \(scope.rawValue) sollte beide eigenen Termine führen")
        }
    }

    /// Dieselben eigenen Termine stehen in **beiden** Antworten. Ohne
    /// Aussieben stünde jedes Tutorium doppelt im Raster.
    @Test("Ein eigener Termin aus beiden Antworten erscheint einmal")
    func keineDoppelten() throws {
        let plan = SchedulePlan.resolve(current: try Self.tutorien(),
                                        upcoming: try Self.tutorien(),
                                        isSemesterBreak: true)

        #expect(plan.entries.count == 2)
        #expect(Set(plan.entries.map(\.id)) == ["t1", "t2"])
    }

    /// Eine Wahl von Hand schlägt die Automatik — und meldet das auch, damit
    /// die Ansicht sie beim Neuladen nicht überschreibt.
    @Test("Eine Wahl von Hand gilt")
    func handauswahl() throws {
        let plan = SchedulePlan.resolve(current: try Self.vorlesungen(),
                                        upcoming: [try Self.entry(id: "c9", titel: "Datenbanken", kurs: true)],
                                        isSemesterBreak: true,
                                        preferred: .current)

        #expect(plan.scope == .current)
        #expect(plan.isAutomatic == false)
        #expect(plan.entries.map(\.title) == ["Analysis I", "Logik"])
    }

    @Test("Ein Plan ohne Veranstaltungen ist keiner")
    func hasCourses() throws {
        #expect(SchedulePlan.hasCourses(try Self.tutorien()) == false)
        #expect(SchedulePlan.hasCourses(try Self.vorlesungen()) == true)
        #expect(SchedulePlan.hasCourses([]) == false)
    }
}
