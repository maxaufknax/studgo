import Foundation
import Testing
@testable import StudGoKit

/// Der ICS-Strom ist die Quelle für den Kalender. Er kommt aus Stud.IP genau
/// so, wie RFC 5545 es erlaubt — mit umgebrochenen Zeilen, Zeitzonenangaben
/// je Feld und maskierten Sonderzeichen. Jede dieser Eigenheiten hat hier
/// ihren Test, weil ein Fehler darin sich in der App als fehlender oder um
/// Stunden verschobener Termin zeigt und sonst nirgends.
@Suite("ICS-Parser")
struct ICSParserTests {
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    static func kalender(_ eintraege: String) -> String {
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Stud.IP//Stud.IP 6.0.4//DE
        \(eintraege)
        END:VCALENDAR
        """
    }

    @Test("Eine Vorlesung mit Zeitzonenangabe")
    func einfacherTermin() throws {
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:Stud.IP-SEM-c0ffee-1
        DTSTART;TZID=Europe/Berlin:20261012T101500
        DTEND;TZID=Europe/Berlin:20261012T114500
        SUMMARY:Analysis I für Ingenieure
        LOCATION:1101 - E001
        CATEGORIES:Vorlesung
        END:VEVENT
        """)
        let events = ICSParser.events(in: text)
        #expect(events.count == 1)
        let event = try #require(events.first)

        #expect(event.summary == "Analysis I für Ingenieure")
        #expect(event.location == "1101 - E001")
        #expect(event.categories == "Vorlesung")
        #expect(event.isAllDay == false)
        // Termine aus Veranstaltungen tragen dieses Präfix — daran hängt in
        // der App die Unterscheidung zu selbst eingetragenen Terminen.
        #expect(event.isCourseDate)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.berlin
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.start)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 12)
        #expect(parts.hour == 10 && parts.minute == 15)
        #expect(event.end.timeIntervalSince(event.start) == 90 * 60)
    }

    @Test("Umgebrochene Zeilen werden wieder zusammengesetzt")
    func gefalteteZeilen() throws {
        // RFC 5545 bricht nach 75 Zeichen um; die Folgezeile beginnt mit einem
        // Leerzeichen. Wer das übersieht, bekommt abgeschnittene Titel.
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:Stud.IP-SEM-abc-2
        DTSTART;TZID=Europe/Berlin:20261013T140000
        SUMMARY:Grundlagen der Elektrotechnik und ihre Anwendung in der
          modernen Energietechnik
        END:VEVENT
        """)
        let event = try #require(ICSParser.events(in: text).first)
        #expect(event.summary == "Grundlagen der Elektrotechnik und ihre Anwendung in der modernen Energietechnik")
    }

    @Test("Ganztägige Termine")
    func ganztaegig() throws {
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:xyz-3
        DTSTART;VALUE=DATE:20261024
        SUMMARY:Tag der offenen Tür
        END:VEVENT
        """)
        let event = try #require(ICSParser.events(in: text).first)
        #expect(event.isAllDay)
        // Ohne DTEND dauert ein ganztägiger Termin 24 Stunden, kein Stündchen.
        #expect(event.end.timeIntervalSince(event.start) == 24 * 3600)
        #expect(event.isCourseDate == false)
    }

    @Test("Maskierte Sonderzeichen")
    func maskierung() throws {
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:xyz-4
        DTSTART;TZID=Europe/Berlin:20261012T101500
        SUMMARY:Übung\\, Gruppe A
        DESCRIPTION:Erste Zeile\\nZweite Zeile\\; mit Semikolon
        END:VEVENT
        """)
        let event = try #require(ICSParser.events(in: text).first)
        #expect(event.summary == "Übung, Gruppe A")
        #expect(event.description == "Erste Zeile\nZweite Zeile; mit Semikolon")
    }

    @Test("Zeiten in UTC")
    func utcZeit() throws {
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:xyz-5
        DTSTART:20261012T081500Z
        DTEND:20261012T094500Z
        SUMMARY:Webinar
        END:VEVENT
        """)
        let event = try #require(ICSParser.events(in: text).first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.berlin
        // 08:15 UTC sind im Oktober 10:15 in Berlin (Sommerzeit bis 25.10.).
        #expect(calendar.component(.hour, from: event.start) == 10)
    }

    @Test("Ohne Ende dauert ein Termin eine Stunde")
    func fehlendesEnde() throws {
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:xyz-6
        DTSTART;TZID=Europe/Berlin:20261012T101500
        SUMMARY:Sprechstunde
        END:VEVENT
        """)
        let event = try #require(ICSParser.events(in: text).first)
        #expect(event.end.timeIntervalSince(event.start) == 3600)
    }

    @Test("Mehrere Termine, kaputte werden übersprungen")
    func mehrereUndKaputte() {
        let text = Self.kalender("""
        BEGIN:VEVENT
        UID:gut-1
        DTSTART;TZID=Europe/Berlin:20261012T101500
        SUMMARY:Erster
        END:VEVENT
        BEGIN:VEVENT
        UID:ohne-anfang
        SUMMARY:Hat kein DTSTART und fällt daher weg
        END:VEVENT
        BEGIN:VEVENT
        UID:gut-2
        DTSTART;TZID=Europe/Berlin:20261013T101500
        SUMMARY:Zweiter
        END:VEVENT
        """)
        let events = ICSParser.events(in: text)
        #expect(events.count == 2)
        #expect(events.map(\.summary) == ["Erster", "Zweiter"])
    }

    @Test("Leerer Strom ergibt keine Termine")
    func leer() {
        #expect(ICSParser.events(in: "").isEmpty)
        #expect(ICSParser.events(in: Self.kalender("")).isEmpty)
    }
}
