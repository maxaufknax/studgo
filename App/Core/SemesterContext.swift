import Foundation

/// Beantwortet die Fragen, die der Kalender ans Semester hat.
///
/// **Warum eigens:** Ein Stud.IP-Semester und seine *Vorlesungszeit* sind zwei
/// verschiedene Zeiträume. Das Sommersemester läuft bis Ende September,
/// Vorlesungen gibt es darin nur bis Mitte Juli — `is-current` bleibt also
/// den ganzen August über wahr, während im Stundenplan nichts stattfindet.
/// Wer nur auf `is-current` schaut, zeigt in der vorlesungsfreien Zeit einen
/// leeren Kalender ohne jede Erklärung. Genau so sah StudGo im August aus.
struct SemesterContext {
    let semesters: [Semester]

    init(_ semesters: [Semester]) {
        self.semesters = semesters.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    // MARK: - Semester

    /// Das laufende Semester. Bevorzugt `is-current` vom Server; fehlt das,
    /// wird über die Zeiträume gesucht.
    func current(on date: Date = Date()) -> Semester? {
        if let flagged = semesters.first(where: \.isCurrent) { return flagged }
        return semesters.first { semester in
            guard let start = semester.start, let end = semester.end else { return false }
            return (start...end).contains(date)
        }
    }

    /// Das nächste Semester nach dem laufenden.
    func next(after date: Date = Date()) -> Semester? {
        let boundary = current(on: date)?.end ?? date
        return semesters.first { ($0.start ?? .distantPast) > boundary }
    }

    /// In welcher Vorlesungszeit liegt dieser Tag? `nil` heißt:
    /// vorlesungsfreie Zeit.
    func lecturePeriod(covering date: Date) -> ClosedRange<Date>? {
        for semester in semesters {
            guard let period = Self.lecturePeriod(of: semester) else { continue }
            if period.contains(date) { return period }
        }
        return nil
    }

    static func lecturePeriod(of semester: Semester) -> ClosedRange<Date>? {
        guard let from = semester.lectureStart, let to = semester.lectureEnd, from <= to else {
            return nil
        }
        return from...to
    }

    // MARK: - Lage

    /// Wo im Studienjahr man gerade steht.
    enum Phase: Equatable {
        /// Vorlesungszeit — der Stundenplan gilt.
        case lectures(title: String, endsOn: Date?)
        /// Vorlesungsfreie Zeit; die nächste Vorlesungszeit steht fest.
        case semesterBreak(nextTitle: String?, nextStart: Date?)
        /// Keine brauchbaren Semesterdaten (etwa offline beim ersten Start).
        case unknown
    }

    func phase(on date: Date = Date()) -> Phase {
        if let semester = semesters.first(where: {
            Self.lecturePeriod(of: $0).map { $0.contains(date) } ?? false
        }) {
            return .lectures(title: semester.title, endsOn: semester.lectureEnd)
        }
        guard !semesters.isEmpty else { return .unknown }
        let upcoming = semesters
            .filter { ($0.lectureStart ?? .distantPast) > date }
            .min { ($0.lectureStart ?? .distantFuture) < ($1.lectureStart ?? .distantFuture) }
        return .semesterBreak(nextTitle: upcoming?.title, nextStart: upcoming?.lectureStart)
    }

    var isSemesterBreak: Bool {
        if case .semesterBreak = phase() { return true }
        return false
    }

    /// Das Semester, dessen Vorlesungszeit als Nächstes beginnt — die Quelle
    /// für den vorausschauenden Stundenplan.
    func upcoming(after date: Date = Date()) -> Semester? {
        semesters
            .filter { ($0.lectureStart ?? .distantPast) > date }
            .min { ($0.lectureStart ?? .distantFuture) < ($1.lectureStart ?? .distantFuture) }
    }

    /// Wie viele Tage noch bis zum nächsten Vorlesungsbeginn.
    func daysUntilLectures(from date: Date = Date()) -> Int? {
        guard let start = upcoming(after: date)?.lectureStart else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: start)).day
    }

    /// Ein Satz, der erklärt, warum gerade nichts im Kalender steht.
    ///
    /// Ohne diesen Satz stand dort „Keine anstehenden Termine" — was wie ein
    /// Fehler aussieht, obwohl es die Wahrheit über die Semesterferien ist.
    func emptyExplanation(on date: Date = Date()) -> String {
        switch phase(on: date) {
        case .lectures:
            return "In den nächsten Wochen steht nichts an."
        case .semesterBreak(let title, let start):
            guard let start else {
                return "Vorlesungsfreie Zeit — im Stundenplan steht deshalb nichts."
            }
            let day = start.formatted(.dateTime.day().month(.wide).year())
            let days = daysUntilLectures(from: date)
            let countdown = days.map { $0 == 1 ? " (morgen)" : " (in \($0) Tagen)" } ?? ""
            guard let title else {
                return "Vorlesungsfreie Zeit. Die Vorlesungen beginnen wieder am \(day)\(countdown)."
            }
            return "Vorlesungsfreie Zeit. Das \(title) beginnt am \(day)\(countdown)."
        case .unknown:
            return "Es konnten keine Semesterdaten geladen werden."
        }
    }
}
