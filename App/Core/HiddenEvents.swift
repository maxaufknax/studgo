import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Was im Kalender nicht stehen soll — und der Weg zurück.
///
/// **Der Fall, der dazu geführt hat:** Eine Übung wird an mehreren Wochentagen
/// angeboten, besucht wird aber nur einer. Wer sich einträgt, steht so lange in
/// allen Gruppen im Stundenplan, bis die Veranstaltungsverwaltung es auftrennt
/// — und selbst dann bleiben die anderen Turnusfenster manchmal belegt. Im
/// Kalender steht derselbe Stoff dann mehrfach in der Woche. Stud.IP kennt kein
/// Ausblenden, die Belegung bleibt also stehen. Die Ausblendung liegt deshalb
/// bewusst **lokal** auf dem Gerät, wie die Blockliste der Moderation: Ein
/// Serverzustand, den nur StudGo pflegt, wäre eine zweite Wahrheit über
/// Veranstaltungen, die Stud.IP weiterhin als belegt führt.
///
/// **Warum der Schlüssel ein Turnusfenster ist und kein einzelner Eintrag:**
/// Derselbe Termin erreicht die App aus drei Quellen — als Block im
/// Stundenplan (`seminar-cycle-dates`), als daraus abgeleitete Sitzung
/// (`plan-…`) und als echte Sitzung aus dem ICS-Strom. Die Kennungen der drei
/// Quellen haben nichts miteinander gemein. Ein Schlüssel aus Veranstaltung,
/// Wochentag und Startminute trifft alle drei; die Kennung des Eintrags oder
/// des Termins träfe immer nur eine.
@MainActor
final class HiddenEventsStore {
    private enum Key {
        static let hidden = "studgo.calendar.hiddenEvents"
        static let shows = "studgo.calendar.showHiddenEvents"
    }

    private let defaults: UserDefaults

    /// Die ausgeblendeten Schlüssel — dauerhaft gesichert.
    ///
    /// `willSet` meldet die Änderung an SwiftUI, `didSet` schreibt sie weg:
    /// beide Seiten sehen denselben Wert.
    private(set) var hiddenKeys: Set<String> {
        willSet { notify() }
        didSet { defaults.set(hiddenKeys.sorted(), forKey: Key.hidden) }
    }

