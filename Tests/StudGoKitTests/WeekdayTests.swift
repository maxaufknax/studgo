import Foundation
import Testing
@testable import StudGoKit

/// Diese Tests gab es früher nicht, und der Fehler, den sie fangen, ist
/// deshalb einmal echt passiert: `Weekday.of` hing an `Calendar.current` und
/// damit an der Zeitzone des Geräts. Auf einem Server unter UTC ist
/// Mitternacht in Berlin noch der Vortag — aus Montag wurde Sonntag.
@Suite("Wochentage")
struct WeekdayTests {
    /// Fest verdrahtet, damit der Test nicht von der Umgebung abhängt.
    static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        berlin.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Montag ist 1, Sonntag ist 7")
    func studipZaehlung() {
        #expect(Weekday.of(Self.date(2026, 8, 24), in: Self.berlin) == 1)  // Montag
        #expect(Weekday.of(Self.date(2026, 8, 28), in: Self.berlin) == 5)  // Freitag
        #expect(Weekday.of(Self.date(2026, 8, 29), in: Self.berlin) == 6)  // Samstag
        #expect(Weekday.of(Self.date(2026, 8, 30), in: Self.berlin) == 7)  // Sonntag
    }

    @Test("Der Kalender ist wirklich ein Parameter")
    func zeitzoneWirktSichAus() {
        let mitternachtBerlin = Self.date(2026, 8, 24)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // Dieselbe Zeitmarke, zwei Kalender, zwei Wochentage — genau der
        // Unterschied, der ohne den Parameter unsichtbar bliebe.
        #expect(Weekday.of(mitternachtBerlin, in: Self.berlin) == 1)
        #expect(Weekday.of(mitternachtBerlin, in: utc) == 7)
    }

    @Test("Namen und Grenzfälle")
    func namen() {
        #expect(Weekday.full(1) == "Montag")
        #expect(Weekday.short(1) == "Mo")
        #expect(Weekday.full(7) == "Sonntag")
        // 0 ist der Leerplatz am Anfang der Liste, 8 liegt daneben.
        #expect(Weekday.full(8) == "Unbekannt")
        #expect(Weekday.short(-1) == "?")
    }
}
