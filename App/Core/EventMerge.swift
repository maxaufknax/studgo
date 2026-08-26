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
    /// **Zwei Sorten Eintrag, zwei Regeln.** `/v1/users/{id}/schedule` mischt
    /// beides in eine Liste:
    ///
    /// * **Turnustermine von Veranstaltungen** (`seminar-cycle-dates`). Sie
    ///   gelten nur während der **Vorlesungszeit**; ohne bekanntes Fenster
    ///   wird bewusst nichts abgeleitet — lieber eine Quelle weniger als
    ///   erfundene Termine.
    /// * **Selbst angelegte Termine** (`schedule-entries`) — das Tutorium,
    ///   die AG, der Sport am Donnerstag. Die gelten **das ganze Jahr**:
    ///   `ScheduleEntry::findByUser_id()` läuft serverseitig ohne
    ///   Semesterfilter, und in der Weboberfläche stehen sie auch in den
    ///   Semesterferien im Stundenplan.
    ///
    /// Bis 1.3.0 galt für beide dieselbe Regel, und die Folge war der Befund
    /// aus dem Testflug: Zwei eigene Termine standen im **Wochenraster** (das
    /// zeigt die Einträge unmittelbar), in der **Tagesansicht** dagegen nicht
    /// — die leitet aus denselben Einträgen datierte Sitzungen ab und warf
    /// sie mit der vorlesungsfreien Zeit gleich wieder weg.
    static func plannedSessions(from entries: [ScheduleEntry],
                                startingAt start: Date = Date(),
                                days: Int,
                                within period: ClosedRange<Date>?) -> [CourseEvent] {
        guard days > 0 else { return [] }

        let cycles = entries.filter(\.isCourse)
        let personal = entries.filter { !$0.isCourse }
        guard !cycles.isEmpty || !personal.isEmpty else { return [] }

        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)

        return (0..<days).flatMap { offset -> [CourseEvent] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return [] }
            let weekday = Weekday.of(day)
            let inLecturePeriod = period?.contains(day) ?? false

            var matching = personal.filter { $0.normalizedWeekday == weekday }
            if inLecturePeriod {
                matching += cycles.filter { $0.normalizedWeekday == weekday }
            }
            return matching.map { CourseEvent(entry: $0, on: day) }
        }
    }
}
