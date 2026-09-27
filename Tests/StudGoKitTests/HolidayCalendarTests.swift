import Foundation
import Testing
@testable import StudGoKit

/// Die Feiertage in Niedersachsen - Grundlage für die Anzeige im Kalender.
///
/// Die beweglichen Tage hängen am Ostersonntag; die feste Zusicherung ist,
/// dass die Rechnung unabhängig vom Kalender des Geräts stimmt. Geprüft
/// wird gegen öffentlich bekannte Osterdaten mehrerer Jahre.
@Suite("Feiertage in Niedersachsen")
struct HolidayCalendarTests {

    static let calendar = Calendar.current

    static func tag(_ jahr: Int, _ monat: Int, _ tag: Int) -> Date {
        calendar.date(from: DateComponents(year: jahr, month: monat, day: tag))!
    }

    // MARK: - Ostersonntag

    @Test("Ostersonntag nach Gaußscher Osterformel", arguments: [
        (2024, 3, 31), (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2028, 4, 16),
    ])
    func ostersonntag(jahr: Int, monat: Int, tag: Int) throws {
        let ostern = try #require(HolidayCalendar.easterSunday(jahr, calendar: Self.calendar))
        #expect(Self.calendar.isDate(ostern, inSameDayAs: Self.tag(jahr, monat, tag)))
    }

    // MARK: - Feste Tage

    @Test("Die festen Feiertage stehen jedes Jahr", arguments: [
        ("Neujahr", 1, 1), ("Tag der Arbeit", 5, 1),
        ("Tag der Deutschen Einheit", 10, 3), ("Reformationstag", 10, 31),
        ("1. Weihnachtstag", 12, 25), ("2. Weihnachtstag", 12, 26),
    ])
    func festeTage(name: String, monat: Int, tag: Int) throws {
        let jahr = 2026
        let tage = HolidayCalendar.holidays(of: jahr, calendar: Self.calendar)
        let gefunden = tage.first { Self.calendar.isDate($0.date, inSameDayAs: Self.tag(jahr, monat, tag)) }
        #expect(try #require(gefunden).name == name)
    }

    // MARK: - Bewegliche Tage 2026

    @Test("Karfreitag liegt zwei Tage vor Ostersonntag")
    func karfreitag() throws {
        let tage = HolidayCalendar.holidays(of: 2026, calendar: Self.calendar)
        let karfreitag = tage.first { $0.name == "Karfreitag" }
        #expect(Self.calendar.isDate(try #require(karfreitag).date,
                                     inSameDayAs: Self.tag(2026, 4, 3)))
    }

    @Test("Ostermontag liegt einen Tag nach Ostersonntag")
    func ostermontag() throws {
        let tage = HolidayCalendar.holidays(of: 2026, calendar: Self.calendar)
        let ostermontag = tage.first { $0.name == "Ostermontag" }
        #expect(Self.calendar.isDate(try #require(ostermontag).date,
                                     inSameDayAs: Self.tag(2026, 4, 6)))
    }

    @Test("Christi Himmelfahrt liegt 39 Tage nach Ostersonntag")
    func himmelfahrt() throws {
        let tage = HolidayCalendar.holidays(of: 2026, calendar: Self.calendar)
        let himmelfahrt = tage.first { $0.name == "Christi Himmelfahrt" }
        #expect(Self.calendar.isDate(try #require(himmelfahrt).date,
                                     inSameDayAs: Self.tag(2026, 5, 14)))
    }

    @Test("Pfingstmontag liegt 50 Tage nach Ostersonntag")
    func pfingstmontag() throws {
        let tage = HolidayCalendar.holidays(of: 2026, calendar: Self.calendar)
        let pfingstmontag = tage.first { $0.name == "Pfingstmontag" }
        #expect(Self.calendar.isDate(try #require(pfingstmontag).date,
                                     inSameDayAs: Self.tag(2026, 5, 25)))
    }

    // MARK: - Abfragen

    @Test("Ein Feiertag am Datum, ein gewöhnlicher Tag nicht")
    func abfrageAmDatum() throws {
        let einheit = try #require(HolidayCalendar.holiday(on: Self.tag(2026, 10, 3),
                                                           calendar: Self.calendar))
        #expect(einheit.name == "Tag der Deutschen Einheit")

        // Heiligabend ist in Niedersachsen kein Feiertag - trotzdem beginnt
        // an vielen Hochschulen an ihm die Weihnachtspause.
        #expect(HolidayCalendar.holiday(on: Self.tag(2026, 12, 24),
                                        calendar: Self.calendar) == nil)
        #expect(HolidayCalendar.holiday(on: Self.tag(2026, 9, 27),
                                        calendar: Self.calendar) == nil)
    }

    @Test("Zeitspannen über den Jahreswechsel liefern beide Jahre")
    func zeitspanne() {
        let spanne = Self.tag(2026, 12, 1)...Self.tag(2027, 1, 15)
        let tage = HolidayCalendar.holidays(in: spanne, calendar: Self.calendar)

        #expect(tage.count == 3)
        #expect(tage.contains { $0.name == "1. Weihnachtstag" })
        #expect(tage.contains { $0.name == "2. Weihnachtstag" })
        #expect(tage.contains { $0.name == "Neujahr" })
    }
}
