import SwiftUI

/// „Dein Semester" — die eigenen Zahlen, nicht der Vergleich mit anderen.
///
/// Stud.IP führt **keine Rangliste**: Der Aktivitätenstrom
/// (`/v1/users/{id}/activitystream`) ist rein persönlich, er zeigt nur die
/// eigene Sicht. Punktestände über Studierende hinweg gäbe es serverseitig
/// nicht — sie müssten erfunden werden. Stattdessen steht hier, was sich aus
/// echten Daten ehrlich ablesen lässt: Stundenplan, Semesterkalender und der
/// eigene Verlauf. Alles wird auf dem Gerät gerechnet, nichts verlässt es.
struct StatisticsView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var plan = Loadable<[ScheduleEntry]>()
    @State private var courses = Loadable<[Course]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var activities = Loadable<[ActivityItem]>()

    private var stats: SemesterStats {
        SemesterStats(plan: plan.value ?? [],
                      courses: courses.value ?? [],
                      semesters: semesters.value ?? [],
                      activities: activities.value ?? [])
    }

    private var isLoading: Bool {
        plan.value == nil && plan.isLoading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    if let progress = stats.semesterProgress {
                        SemesterProgressCard(progress: progress)
                    }
                    numbers
                    WeekLoadCard(stats: stats)
                    if !stats.activityWeeks.isEmpty {
                        ActivityCard(stats: stats)
                    }
                    if !stats.topCourses.isEmpty {
                        topCourses
                    }
                    footnote
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dein Semester")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if plan.value == nil { await reload(fresh: false) } }
    }

    // MARK: - Zahlen

    private var numbers: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(stats.courseCount)",
                     label: stats.courseCount == 1 ? "Kurs" : "Kurse",
                     symbol: "books.vertical.fill")
            StatTile(value: stats.weeklyHoursLabel,
                     label: "Std./Woche",
                     symbol: "clock.fill")
            StatTile(value: "\(stats.sessionsPerWeek)",
                     label: "Sitzungen",
                     symbol: "calendar")
        }
    }

    // MARK: - Aktivste Veranstaltungen

    private var topCourses: some View {
        SectionCard(title: "Wo am meisten los ist", symbol: "flame") {
            VStack(spacing: 10) {
                ForEach(stats.topCourses) { entry in
                    HStack(spacing: 10) {
                        AccentBar(seed: entry.id)
                        Text(entry.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(entry.count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Tint.color(entry.id))
                    }
                }
            }
        }
    }

    private var footnote: some View {
        Text("Diese Zahlen entstehen auf dem Gerät aus deinem Stundenplan, dem Semesterkalender und deinem eigenen Verlauf in Stud.IP. Sie werden nirgends hochgeladen, und niemand sonst sieht sie.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    // MARK: - Laden

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        async let a: Void = plan.load { try await client.schedule(for: user.id) }
        async let b: Void = semesters.load { try await client.semesters() }
        async let c: Void = activities.load { try await client.activityStream(for: user.id, limit: 200) }
        _ = await (a, b, c)

        // Die Kurse erst danach: das laufende Semester steht jetzt fest, und
        // ohne Filter lieferte Stud.IP alle je belegten Veranstaltungen.
        let current = (semesters.value ?? []).first { $0.isCurrent }
        await courses.load { try await client.courses(for: user.id, semester: current?.id) }
    }
}

// MARK: - Rechenwerk

/// Wertet Stundenplan, Semester und Verlauf aus. Ausgelagert, damit die
/// Ansicht nur noch anzeigt — und damit die Regeln an einer Stelle stehen.
struct SemesterStats {
    let plan: [ScheduleEntry]
    let courses: [Course]
    let semesters: [Semester]
    let activities: [ActivityItem]

    private var currentSemester: Semester? {
        semesters.first { $0.isCurrent }
    }

    /// Nur Veranstaltungstermine — selbst angelegte Einträge im Stundenplan
    /// sind keine Lehrveranstaltung und würden die Wochenstunden verfälschen.
    private var cycles: [ScheduleEntry] {
        plan.filter(\.isCourse)
    }

    // MARK: Semesterfortschritt

    struct Progress {
        let title: String
        let fraction: Double
        let dayOfLectures: Int
        let totalLectureDays: Int
        let daysRemaining: Int
        let hasStarted: Bool
    }

    var semesterProgress: Progress? {
        guard let semester = currentSemester,
              let from = semester.lectureStart,
              let to = semester.lectureEnd,
              from < to else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let total = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        let elapsed = calendar.dateComponents([.day], from: from, to: today).day ?? 0
        let clamped = min(max(elapsed, 0), total)

        return Progress(title: semester.title,
                        fraction: total > 0 ? Double(clamped) / Double(total) : 0,
                        dayOfLectures: clamped,
                        totalLectureDays: total,
                        daysRemaining: max(0, total - clamped),
                        hasStarted: today >= calendar.startOfDay(for: from))
    }

    // MARK: Zahlen

    var courseCount: Int { courses.count }

    var sessionsPerWeek: Int { cycles.count }

    /// Wochenstunden als echte Zeit, nicht als Semesterwochenstunden:
    /// eine 90-Minuten-Sitzung zählt hier als 1,5 Stunden.
    var weeklyMinutes: Int {
        cycles.reduce(0) { $0 + max(0, $1.endMinutes - $1.startMinutes) }
    }

    var weeklyHoursLabel: String {
        let hours = Double(weeklyMinutes) / 60
        return hours < 10
            ? String(format: "%.1f", hours).replacingOccurrences(of: ".", with: ",")
            : String(Int(hours.rounded()))
    }

    // MARK: Wochenauslastung

    struct DayLoad: Identifiable {
        let weekday: Int
        let minutes: Int
        var id: Int { weekday }
        var label: String { Weekday.short(weekday) }
    }

    /// Montag bis Freitag stehen immer, damit ein freier Freitag als freier
    /// Tag sichtbar wird statt einfach zu fehlen.
    var weekLoad: [DayLoad] {
        let used = Set(cycles.map(\.normalizedWeekday))
        let days = Set(1...5).union(used).sorted()
        return days.map { day in
            let minutes = cycles
                .filter { $0.normalizedWeekday == day }
                .reduce(0) { $0 + max(0, $1.endMinutes - $1.startMinutes) }
            return DayLoad(weekday: day, minutes: minutes)
        }
    }

    var busiestDay: DayLoad? {
        weekLoad.max { $0.minutes < $1.minutes }
    }

    var freeDays: [String] {
        weekLoad.filter { $0.minutes == 0 }.map(\.label)
    }

    // MARK: Verlauf

    struct WeekBucket: Identifiable {
        let start: Date
        let count: Int
        var id: Date { start }
    }

    /// Die letzten acht Wochen, älteste zuerst.
    var activityWeeks: [WeekBucket] {
        guard !activities.isEmpty else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }

        return (0..<8).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let count = activities.filter {
                guard let date = $0.createdAt else { return false }
                return date >= start && date < end
            }.count
            return WeekBucket(start: start, count: count)
        }
    }

    /// Aufeinanderfolgende Tage mit mindestens einer Aktivität, von heute
    /// rückwärts. Ein stiller heutiger Tag beendet die Reihe noch nicht —
    /// sonst stünde jeden Morgen eine Null da.
    var streak: Int {
        let calendar = Calendar.current
        let days = Set(activities.compactMap { $0.createdAt }
            .map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    struct CourseActivity: Identifiable {
        let id: String
        let name: String
        let count: Int
    }

    /// Die Veranstaltungen mit den meisten Ereignissen im Verlauf.
    var topCourses: [CourseActivity] {
        var tally: [String: (name: String, count: Int)] = [:]
        for item in activities {
            guard let id = item.courseID else { continue }
            let name = item.courseName
                ?? courses.first { $0.id == id }?.shortTitle
                ?? "Veranstaltung"
            tally[id, default: (name: name, count: 0)].count += 1
        }
        return tally
            .map { CourseActivity(id: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Bausteine

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct SemesterProgressCard: View {
    let progress: SemesterStats.Progress

    private var headline: String {
        guard progress.hasStarted else { return "Die Vorlesungszeit hat noch nicht begonnen" }
        if progress.daysRemaining == 0 { return "Die Vorlesungszeit ist vorbei" }
        return "Noch \(progress.daysRemaining) Tage Vorlesungszeit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progress.title)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text("\(Int((progress.fraction * 100).rounded())) %")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.tint)

            Text(headline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: progress.fraction)

            Text("Tag \(progress.dayOfLectures) von \(progress.totalLectureDays)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Wochenauslastung als Balken. Von Hand gezeichnet statt mit Swift Charts:
/// die Balken sollen die Themenfarbe tragen, und mehr als eine Höhe je Tag
/// braucht es hier nicht.
struct WeekLoadCard: View {
    let stats: SemesterStats

    private var maximum: Int {
        max(stats.weekLoad.map(\.minutes).max() ?? 0, 60)
    }

    private var subtitle: String {
        if stats.weeklyMinutes == 0 { return "Kein Stundenplan hinterlegt" }
        var parts: [String] = []
        if let busiest = stats.busiestDay, busiest.minutes > 0 {
            parts.append("Vollster Tag: \(Weekday.full(busiest.weekday))")
        }
        let free = stats.freeDays
        if !free.isEmpty {
            parts.append(free.count == 1 ? "\(free[0]) ist frei" : "Frei: \(free.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        SectionCard(title: "Deine Woche", symbol: "chart.bar") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(stats.weekLoad) { day in
                        VStack(spacing: 5) {
                            Text(day.minutes > 0 ? "\(day.minutes / 60)" : "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day.minutes > 0 ? Color.accentColor : Color(.tertiarySystemFill))
                                .frame(height: max(4, 70 * CGFloat(day.minutes) / CGFloat(maximum)))
                            Text(day.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Weekday.full(day.weekday)): \(day.minutes / 60) Stunden")
                    }
                }
                .frame(height: 106, alignment: .bottom)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ActivityCard: View {
    let stats: SemesterStats

    private var maximum: Int {
        max(stats.activityWeeks.map(\.count).max() ?? 0, 1)
    }

    private var streakText: String {
        switch stats.streak {
        case 0: return "Zuletzt war es ruhig."
        case 1: return "Heute war etwas los."
        default: return "\(stats.streak) Tage in Folge etwas los."
        }
    }

    var body: some View {
        SectionCard(title: "Letzte acht Wochen", symbol: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(stats.activityWeeks) { week in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(week.count > 0 ? Color.accentColor.opacity(0.85)
                                                     : Color(.tertiarySystemFill))
                                .frame(height: max(3, 56 * CGFloat(week.count) / CGFloat(maximum)))
                            Text(week.start.formatted(.dateTime.day().month(.narrow)))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 76, alignment: .bottom)

                Label(streakText, systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
