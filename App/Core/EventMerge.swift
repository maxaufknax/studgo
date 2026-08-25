import Foundation

/// Führt die Terminquellen von Stud.IP zusammen.
///
/// `/v1/users/{id}/events` liefert **nur den persönlichen Kalender**: die Route
/// filtert auf `range_id = user`, Veranstaltungstermine hängen dagegen am Kurs.
/// Wer sich allein darauf verlässt, zeigt Studierenden einen leeren Kalender,
/// obwohl ihr Stundenplan voll ist. Die Sitzungen der belegten Veranstaltungen
/// werden deshalb aus den Turnusterminen des Stundenplans abgeleitet.
enum EventMerge {

    /// Ein Stundenplan zusammen mit der Vorlesungszeit, für die er gilt.
    ///
    /// **Warum die Zeit mitgeführt wird:** `/v1/users/{id}/schedule` gibt
    /// immer den Plan *eines* Semesters — welches, entscheidet
    /// `filter[timestamp]`. Würde man den Plan des laufenden Semesters über
    /// Tage des nächsten legen, stünden dort Sitzungen, die es nicht gibt.
    /// Seit der Kalender in der vorlesungsfreien Zeit vorausschaut, liegen
    /// zwei Pläne gleichzeitig vor, und jeder gilt nur in seinem Fenster.
    struct PlanWindow {
        let entries: [ScheduleEntry]
        let period: ClosedRange<Date>?

        init(entries: [ScheduleEntry], period: ClosedRange<Date>?) {
            self.entries = entries
            self.period = period
        }

        /// Bequemer Weg für den Regelfall: der Plan des Semesters, in dessen
        /// Vorlesungszeit `reference` liegt.
        init(entries: [ScheduleEntry], semester: Semester?) {
            self.entries = entries
            self.period = semester.flatMap(SemesterContext.lecturePeriod(of:))
        }
    }

    /// Persönliche Termine und abgeleitete Sitzungen, nach Zeit sortiert.
    static func combine(dated: [CourseEvent],
                        plans: [PlanWindow],
                        from start: Date = Date(),
                        days: Int) -> [CourseEvent] {
        var seen = Set(dated.map(slot))
        var merged = dated

        for plan in plans {
            for session in plannedSessions(from: plan.entries,
                                           startingAt: start,
                                           days: days,
                                           within: plan.period) {
                let key = slot(session)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                merged.append(session)
            }
        }
        return merged.sorted { $0.start < $1.start }
    }

    /// Erkennt denselben Termin aus beiden Quellen an Tag und Startminute —
    /// sonst stünde eine Vorlesung doppelt da, sobald Stud.IP sie doch in den
    /// persönlichen Kalender legt.
    static func slot(_ event: CourseEvent) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: event.start)
        let minutes = calendar.component(.hour, from: event.start) * 60
            + calendar.component(.minute, from: event.start)
        return "\(Int(day.timeIntervalSince1970))/\(minutes)"
    }

    /// Die Sitzungen aus einem Wochenplan, Tag für Tag ausgerollt.
    ///
    /// Ohne bekannte Vorlesungszeit wird bewusst nichts abgeleitet — lieber
    /// eine Quelle weniger als erfundene Termine. Und außerhalb der
    /// Vorlesungszeit ebenfalls nichts: Der Stundenplan führt seine
    /// Turnustermine das ganze Semester über, abgehalten werden sie nur
    /// während der Vorlesungszeit.
    static func plannedSessions(from entries: [ScheduleEntry],
                                startingAt start: Date = Date(),
                                days: Int,
                                within period: ClosedRange<Date>?) -> [CourseEvent] {
        let cycles = entries.filter(\.isCourse)
        guard !cycles.isEmpty, let period, days > 0 else { return [] }

        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)

        return (0..<days).flatMap { offset -> [CourseEvent] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first),
                  period.contains(day) else { return [] }
            let weekday = TimetableView.weekday(of: day)
            return cycles
                .filter { $0.normalizedWeekday == weekday }
                .map { CourseEvent(entry: $0, on: day) }
        }
    }
}
