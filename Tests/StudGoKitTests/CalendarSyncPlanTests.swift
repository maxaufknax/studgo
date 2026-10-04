import Foundation
import Testing
@testable import StudGoKit

/// Der Abgleich mit dem iOS-Kalender „StudGo“ (seit 1.8.2).
///
/// Ein Fehler hier landet nicht in der App, sondern im Kalender der Person -
/// doppelte Vorlesungen, verschwundene eigene Einträge, eine Woche voller
/// ausgefallener Sitzungen. Deshalb ist die ganze Entscheidung ohne EventKit
/// gebaut und hier geprüft; `CalendarSync` überträgt sie nur.
@Suite("Kalender-Abgleich")
struct CalendarSyncPlanTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func session(_ id: String, _ title: String, inHours offset: Double,
                        hours: Double = 1.5, room: String? = "1101 - E001",
                        cancelled: Bool = false) -> CourseEvent {
        let start = now.addingTimeInterval(offset * 3600)
        let summary = cancelled ? "\(title) (fällt aus)" : title
        let event = ICSParser.Event(uid: "Stud.IP-SEM-\(id)@studip", summary: summary,
                                    description: nil, location: room, categories: nil,
                                    start: start, end: start.addingTimeInterval(hours * 3600),
                                    isAllDay: false)
        return CourseEvent(ics: event, courseID: nil)
    }

    @Test("Eingetragen wird nur, was noch kommt, nicht ausfällt und im Fenster liegt")
    func auswahl() {
        let events = [Self.session("vorbei", "Analysis", inHours: -5),
                      Self.session("laeuft", "Datenbanken", inHours: -0.5),
                      Self.session("morgen", "Programmieren", inHours: 20),
                      Self.session("abgesagt", "Technikethik", inHours: 30, cancelled: true),
                      Self.session("weit", "Logik", inHours: 24 * 70)]
        let items = CalendarSyncPlan.items(from: events, now: Self.now, horizonDays: 56)
        #expect(items.map(\.title) == ["Datenbanken", "Programmieren"])
        #expect(items.allSatisfy { $0.notes?.contains("StudGo") == true })
    }

    @Test("Derselbe Termin bekommt immer denselben Schlüssel, ein anderer einen anderen")
    func schluessel() {
        let a = Self.session("1", "Analysis", inHours: 2)
        let b = Self.session("2", "Analysis", inHours: 2)
        #expect(CalendarSyncPlan.key(for: a) == CalendarSyncPlan.key(for: Self.session("1", "Umbenannt", inHours: 9)))
        #expect(CalendarSyncPlan.key(for: a) != CalendarSyncPlan.key(for: b))
        let digits = CalendarSyncPlan.key(for: a)
        #expect(digits.allSatisfy { $0.isHexDigit })
    }

    @Test("Nur Einträge von StudGo werden erkannt")
    func adresse() {
        let key = CalendarSyncPlan.key(for: Self.session("1", "Analysis", inHours: 2))
        #expect(CalendarSyncPlan.key(from: CalendarSyncPlan.url(for: key)) == key)
        #expect(CalendarSyncPlan.key(from: URL(string: "https://studgo.de/termin/abc")) == nil)
        #expect(CalendarSyncPlan.key(from: URL(string: "studgo://heute")) == nil)
        #expect(CalendarSyncPlan.key(from: nil) == nil)
    }

    @Test("Doppelte Termine landen nur einmal im Kalender")
    func keineDoppelten() {
        let twice = [Self.session("1", "Analysis", inHours: 2), Self.session("1", "Analysis", inHours: 2)]
        #expect(CalendarSyncPlan.items(from: twice, now: Self.now, horizonDays: 56).count == 1)
    }

    static func item(_ key: String, _ title: String, start: Double = 2) -> CalendarSyncItem {
        CalendarSyncItem(key: key, title: title,
                         start: now.addingTimeInterval(start * 3600),
                         end: now.addingTimeInterval((start + 1.5) * 3600))
    }

    @Test("Neues kommt hinzu, Geändertes wird angepasst, Weggefallenes entfernt")
    func unterschied() {
        let existing = [Self.item("a", "Analysis"), Self.item("b", "Datenbanken"), Self.item("c", "Alt")]
        let desired = [Self.item("a", "Analysis"), Self.item("b", "Datenbanken", start: 3), Self.item("d", "Neu")]
        let changes = CalendarSyncPlan.changes(existing: existing, desired: desired)
        #expect(changes.insert.map(\.key) == ["d"])
        #expect(changes.update.map(\.key) == ["b"])
        #expect(changes.remove == ["c"])
        #expect(changes.duplicates.isEmpty)
    }

    @Test("Ein zweiter Abgleich ohne Änderung tut nichts")
    func stillstand() {
        let desired = [Self.item("a", "Analysis"), Self.item("b", "Datenbanken")]
        #expect(CalendarSyncPlan.changes(existing: desired, desired: desired).isEmpty)
    }

    @Test("Mehrfach eingetragene Schlüssel werden bereinigt")
    func bereinigung() {
        let existing = [Self.item("a", "Analysis"), Self.item("a", "Analysis")]
        let changes = CalendarSyncPlan.changes(existing: existing, desired: [Self.item("a", "Analysis")])
        #expect(changes.duplicates == ["a"])
        #expect(changes.insert.isEmpty && changes.update.isEmpty && changes.remove.isEmpty)
    }
}
