import Foundation
import Testing
@testable import StudGoKit

/// Die Auswahl für „Demnächst“ auf dem Startbildschirm.
///
/// Der Anlass ist eine Rückmeldung zur 1.7.0: Der Abschnitt zeigte scheinbar
/// „je einen Termin je Tag“, ohne dass jemand das Kriterium nachvollziehen
/// konnte. Hier steht das Kriterium fest: die tatsächlich nächsten Termine,
/// ohne Tagesdeckel - und die Prüfungen, die das garantieren.
@Suite("Die nächsten Termine auswählen")
struct UpcomingEventsTests {

    static let calendar = Calendar.current

    static func uhr(_ tag: String, _ zeit: String) -> Date {
        let tage = tag.split(separator: "-").compactMap { Int($0) }
        let stunden = zeit.split(separator: ":").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: tage[0], month: tage[1],
                                                  day: tage[2],
                                                  hour: stunden[0],
                                                  minute: stunden.count > 1 ? stunden[1] : 0))!
    }

    /// Eine Sitzung am gegebenen Zeitpunkt - derselbe Weg wie der ICS-Strom.
    static func termin(_ id: String, titel: String, von: Date) -> CourseEvent {
        let event = ICSParser.Event(uid: id, summary: titel,
                                    description: nil, location: nil, categories: nil,
                                    start: von, end: von.addingTimeInterval(5400),
                                    isAllDay: false)
        return CourseEvent(ics: event, courseID: "kurs-\(id)")
    }

    /// Sonntag, 27. September 2026, 12:00 - „jetzt“ für alle Prüfungen hier.
    static let jetzt = uhr("2026-09-27", "12:00")

    @Test("Heutige Termine bleiben draußen - dafür gibt es „Heute noch“")
    func heutigeBleibenDraussen() {
        let spaeterHeute = Self.termin("a", titel: "Abendsitzung",
                                       von: Self.uhr("2026-09-27", "18:00"))
        let gestern = Self.termin("alt", titel: "Gestern",
                                  von: Self.uhr("2026-09-26", "10:00"))
        let morgen = Self.termin("b", titel: "Montagssitzung",
                                 von: Self.uhr("2026-09-28", "10:00"))

        let selected = UpcomingEvents.select([spaeterHeute, gestern, morgen],
                                             now: Self.jetzt, calendar: Self.calendar)

        #expect(selected.map(\.id) == ["b"])
    }

    @Test("Mehrere am selben Tag bleiben alle - kein Deckel je Tag")
    func mehrereJeTag() {
        // Der Befund aus der 1.7.0-Rückmeldung: zwei Termine am selben Tag
        // zeigten nur einen. Die Auswahl nimmt die nächsten Termine als
        // Reihe, ungeachtet des Tages.
        let erster = Self.termin("a", titel: "Analysis I",
                                 von: Self.uhr("2026-09-29", "10:00"))
        let zweiter = Self.termin("b", titel: "Analysis I Übung",
                                  von: Self.uhr("2026-09-29", "12:00"))
        let amDonnerstag = Self.termin("c", titel: "Rechnerarchitektur",
                                        von: Self.uhr("2026-10-01", "09:00"))

        let selected = UpcomingEvents.select([amDonnerstag, erster, zweiter],
                                             now: Self.jetzt, calendar: Self.calendar)

        #expect(selected.map(\.id) == ["a", "b", "c"])
    }

    @Test("Die Grenze zählt Termine, nicht Tage")
    func grenze() {
        var termine: [CourseEvent] = []
        for index in 0..<8 {
            // Zwei je Tag über vier Tage - die Grenze darf nicht am Tag
            // kappen, sondern erst am Termin.
            let tag = Self.calendar.date(byAdding: .day,
                                          value: 1 + index / 2, to: Self.jetzt)!
            let stunde = Self.calendar.date(bySettingHour: 8 + (index % 2) * 2,
                                            minute: 0, second: 0, of: tag)!
            termine.append(Self.termin("t\(index)", titel: "Termin \(index)", von: stunde))
        }

        let selected = UpcomingEvents.select(termine, now: Self.jetzt,
                                             limit: 5, calendar: Self.calendar)

        #expect(selected.count == 5)
    }

    @Test("Abgesagte stehen mit dabei - der Kalender zeigt sie ebenfalls")
    func abgesagteMitDabei() throws {
        let json = """
        {"data": {"type": "course-events", "id": "x", "attributes": {
            "title": "Fällt aus", "start": "2026-09-29T10:00:00+02:00",
            "end": "2026-09-29T11:00:00+02:00", "is-cancelled": true}}}
        """
        let doc = try JSONAPIDocument(data: Data(json.utf8))
        let resource = try #require(doc.first)
        let abgesagt = try #require(CourseEvent(resource))
        let stattfindend = Self.termin("b", titel: "Findet statt",
                                        von: Self.uhr("2026-09-30", "08:00"))

        let selected = UpcomingEvents.select([abgesagt, stattfindend],
                                             now: Self.jetzt, calendar: Self.calendar)

        #expect(selected.map(\.id) == ["x", "b"])
    }

    @Test("Gruppierung: Tage aufsteigend, im Tag nach der Uhrzeit")
    func gruppierung() {
        // Unsortiert hereingegeben, gemischt über zwei Tage.
        let dienstagSpät = Self.termin("a", titel: "Abends",
                                       von: Self.uhr("2026-09-29", "18:00"))
        let dienstagFrüh = Self.termin("b", titel: "Morgens",
                                       von: Self.uhr("2026-09-29", "08:00"))
        let mittwoch = Self.termin("c", titel: "Mittwoch",
                                   von: Self.uhr("2026-09-30", "10:00"))

        let groups = UpcomingEvents.group([dienstagSpät, mittwoch, dienstagFrüh],
                                          calendar: Self.calendar)

        #expect(groups.count == 2)
        #expect(groups[0].events.map(\.id) == ["b", "a"])
        #expect(groups[1].events.map(\.id) == ["c"])
        #expect(Self.calendar.isDate(groups[0].day, inSameDayAs: Self.uhr("2026-09-29", "12:00")))
        #expect(Self.calendar.isDate(groups[1].day, inSameDayAs: Self.uhr("2026-09-30", "12:00")))
    }
}
