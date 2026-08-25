import SwiftUI

/// Einstiegsbildschirm: was jetzt ansteht, was heute noch kommt, was neu ist.
struct TodayView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth
    @Environment(Preferences.self) private var preferences

    @State private var events = Loadable<[CourseEvent]>()
    @State private var plan = Loadable<[ScheduleEntry]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var messages = Loadable<[Message]>()
    @State private var news = Loadable<[NewsItem]>()
    @State private var courses: [Course] = []
    @State private var isShowingSettings = false

    /// Persönliche Termine plus die aus dem Stundenplan abgeleiteten
    /// Sitzungen — warum das nötig ist, steht in `EventMerge`.
    private var context: SemesterContext { SemesterContext(semesters.value ?? []) }

    private var allEvents: [CourseEvent] {
        EventMerge.combine(dated: events.value ?? [],
                           plans: [EventMerge.PlanWindow(entries: plan.value ?? [],
                                                         semester: context.current())],
                           days: 21)
    }

    private var current: CourseEvent? {
        let now = Date()
        if let running = allEvents.first(where: { $0.start <= now && $0.end >= now && !$0.isCancelled }) {
            return running
        }
        return allEvents.first { $0.start > now && !$0.isCancelled }
    }

    private var todaysRemaining: [CourseEvent] {
        allEvents.filter {
            Calendar.current.isDateInToday($0.start) && $0.end >= Date() && $0.id != current?.id
        }
    }

    private var laterEvents: [CourseEvent] {
        allEvents
            .filter { !Calendar.current.isDateInToday($0.start) && $0.start > Date() && $0.id != current?.id }
            .prefix(4)
            .map { $0 }
    }

    private var unread: [Message] {
        (messages.value ?? []).filter { !$0.isRead }
    }

    private var isInitialLoad: Bool {
        (events.isLoading && !events.hasValue) || (plan.isLoading && !plan.hasValue)
    }

    var body: some View {
        StudGoStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    greeting

                    if isInitialLoad {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        if let current {
                            NavigationLink(value: current) { NextUpCard(event: current) }
                                .buttonStyle(.plain)
                        } else if allEvents.isEmpty, let message = events.errorMessage {
                            problemCard(message)
                        } else {
                            freeCard
                        }

                        if !todaysRemaining.isEmpty {
                            SectionCard(title: "Heute noch", symbol: "clock") {
                                rows(todaysRemaining) { event in
                                    NavigationLink(value: event) {
                                        linkRow { EventRow(event: event) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !laterEvents.isEmpty {
                            SectionCard(title: "Demnächst", symbol: "calendar") {
                                rows(laterEvents) { event in
                                    NavigationLink(value: event) {
                                        linkRow { EventRow(event: event, showDay: true) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !unread.isEmpty {
                            SectionCard(title: unread.count == 1 ? "1 ungelesene Nachricht"
                                                                 : "\(unread.count) ungelesene Nachrichten",
                                        symbol: "envelope.badge") {
                                rows(Array(unread.prefix(3))) { message in
                                    NavigationLink(value: message) {
                                        linkRow { MessageRow(message: message) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let items = news.value, !items.isEmpty {
                            SectionCard(title: "Ankündigungen", symbol: "megaphone") {
                                rows(Array(items.prefix(3))) { item in
                                    NavigationLink(value: item) {
                                        linkRow { NewsRow(item: item) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        InitialsBadge(initials: user.initials, size: 30)
                    }
                    .accessibilityLabel("Profil und Einstellungen")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(user: user)
            }
            .refreshable { await reload(fresh: true) }
            .task { if !events.hasValue || !plan.hasValue { await reload(fresh: false) } }
        }
    }

    // MARK: - Bausteine

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(salutation)
                .font(.title2.bold())
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var freeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: context.isSemesterBreak ? "sun.max.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(context.isSemesterBreak ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.isSemesterBreak ? "Semesterferien" : "Nichts mehr im Kalender")
                    .font(.subheadline.weight(.semibold))
                // Ohne Begründung sieht ein leerer Startbildschirm nach einem
                // Fehler aus — im August ist er schlicht richtig.
                Text(context.emptyExplanation())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func problemCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Termine nicht geladen")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Neu laden") { Task { await reload(fresh: true) } }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .card()
    }

    /// Reihen innerhalb einer Karte, getrennt durch feine Linien.
    @ViewBuilder
    private func rows<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            // Über den Index statt über `enumerated()`: Swift kennt keine
            // Key-Paths in Tupel, `id: \.element.id` wäre nicht übersetzbar.
            ForEach(Array(items.indices), id: \.self) { index in
                if index > 0 {
                    Divider().padding(.vertical, 6)
                }
                row(items[index])
            }
        }
    }

    /// Inhalt einer antippbaren Karte samt Winkel am Rand.
    private func linkRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var salutation: String {
        let name = user.givenName ?? user.formattedName
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: return "Guten Morgen, \(name)"
        case 11..<18: return "Hallo, \(name)"
        default: return "Guten Abend, \(name)"
        }
    }

    // MARK: - Laden

    /// Plant die Terminerinnerungen neu.
    ///
    /// **Hier und nicht im Kalender-Reiter:** „Heute" lädt bei jedem Start,
    /// der Kalender nur, wenn jemand ihn öffnet. Wer die Erinnerungen dort
    /// aufsetzte, bekäme sie nur, solange er den Reiter regelmäßig besucht.
    /// Das Neuplanen räumt vorher alles Eigene weg, ist also gefahrlos zu
    /// wiederholen.
    private func rescheduleReminders() async {
        guard preferences.eventReminders else { return }
        await Notifications.scheduleEventReminders(allEvents,
                                                   leadMinutes: preferences.leadMinutes,
                                                   quietWeekend: preferences.quietWeekend)
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        // Die Abschnitte sind voneinander unabhängig — parallel laden.
        // Stundenplan und Semester teilen sich den Zwischenspeicher mit den
        // anderen Tabs, kosten hier also meist keine eigene Anfrage.
        // Bevorzugt der ICS-Strom: Er liefert echte Sitzungen samt Ausfällen
        // (siehe `StudIPClient.calendarEvents`). Der alte Weg bleibt als
        // Rückfallebene — dann fehlen zwar Ausfälle, aber nicht der Termin.
        let known = courses
        async let loadEvents: Void = events.load {
            do { return try await client.calendarEvents(for: user.id, courses: known) }
            catch { return try await client.events(for: user.id, weeks: 4) }
        }
        async let loadPlan: Void = plan.load { try await client.schedule(for: user.id) }
        async let loadSemesters: Void = semesters.load { try await client.semesters() }
        async let loadMessages: Void = messages.load { try await client.inbox(for: user.id) }
        async let loadNews: Void = news.load { try await client.news(for: user.id) }
        _ = await (loadEvents, loadPlan, loadSemesters, loadMessages, loadNews)
        auth.noteUnread((messages.value ?? []).filter { !$0.isRead }.count)
        // Für die Kursfarben im Kalender: Der ICS-Strom nennt nur den
        // Veranstaltungsnamen, nicht die Kennung.
        if courses.isEmpty, let loaded = try? await client.courses(for: user.id) {
            courses = loaded
        }
        await rescheduleReminders()
    }
}

/// Die Karte ganz oben: was gerade läuft oder als Nächstes ansteht.
/// Der Countdown zählt selbstständig weiter — sonst stünde nach dem Weglegen
/// des Telefons eine falsche Zeit auf dem Bildschirm.
struct NextUpCard: View {
    let event: CourseEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let isRunning = event.start <= now && event.end >= now

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: isRunning ? "play.circle.fill" : "arrow.right.circle.fill")
                        .font(.caption)
                    Text(isRunning ? "Läuft gerade" : "Als Nächstes")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Text(Countdown.text(start: event.start, end: event.end, now: now))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Tint.color(event.tintSeed))

                Text(event.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Label(Format.timeRange(event.start, event.end), systemImage: "clock")
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse").lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if !Calendar.current.isDateInToday(event.start) {
                    Chip(text: Format.dayShort(event.start), symbol: "calendar",
                         color: Tint.color(event.tintSeed))
                }

                if isRunning {
                    ProgressView(value: progress(now: now))
                        .tint(Tint.color(event.tintSeed))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(Tint.surface(event.tintSeed))
            .accessibilityElement(children: .combine)
        }
    }

    private func progress(now: Date) -> Double {
        let total = event.end.timeIntervalSince(event.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(event.start) / total))
    }
}

/// Überschrift plus Karte — die wiederkehrende Form auf dem Startbildschirm.
struct SectionCard<Content: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption2)
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 2)

            content.card()
        }
    }
}
