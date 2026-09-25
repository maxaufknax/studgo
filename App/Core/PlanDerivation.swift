import Foundation

/// Stundenplanblöcke aus datierten Kurssitzungen.
///
/// Der Fall, der das braucht (Rückmeldung zur Fassung 1.6.1): Ende September
/// zeigte die **Liste** die WiSe-Sitzungen aus dem ICS-Strom, das
/// **Wochenraster** aber weiter den Plan des SoSe. Der Grund liegt bei
/// Stud.IP: `/v1/users/{id}/schedule` mit `filter[timestamp]` des kommenden
/// Semesters liefert die Turnustermine erst, wenn die Belegung in
/// `semester_courses` eingetragen ist (Befund 11 in docs/API-NOTES.md) — der
/// ICS-Export (`exportCourseDates`) schreibt die einzelnen Sitzungen dagegen
/// schon jetzt in den Strom. Für das Raster blieb damit der alte Semesterplan
/// stehen, obwohl längst bekannt war, wie die kommende Woche aussieht.
///
/// Hier passiert die Umkehrung von `EventMerge.plannedSessions`: Statt einen
/// Wochenplan in datierte Sitzungen auszurollen, werden datierte Sitzungen
/// wieder in ein Wochenraster zurückgelegt — gruppiert nach Veranstaltung,
/// Wochentag und Uhrzeit. Das Ergebnis ist ein Plan wie ihn der Stundenplan-
/// Endpunkt liefert, nur aus der verlässlicheren Quelle; `SchedulePlan.resolve`
/// entscheidet damit wie bisher, welches Raster zu sehen ist.
enum PlanDerivation {

    /// Baut wiederkehrende Blöcke aus echten Kurssitzungen.
    ///
    /// - Parameter within: Nur Sitzungen in diesem Fenster zählen — ohne
    ///   bekanntes Fenster wird bewusst nichts abgeleitet, denn ein Block aus
    ///   SoSe-Sitzungen wäre eine erfundene Aussage über das WiSe.
    ///
    /// Eigene Termine (`isPersonal`) zählen nicht: Die stehen im Stundenplan
    /// des eigenen Kontos ohnehin und gelten dort ganzjährig. Abgesagte
    /// Sitzungen scheiden aus, sonst würde ein einzelner Ausfall einen Block
    /// erzeugen, der nie stattfindet.
    static func cycleEntries(from events: [CourseEvent],
                             within period: ClosedRange<Date>?,
                             calendar: Calendar = .current) -> [ScheduleEntry] {
        let candidates = events.filter { event in
            event.courseID?.nilIfEmpty != nil && !event.isPersonal && !event.isCancelled
        }
        guard !candidates.isEmpty else { return [] }

        struct Key: Hashable {
            let courseID: String
            let weekday: Int
            let startMinutes: Int
            let endMinutes: Int
        }

        var groups: [Key: [CourseEvent]] = [:]
        for event in candidates {
            if let period, !period.contains(event.start) { continue }
            let key = Key(courseID: event.courseID ?? "",
                          weekday: Weekday.of(event.start, in: calendar),
                          startMinutes: minutes(of: event.start, in: calendar),
                          endMinutes: minutes(of: event.end, in: calendar))
            groups[key, default: []].append(event)
        }

        // Nach Wochentag und Startzeit — das Raster liest die Liste genau so.
        let ordered = groups.sorted { a, b in
            if a.key.weekday != b.key.weekday { return a.key.weekday < b.key.weekday }
            return a.key.startMinutes < b.key.startMinutes
        }
        return ordered.map { key, occurrences in
            ScheduleEntry(id: "derived-\(key.courseID)-\(key.weekday)-\(key.startMinutes)",
                          title: mostFrequent(occurrences.map(\.title)) ?? "",
                          weekday: key.weekday,
                          start: Format.clock(minutes: key.startMinutes),
                          end: Format.clock(minutes: key.endMinutes),
                          location: mostFrequent(occurrences.compactMap(\.location)),
                          isCourse: true,
                          courseID: key.courseID)
        }
    }

    /// Der häufigste Wert — leerer String zählt nicht. Bei Gleichstand gewinnt
    /// das erste Vorkommen; die Titel einer Turnusreihe unterscheiden sich
    /// höchstens um Nummer und Art, die Benennung ist also beliebig stabil.
    private static func mostFrequent(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for value in values where !value.isEmpty {
            if counts[value] == nil { order.append(value) }
            counts[value, default: 0] += 1
        }
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    private static func minutes(of date: Date, in calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
