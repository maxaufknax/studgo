import Foundation

/// Führt die beiden Terminquellen von Stud.IP zusammen.
///
/// `/v1/users/{id}/events` liefert **nur den persönlichen Kalender**: die Route
/// filtert auf `range_id = user`, Veranstaltungstermine hängen dagegen am Kurs.
/// Wer sich allein darauf verlässt, zeigt Studierenden einen leeren Kalender,
/// obwohl ihr Stundenplan voll ist. Die Sitzungen der belegten Veranstaltungen
/// werden deshalb aus den Turnusterminen des Stundenplans abgeleitet.
enum EventMerge {
    /// Persönliche Termine und abgeleitete Sitzungen, nach Zeit sortiert.
    static func combine(dated: [CourseEvent],
                        plan: [ScheduleEntry],
                        semesters: [Semester],
                        days: Int) -> [CourseEvent] {
        var seen = Set(dated.map(slot))
        var merged = dated

        for session in plannedSessions(from: plan,
                                       days: days,
                                       within: lecturePeriod(in: semesters)) {
            let key = slot(session)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(session)
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

    /// Vorlesungszeit des laufenden Semesters. Ohne diese Grenze stünden in
    /// der vorlesungsfreien Zeit Sitzungen im Kalender, die nicht
    /// stattfinden: Der Stundenplan führt seine Turnustermine das ganze
    /// Semester über, abgehalten werden sie nur während der Vorlesungszeit.
    static func lecturePeriod(in semesters: [Semester]) -> ClosedRange<Date>? {
        guard let current = semesters.first(where: { $0.isCurrent }),
              let from = current.lectureStart,
              let to = current.lectureEnd,
              from <= to else { return nil }
        return from...to
    }

    /// Die Sitzungen der nächsten Tage aus dem Wochenplan. Ohne bekannte
    /// Vorlesungszeit wird bewusst nichts abgeleitet — lieber eine Quelle
    /// weniger als erfundene Termine.
    static func plannedSessions(from entries: [ScheduleEntry],
                                days: Int,
                                within period: ClosedRange<Date>?) -> [CourseEvent] {
        let cycles = entries.filter(\.isCourse)
        guard !cycles.isEmpty, let period else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).flatMap { offset -> [CourseEvent] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  period.contains(day) else { return [] }
            let weekday = TimetableView.weekday(of: day)
            return cycles
                .filter { $0.normalizedWeekday == weekday }
                .map { CourseEvent(entry: $0, on: day) }
        }
    }
}
