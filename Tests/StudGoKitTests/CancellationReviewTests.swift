import Foundation
import Testing
@testable import StudGoKit

/// Der Ausfallsabgleich - reine Vergleichslogik, auf Linux geprüft.
///
/// Die Eigenschaften, die zählen, stehen beim Typ `CancellationReview`; die
/// Suite hält sie fest, damit niemand sie später wegoptimiert:
///
/// * Eine abgesagte Sitzung, für die eine Erinnerung stand, wird entfernt
///   und - wenn gewünscht - genau einmal gemeldet.
/// * Bestehende, richtige Erinnerungen werden nie angerührt.
/// * Der Abgleich ergänzt nur fehlende Erinnerungen im 7-Tage-Fenster.
@Suite("Ausfallsabgleich")
struct CancellationReviewTests {

    private static let calendar = Calendar.current

    private func event(id: String, hoursFromNow: Double,
                       cancelled: Bool = false) -> CourseEvent {
        let summary = cancelled ? "Übung (fällt aus)" : "Übung"
        let start = Date().addingTimeInterval(hoursFromNow * 3600)
        // Die Kennung der Veranstaltung.
        // (id = event.uid; Vergleich und Erinnerung laufen ueber sie.)
        let ics = ICSParser.Event(uid: id, summary: summary,
                                  description: nil, location: nil, categories: nil,
                                  start: start, end: start.addingTimeInterval(3600),
                                  isAllDay: false)
        return CourseEvent(ics: ics, courseID: nil)
    }

    private func reminder(_ id: String, fireInHours: Double?) -> CancellationReview.PlannedReminder {
        CancellationReview.PlannedReminder(
            eventID: id,
            fireDate: fireInHours.map { Date().addingTimeInterval($0 * 3600) })
    }

    @Test("Eine frisch abgesagte Sitzung verliert ihre Erinnerung und wird gemeldet")
    func frischerAusfall() {
        let planned = [reminder("t1", fireInHours: 2)]
        let fresh = [event(id: "t1", hoursFromNow: 3, cancelled: true)]

        let result = CancellationReview.review(planned: planned, announced: [],
                                               fresh: fresh, leadMinutes: 60,
                                               quietWeekend: false, now: Date())

        #expect(result.retireEventIDs == ["t1"])
        #expect(result.newlyCancelled.map(\.id) == ["t1"])
        // Der Ausfall ist gemeldet; der nächste Lauf sagt ihn nicht erneut.
        #expect(result.announced == ["t1"])
        #expect(result.missing.isEmpty)
    }

    @Test("Gleiche Absage wird nur einmal gemeldet")
    func nurEinmal() {
        let planned = [reminder("t1", fireInHours: 2)]
        let fresh = [event(id: "t1", hoursFromNow: 3, cancelled: true)]

        let result = CancellationReview.review(planned: planned, announced: ["t1"],
                                               fresh: fresh, leadMinutes: 60,
                                               quietWeekend: false, now: Date())
        #expect(result.newlyCancelled.isEmpty)
        #expect(result.retireEventIDs == ["t1"])
    }

    @Test("Eine Absage ohne frühere Erinnerung wirbelt nichts auf")
    func ausfallOhneErinnerung() {
        // Stand keine Erinnerung, war die Absage vermutlich längst bekannt -
        // melden wäre Lärm, entfernen gibt es nichts.
        let fresh = [event(id: "t1", hoursFromNow: 3, cancelled: true)]
        let result = CancellationReview.review(planned: [], announced: [],
                                               fresh: fresh, leadMinutes: 60,
                                               quietWeekend: false, now: Date())
        #expect(result.retireEventIDs.isEmpty)
        #expect(result.newlyCancelled.isEmpty)
    }

    @Test("Eine korrekte Erinnerung bleibt unangetastet")
    func korrekteErinnerungenBleiben() {
        // Weckzeit: 3 Stunden bis Beginn minus 60 Minuten Vorlauf.
        let planned = [reminder("t1", fireInHours: 2)]
        let fresh = [event(id: "t1", hoursFromNow: 3)]

        let result = CancellationReview.review(planned: planned, announced: [],
                                               fresh: fresh, leadMinutes: 60,
                                               quietWeekend: false, now: Date())
        #expect(result.retireEventIDs.isEmpty)
        #expect(result.missing.isEmpty)
        #expect(result.newlyCancelled.isEmpty)
    }

    @Test("Eine verschobene Sitzung wird umgeplant statt verlassen")
    func verschoben() {
        // Erinnerung steht auf 2 Stunden - die Weckzeit der alten Uhr.
        let planned = [reminder("t1", fireInHours: 2)]
        let fresh = [event(id: "t1", hoursFromNow: 26)]

        let result = CancellationReview.review(planned: planned, announced: [],
                                               fresh: fresh, leadMinutes: 60,
                                               quietWeekend: false, now: Date())
        #expect(result.retireEventIDs == ["t1"])
        #expect(result.missing.map(\.id) == ["t1"])
    }

    @Test("Fehlende Erinnerungen im Fenster werden ergänzt")
    func ergaenzen() {
        let fresh = [event(id: "t1", hoursFromNow: 24),
                     event(id: "t2", hoursFromNow: 96)]
        let result = CancellationReview.review(planned: [], announced: [],
                                               fresh: fresh, leadMinutes: 20,
                                               quietWeekend: false, now: Date())
        #expect(result.missing.map(\.id) == ["t1", "t2"])
    }

    @Test("Am Wochenende wird bei gestellter Einstellung nichts nachgeplant")
    func wochenende() throws {
        // Der nächste Samstag ab jetzt - egal, wie spät es ist (geprüfte
        // Kalenderrechnung wie überall im Testsatz).
        let now = Date()
        let saturday = Self.calendar.nextDate(after: now, matching: DateComponents(weekday: 7),
                                              matchingPolicy: .nextTime)!
        let hours = saturday.timeIntervalSince(now) / 3600
        let fresh = [event(id: "samstag", hoursFromNow: hours + 2)]

        let result = CancellationReview.review(planned: [], announced: [],
                                               fresh: fresh, leadMinutes: 20,
                                               quietWeekend: true, now: now)
        #expect(result.missing.isEmpty)

        let allowed = CancellationReview.review(planned: [], announced: [],
                                               fresh: fresh, leadMinutes: 20,
                                               quietWeekend: false, now: now)
        #expect(allowed.missing.map(\.id) == ["samstag"])
    }

    @Test("Gemeldete Ausfälle unbekannter Termine fallen aus der Menge")
    func gesaeuberteMenge() {
        let planned = [reminder("t1", fireInHours: 2)]
        let fresh = [event(id: "t1", hoursFromNow: 3, cancelled: true)]

        let result = CancellationReview.review(planned: planned,
                                               announced: ["t1", "uralt"],
                                               fresh: fresh, leadMinutes: 60,
                                               quietWeekend: false, now: Date())
        // „uralt“ kommt im Kalender nicht vor und ist damit vergessen.
        #expect(result.announced == ["t1"])
    }
}
