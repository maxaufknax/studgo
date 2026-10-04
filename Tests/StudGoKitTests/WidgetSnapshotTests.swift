import Foundation
import Testing
@testable import StudGoKit

/// Was die Widgets wann zeigen.
///
/// Der Anlass ist ein Befund aus 1.8.0/1.8.1: Der Schnappschuss kannte genau
/// einen Termin. War der vorbei, stand er weiter als „Nächster Termin“ auf dem
/// Sperrbildschirm, bis die App wieder geöffnet wurde. Seit 1.8.2 trägt der
/// Schnappschuss die kommenden Termine, und die Timeline rechnet aus, wann
/// welcher dran ist.
@Suite("Widget-Schnappschuss")
struct WidgetSnapshotTests {

    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static func event(_ title: String, from start: Int, to end: Int,
                      room: String? = nil) -> WidgetSnapshot.NextEvent {
        WidgetSnapshot.NextEvent(title: title,
                                 start: base.addingTimeInterval(TimeInterval(start * 60)),
                                 end: base.addingTimeInterval(TimeInterval(end * 60)),
                                 location: room)
    }

    static func at(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

    static let day = WidgetSnapshot(
        upcoming: [event("Analysis", from: 0, to: 90),
                   event("Datenbanken", from: 120, to: 210),
                   event("Programmieren", from: 240, to: 330)],
        unreadMessages: 2,
        updatedAt: base)

    @Test("Läuft ein Termin, zeigt das Widget ihn - sonst den nächsten")
    func aktuellerTermin() {
        #expect(Self.day.current(at: Self.at(-30))?.title == "Analysis")
        #expect(Self.day.current(at: Self.at(45))?.title == "Analysis")
        #expect(Self.day.current(at: Self.at(100))?.title == "Datenbanken")
    }

    @Test("Zum Ende eines Termins steht schon der nächste da")
    func endeSchaltetWeiter() {
        let shown = Self.day.current(at: Self.at(90))
        #expect(shown?.title == "Datenbanken")
        #expect(shown.map { Self.day.isRunning($0, at: Self.at(90)) } == false)
    }

    @Test("Nach dem letzten Termin zeigt das Widget nichts Vergangenes")
    func nichtsVergangenes() {
        #expect(Self.day.current(at: Self.at(400)) == nil)
    }

    @Test("„Danach“ lässt den gezeigten Termin aus")
    func danach() {
        #expect(Self.day.following(at: Self.at(45), limit: 3).map(\.title)
                == ["Datenbanken", "Programmieren"])
        #expect(Self.day.following(at: Self.at(-30), limit: 3).map(\.title)
                == ["Datenbanken", "Programmieren"])
        #expect(Self.day.following(at: Self.at(-30), limit: 1).map(\.title) == ["Datenbanken"])
    }

    @Test("Die Timeline bekommt jeden Beginn und jedes Ende genau einmal")
    func wechselzeitpunkte() {
        let dates = Self.day.changeDates(after: Self.at(45))
        #expect(dates == [Self.at(90), Self.at(120), Self.at(210), Self.at(240), Self.at(330)])

        let doubled = WidgetSnapshot(upcoming: [Self.event("A", from: 0, to: 60),
                                                Self.event("B", from: 60, to: 120)],
                                     unreadMessages: 0, updatedAt: Self.base)
        #expect(doubled.changeDates(after: Self.at(-1)) == [Self.at(0), Self.at(60), Self.at(120)])
    }

    @Test("In den Schnappschuss kommen nur Termine der nächsten sieben Tage, die noch nicht vorbei sind")
    func auswahl() {
        let candidates = [Self.event("vorbei", from: -120, to: -30),
                          Self.event("läuft", from: -30, to: 60),
                          Self.event("übermorgen", from: 2 * 24 * 60, to: 2 * 24 * 60 + 90),
                          Self.event("in acht Tagen", from: 8 * 24 * 60, to: 8 * 24 * 60 + 90)]
        let chosen = WidgetSnapshot.upcoming(candidates, now: Self.base)
        #expect(chosen.map(\.title) == ["läuft", "übermorgen"])

        let many = (0..<30).map { Self.event("T\($0)", from: $0 * 60, to: $0 * 60 + 45) }
        #expect(WidgetSnapshot.upcoming(many, now: Self.base).count == 16)
    }

    @Test("Ein Schnappschuss aus 1.8.1 bleibt nach dem Update lesbar")
    func alterSchnappschuss() throws {
        let json = """
        {"nextEvent":{"title":"Analysis","start":"2026-09-21T10:15:00Z","end":"2026-09-21T11:45:00Z",
         "location":"1101 - E001"},"unreadMessages":4,"updatedAt":"2026-09-21T08:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.upcoming == nil)
        #expect(snapshot.events.map(\.title) == ["Analysis"])
        #expect(snapshot.unreadMessages == 4)
    }

    @Test("Neue Schnappschüsse überstehen das Speichern")
    func rundreise() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(Self.day)
        let back = try decoder.decode(WidgetSnapshot.self, from: data)
        #expect(back.events.map(\.title) == Self.day.events.map(\.title))
    }
}