    /// Zeigen die Ansichten ausgeblendete Termine trotzdem an — markiert und
    /// mit Weg zum Wiedereinblenden? Vorgabe **aus**: Wer etwas ausgeblendet
    /// hat, will es nicht sehen. Wer es zurückhaben will, schaltet um.
    var showsHiddenEvents: Bool {
        willSet { notify() }
        didSet { defaults.set(showsHiddenEvents, forKey: Key.shows) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenKeys = Set(defaults.stringArray(forKey: Key.hidden) ?? [])
        showsHiddenEvents = defaults.object(forKey: Key.shows) as? Bool ?? false
    }

    // MARK: - Schlüssel

    /// Turnusfenster einer Veranstaltung: Kennung, Wochentag (Stud.IP-Zählung
    /// 1 = Montag … 7 = Sonntag) und Startminute. Der eine Schlüssel für
    /// Stundenplanblock, abgeleitete Sitzung und ICS-Termin desselben Slots.
    nonisolated static func courseSlot(_ courseID: String, weekday: Int, startMinutes: Int) -> String {
        "slot:\(courseID):\(weekday):\(startMinutes)"
    }

    /// Ein eigener Stundenplaneintrag (`schedule-entry`) — über seine
    /// Kennung, denn er kennt weder Reihe noch Veranstaltung.
    nonisolated static func ownEntry(_ entryID: String) -> String {
        "entry:\(entryID)"
    }

    /// Ein einzelner Termin ohne Reihe dahinter — ein persönlicher
    /// Kalendereintrag, der nur sich selbst meint.
    nonisolated static func singleEvent(_ eventID: String) -> String {
        "event:\(eventID)"
    }

    /// Der Schlüssel eines Stundenplanblocks. Turnusfenster einer
    /// Veranstaltung über `courseSlot`, eigener Eintrag über `ownEntry`.
    nonisolated static func key(of entry: ScheduleEntry) -> String {
        if let courseID = entry.courseID, entry.isCourse {
            return courseSlot(courseID,
                              weekday: entry.normalizedWeekday,
                              startMinutes: entry.startMinutes)
        }
        return ownEntry(entry.id)
    }

    /// Der Schlüssel eines Termins mit Datum. Termin einer Veranstaltung über
    /// `courseSlot` aus Wochentag und Startminute — derselbe Schlüssel wie
    /// sein Stundenplanblock; aus dem Stundenplan abgeleitete Sitzungen über
    /// die Kennung ihres Eintrags; alles Persönliche als Einzeltermin.
    ///
    /// `calendar` ist Parameter für die Prüfbarkeit: `Calendar.current` hängt
    /// an der Zeitzone des Geräts, und Mitternacht in Berlin ist auf einem
    /// Prüfserver unter UTC noch der Vortag (siehe `Weekday.of`).
    nonisolated static func key(of event: CourseEvent, in calendar: Calendar = .current) -> String {
        if let courseID = event.courseID {
            return courseSlot(courseID,
                              weekday: Weekday.of(event.start, in: calendar),
                              startMinutes: minutes(of: event.start, in: calendar))
        }
        if let entryID = sourceEntryID(of: event.id) {
            return ownEntry(entryID)
        }
        return singleEvent(event.id)
    }

    /// Die Kennung des Eintrags, aus dem eine abgeleitete Sitzung entstanden
    /// ist (`plan-<Eintrag>-<Zeitstempel>`), oder nichts. Der Zeitstempel
    /// am Ende muss aus Ziffern bestehen — sonst ist die Kennung von einem
    /// anderen Ursprung, und ein fremdes Präfix wäre ein Schlüssel, der zu
    /// nichts passt.
    nonisolated static func sourceEntryID(of eventID: String) -> String? {
        guard eventID.hasPrefix("plan-") else { return nil }
        let rest = eventID.dropFirst("plan-".count)
        guard let separator = rest.lastIndex(of: "-") else { return nil }
        let stamp = rest[rest.index(after: separator)...]
        guard !stamp.isEmpty, stamp.allSatisfy(\.isNumber) else { return nil }
        return String(rest[..<separator])
    }

    private nonisolated static func minutes(of date: Date, in calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    // MARK: - Fragen

    func isHidden(_ entry: ScheduleEntry) -> Bool {
        hiddenKeys.contains(Self.key(of: entry))
    }

    func isHidden(_ event: CourseEvent, in calendar: Calendar = .current) -> Bool {
        hiddenKeys.contains(Self.key(of: event, in: calendar))
    }

    // MARK: - Ändern

    /// Blendet einen Termin aus — im Stundenplan, im Kalender und auf
    /// „Heute“.
    func hide(_ event: CourseEvent) {
        hiddenKeys.insert(Self.key(of: event))
    }

    /// Blendet einen Stundenplanblock aus — samt aller Sitzungen, die aus
    /// ihm abgeleitet werden.
    func hide(_ entry: ScheduleEntry) {
        hiddenKeys.insert(Self.key(of: entry))
    }

    func unhide(_ event: CourseEvent) {
        hiddenKeys.remove(Self.key(of: event))
    }

    func unhide(_ entry: ScheduleEntry) {
        hiddenKeys.remove(Self.key(of: entry))
    }

    /// Sagt SwiftUI, dass sich etwas geändert hat. Unter Linux (Testsatz)
    /// ein No-op — dort gibt es weder SwiftUI noch `objectWillChange`.
    private func notify() {
        #if canImport(SwiftUI)
        objectWillChange.send()
        #endif
    }
}

#if canImport(SwiftUI)
extension HiddenEventsStore: ObservableObject {}
#endif
