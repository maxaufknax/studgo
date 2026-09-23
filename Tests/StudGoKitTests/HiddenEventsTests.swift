import Foundation
import Testing
@testable import StudGoKit

/// Was `HiddenEventsStore` ausblendet — und was er treffen muss.
///
/// Der Anlass ist die Übungsgruppe mit mehreren Terminen in der Woche, von
/// denen nur einer der eigene ist. Derselbe Termin erreicht die App aus drei
/// Quellen mit nichts gemein habenden Kennungen; die Suite prüft, dass ein
/// einziger Schlüssel alle drei trifft.
@Suite("Ausgeblendete Termine")
@MainActor
struct HiddenEventsTests {

    /// **Bewusst der Kalender des Systems** — aus demselben Grund wie in
    /// `EventMergeTests`: Ein Datum ist der Tag dort, wo das Gerät steht.
    static let calendar = Calendar.current

    static func entry(id: String, titel: String, wochentag: Int,
                      von: String, bis: String, kurs: Bool) throws -> ScheduleEntry {
        let type = kurs ? "seminar-cycle-dates" : "schedule-entries"
        let owner = kurs
            ? """
              , "relationships": {"owner": {"data": {"type": "courses", "id": "kurs1"}}}
              """
            : ""
        let json = """
        {"data": {"type": "\(type)", "id": "\(id)", "attributes": {
            "title": "\(titel)", "weekday": \(wochentag),
            "start": "\(von)", "end": "\(bis)"}\(owner)}}
        """
        let doc = try JSONAPIDocument(data: Data(json.utf8))
        let resource = try #require(doc.first)
        return try #require(ScheduleEntry(resource))
    }

    static func am(_ text: String, _ uhrzeit: String) -> Date {
        let date = text.split(separator: "-").compactMap { Int($0) }
        let time = uhrzeit.split(separator: ":").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: date[0], month: date[1],
                                                 day: date[2],
                                                 hour: time[0], minute: time[1]))!
    }

    private func makeStore() -> (HiddenEventsStore, UserDefaults, String) {
        let name = "studgo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (HiddenEventsStore(defaults: defaults), defaults, name)
    }

    @Test("Ein Turnusfenster trifft Stundenplanblock, abgeleitete Sitzung und ICS-Termin",
          arguments: ["2026-10-12", "2026-10-13", "2026-10-14"])
    func turnusTreffenAlleQuellen(tag: String) throws {
        // Montag bis Mittwoch der ersten Vorlesungswoche — der Wochentag des
        // Blocks muss mit dem des Termins übereinstimmen, was auch immer die
        // Zeitzone des Prüfgeräts gerade ist.
        let weekday = Weekday.of(Self.am(tag, "14:15"), in: Self.calendar)
        let block = try Self.entry(id: "z1", titel: "Übung Analysis",
                                   wochentag: weekday, von: "14:15", bis: "15:45",
                                   kurs: true)
        let sitzung = CourseEvent(entry: block, on: Self.am(tag, "00:00"))

        let strom = ICSParser.Event(uid: "Stud.IP-SEM-777@studip",
                                    summary: "Übung Analysis",
                                    description: nil,
                                    location: "E001",
                                    categories: nil,
                                    start: Self.am(tag, "14:15"),
                                    end: Self.am(tag, "15:45"),
                                    isAllDay: false)
        let echt = CourseEvent(ics: strom, courseID: "kurs1")

        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        store.hide(block)
        #expect(store.isHidden(block))
        #expect(store.isHidden(sitzung, in: Self.calendar))
        #expect(store.isHidden(echt, in: Self.calendar))
    }

    @Test("Ein anderer Turnus derselben Veranstaltung bleibt sichtbar")
    func nurDasEigeneFenster() throws {
        let block1 = try Self.entry(id: "z1", titel: "Übung Analysis", wochentag: 1,
                                    von: "08:15", bis: "09:45", kurs: true)
        let block2 = try Self.entry(id: "z2", titel: "Übung Analysis", wochentag: 3,
                                    von: "08:15", bis: "09:45", kurs: true)

        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        store.hide(block1)
        #expect(store.isHidden(block1))
        #expect(!store.isHidden(block2))
    }

    @Test("Ein eigener Termin blendet Block und Sitzung gemeinsam aus")
    func eigenerTermin() throws {
        let block = try Self.entry(id: "e1", titel: "Sport", wochentag: 4,
                                   von: "18:00", bis: "20:00", kurs: false)
        let sitzung = CourseEvent(entry: block, on: Self.am("2026-10-15", "00:00"))

        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        store.hide(block)
        #expect(store.isHidden(block))
        #expect(store.isHidden(sitzung, in: Self.calendar))

        store.unhide(block)
        #expect(!store.isHidden(block))
        #expect(!store.isHidden(sitzung, in: Self.calendar))
    }

    @Test("Ein persönlicher Kalendereintrag blendet nur sich selbst aus")
    func persoegnlicherTermin() {
        let strom = { (id: String, um: String) in
            ICSParser.Event(uid: id, summary: "Zahnarzt", description: nil,
                            location: nil, categories: nil,
                            start: Self.am("2026-10-14", um), end: Self.am("2026-10-14", "10:00"),
                            isAllDay: false)
        }
        let erster = CourseEvent(ics: strom("kal-1", "09:00"), courseID: nil)
        let anderer = CourseEvent(ics: strom("kal-2", "09:00"), courseID: nil)

        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        store.hide(erster)
        #expect(store.isHidden(erster, in: Self.calendar))
        #expect(!store.isHidden(anderer, in: Self.calendar))
    }

    @Test("Ausgeblendete überleben den Neustart, die Schalterstellung auch")
    func dauerhaft() throws {
        let block = try Self.entry(id: "z1", titel: "Übung Analysis", wochentag: 2,
                                   von: "10:00", bis: "11:30", kurs: true)
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!store.showsHiddenEvents)
        store.showsHiddenEvents = true
        store.hide(block)

        let wieder = HiddenEventsStore(defaults: defaults)
        #expect(wieder.showsHiddenEvents)
        #expect(wieder.isHidden(block))
    }

    @Test("Die Kennung der abgeleiteten Sitzung führt auf ihren Eintrag zurück")
    func quelleDerSitzung() {
        #expect(HiddenEventsStore.sourceEntryID(of: "plan-z1-1760000000") == "z1")
        #expect(HiddenEventsStore.sourceEntryID(of: "plan-eigen-1-1760000000") == "eigen-1")
        #expect(HiddenEventsStore.sourceEntryID(of: "kalender-1") == nil)
        #expect(HiddenEventsStore.sourceEntryID(of: "plan-ohne-zeitstempel") == nil)
    }
}
