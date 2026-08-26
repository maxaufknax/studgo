import SwiftUI

/// Der Kalender in drei Lesarten — **Tag**, **Woche** und **Liste**.
///
/// Bis 1.2.0 gab es zwei: ein fünfspaltiges Wochenraster und eine
/// Terminliste. Auf einem iPhone im Hochformat sind fünf Spalten rund
/// 60 Punkte breit; darin steht von „Grundlagen der Rechnerarchitektur"
/// nichts Lesbares. Und wer wissen wollte, was *morgen* ansteht, musste im
/// Raster die Spalte zählen.
///
/// Jetzt:
/// * **Tag** — ein Tag groß, mit Datumsleiste zum Blättern. Die Ansicht, die
///   man morgens vor der Tür braucht.
/// * **Woche** — das Raster, wahlweise 3, 5 oder 7 Spalten. Drei Spalten sind
///   auf dem Telefon lesbar, sieben im Querformat sinnvoll.
/// * **Liste** — die nächsten Wochen am Stück, nach Tagen gruppiert.
struct ScheduleView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    enum Mode: String, CaseIterable, Identifiable {
        case day = "Tag"
        case grid = "Woche"
        case list = "Liste"
        var id: String { rawValue }
    }

    /// Wie viele Spalten das Wochenraster zeigt.
    enum GridSpan: Int, CaseIterable, Identifiable {
        case three = 3
        case workWeek = 5
        case full = 7
        var id: Int { rawValue }

        var label: String {
            switch self {
            case .three: return "3 Tage"
            case .workWeek: return "Mo–Fr"
            case .full: return "ganze Woche"
            }
        }
    }

    @State private var mode: Mode = .day
    /// Der gewählte Tag in der Tagesansicht und der erste im Dreitageraster.
    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var span: GridSpan = .workWeek

    @State private var entries = Loadable<[ScheduleEntry]>()
    /// Der Plan des **kommenden** Semesters — in der vorlesungsfreien Zeit
    /// das Einzige, was es zu zeigen gibt.
    @State private var preview = Loadable<[ScheduleEntry]>()
    @State private var agenda = Loadable<[CourseEvent]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var courses: [Course] = []
    @State private var exportURL: URL?
    @State private var isExporting = false

    /// Ein eigener `Navigator`, weil das Wochenraster aus einem Rückruf heraus
    /// weiterschaltet — ein `NavigationLink` sitzt in einem angetippten Block
    /// nicht sinnvoll unter. Er wird zugleich ins Umfeld gelegt, damit die von
    /// hier erreichbaren `PushLink`-Zeilen (etwa der Dateibereich einer
    /// Veranstaltung) in *diesen* Stapel schieben.
    @State private var navigator = Navigator()

    // MARK: - Abgeleiteter Zustand

    private var context: SemesterContext { SemesterContext(semesters.value ?? []) }

    /// Welcher Wochenplan gerade gilt — und ob er schon der des nächsten
    /// Semesters ist.
    private var activePlan: (entries: [ScheduleEntry], semester: Semester?, isPreview: Bool) {
        let ahead = preview.value ?? []
        if context.isSemesterBreak, !ahead.isEmpty {
            return (ahead, context.upcoming(), true)
        }
        return (entries.value ?? [], context.current(), false)
    }

    /// Beide Pläne mit ihrer jeweiligen Vorlesungszeit — daraus leitet
    /// `EventMerge` Sitzungen ab, wo der ICS-Strom keine liefert.
    private var planWindows: [EventMerge.PlanWindow] {
        [EventMerge.PlanWindow(entries: entries.value ?? [], semester: context.current()),
         EventMerge.PlanWindow(entries: preview.value ?? [], semester: context.upcoming())]
    }

    private func events(from start: Date, days: Int) -> [CourseEvent] {
        EventMerge.combine(dated: agenda.value ?? [],
                           plans: planWindows,
                           from: start,
                           days: days)
    }

    var body: some View {
        NavigationStack(path: $navigator.path) {
            VStack(spacing: 0) {
                SegmentedHeader(title: "Ansicht",
                                options: Mode.allCases,
                                selection: $mode) { $0.rawValue }

                if activePlan.isPreview { previewBanner }

                switch mode {
                case .day: dayView
                case .grid: gridView
                case .list: listView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: exportTarget) { target in
                ShareSheet(items: [target.url])
            }
            .studGoDestinations()
            .refreshable { await load(fresh: true) }
            .task { if entries.value == nil { await load(fresh: false) } }
        }
        .environment(navigator)
    }

    // MARK: - Werkzeugleiste

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if mode == .grid {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Spalten", selection: $span) {
                        ForEach(GridSpan.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Label(span.label, systemImage: "rectangle.split.3x1")
                        .font(.footnote)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    withAnimation { anchor = Calendar.current.startOfDay(for: Date()) }
                } label: {
                    Label("Heute", systemImage: "calendar.badge.clock")
                }
                if let start = context.upcoming()?.lectureStart, start > Date() {
                    Button {
                        withAnimation {
                            anchor = Calendar.current.startOfDay(for: start)
                            mode = .day
                        }
                    } label: {
                        Label("Zum Vorlesungsbeginn", systemImage: "arrow.right.to.line")
                    }
                }
                Divider()
                Button {
                    Task { await exportCalendar() }
                } label: {
                    Label(isExporting ? "Wird geladen…" : "Termine exportieren (.ics)",
                          systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)
                Button {
                    Task { await load(fresh: true) }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Weitere Möglichkeiten")
        }
    }

    /// In der vorlesungsfreien Zeit zeigt das Raster den Plan des **nächsten**
    /// Semesters. Ohne diesen Hinweis sähe es aus, als liefe das Semester
    /// bereits.
    private var previewBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
            Text(bannerText)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10))
    }

    private var bannerText: String {
        guard let semester = activePlan.semester else { return "Plan des kommenden Semesters" }
        guard let start = semester.lectureStart else { return "Plan für \(semester.title)" }
        return "Vorschau auf \(semester.title) — Vorlesungsbeginn \(start.formatted(.dateTime.day().month(.abbreviated)))"
    }

    // MARK: - Tag

    private var dayView: some View {
        VStack(spacing: 0) {
            DayStrip(selection: $anchor, markedDays: daysWithEvents)
            Divider()
            DayAgenda(date: anchor,
                      events: events(from: anchor, days: 1)
                        .filter { Calendar.current.isDate($0.start, inSameDayAs: anchor) },
                      isLoading: agenda.isLoading && !agenda.hasValue,
                      explanation: emptyDayText)
        }
    }

    /// Welche Tage der nächsten Wochen überhaupt etwas enthalten — die
    /// Datumsleiste setzt darunter einen Punkt.
    private var daysWithEvents: Set<Date> {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: min(anchor, Date()))
        return Set(events(from: from, days: 35).map { calendar.startOfDay(for: $0.start) })
    }

    private var emptyDayText: String {
        let calendar = Calendar.current
        if context.lecturePeriod(covering: anchor) == nil {
            return context.emptyExplanation(on: anchor)
        }
        if calendar.isDateInWeekend(anchor) {
            return "Wochenende — nichts eingetragen."
        }
        return "An diesem Tag steht nichts an."
    }

    // MARK: - Woche

    private var gridView: some View {
        Group {
            if !activePlan.entries.isEmpty {
                TimetableView(entries: activePlan.entries,
                              visibleDays: gridColumns) { navigator.push($0) }
            } else {
                CalendarEmptyState(symbol: "calendar",
                                   title: gridEmptyTitle,
                                   message: context.emptyExplanation(),
                                   isLoading: entries.isLoading && !entries.hasValue,
                                   action: gridEmptyAction)
            }
        }
    }

    private var gridEmptyTitle: String {
        context.isSemesterBreak ? "Semesterferien" : "Kein Stundenplan hinterlegt"
    }

    /// In der vorlesungsfreien Zeit ist „erneut versuchen" die falsche
    /// Antwort — es gibt schlicht nichts. Ein Weg in die Terminliste dagegen
    /// führt zu dem, was es doch noch gibt: Klausuren und eigene Termine.
    private var gridEmptyAction: CalendarEmptyState.Action? {
        if context.isSemesterBreak {
            return CalendarEmptyState.Action(title: "Anstehende Termine ansehen",
                                             symbol: "list.bullet") {
                withAnimation { mode = .list }
            }
        }
        return CalendarEmptyState.Action(title: "Erneut versuchen",
                                         symbol: "arrow.clockwise") {
            Task { await load(fresh: true) }
        }
    }

    /// Welche Wochentage nebeneinander stehen.
    ///
    /// Bei drei Spalten wird ab dem gewählten Tag gezählt und über den
    /// Sonntag hinweg umgebrochen — sonst zeigte ein Freitag „Fr, Sa, So"
    /// statt der drei nächsten Vorlesungstage.
    private var gridColumns: [Int] {
        switch span {
        case .full: return Array(1...7)
        case .workWeek: return Array(1...5)
        case .three:
            let first = TimetableView.weekday(of: anchor)
            return (0..<3).map { (first - 1 + $0) % 7 + 1 }
        }
    }

    // MARK: - Liste

    private var listView: some View {
        List {
            ForEach(byDay, id: \.day) { group in
                Section(Format.dayHeader(group.day)) {
                    ForEach(group.events) { event in
                        NavigationLink(value: event) { EventRow(event: event) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if byDay.isEmpty {
                CalendarEmptyState(symbol: "calendar.badge.checkmark",
                                   title: context.isSemesterBreak
                                        ? "Semesterferien"
                                        : "Keine anstehenden Termine",
                                   message: context.emptyExplanation(),
                                   isLoading: agenda.isLoading && !agenda.hasValue,
                                   action: CalendarEmptyState.Action(title: "Erneut laden",
                                                                     symbol: "arrow.clockwise") {
                                       Task { await load(fresh: true) }
                                   })
            }
        }
    }

    /// Sechs Wochen weit — genug, um in den Semesterferien den
    /// Vorlesungsbeginn und die Klausurtermine zu erreichen.
    private var byDay: [(day: Date, events: [CourseEvent])] {
        let upcoming = events(from: Date(), days: 42).filter { $0.end >= Date() }
        return Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
    }

    // MARK: - Laden

    private func load(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        let userID = user.id

        // Die Semester zuerst: Erst danach steht fest, ob überhaupt ein
        // zweiter Plan vorauszuladen ist und welcher.
        await semesters.load { try await client.semesters() }
        let known = SemesterContext(semesters.value ?? [])
        if let loaded = try? await client.courses(for: userID) { courses = loaded }

        async let plan: Void = entries.load { try await client.schedule(for: userID) }
        async let ahead: Void = loadPreview(client: client, context: known)
        async let dates: Void = loadAgenda(client: client)
        _ = await (plan, ahead, dates)
    }

    /// Der Plan des kommenden Semesters — nur in der vorlesungsfreien Zeit.
    ///
    /// `filter[timestamp]` wählt in `UserScheduleShow` das Semester über
    /// `Semester::findByTimestamp()`. Kommt nichts zurück, ist man in dessen
    /// Veranstaltungen schlicht noch nicht eingetragen — das ist der
    /// Regelfall zwei Monate vor Beginn und kein Fehler.
    private func loadPreview(client: StudIPClient, context: SemesterContext) async {
        guard context.isSemesterBreak, let upcoming = context.upcoming(),
              let start = upcoming.start else {
            preview.value = []
            return
        }
        let userID = user.id
        await preview.load { try await client.schedule(for: userID, semesterStart: start) }
    }

    /// Echte Termine — bevorzugt aus dem ICS-Strom.
    ///
    /// Der liefert **jede** Sitzung mit Datum, Raum, Thema und Ausfall;
    /// `/v1/users/{id}/events` kennt nur den persönlichen Kalender. Sollte der
    /// Strom einmal nicht kommen, bleibt der alte Weg — dann fehlen zwar die
    /// Ausfälle, aber der Kalender ist nicht leer.
    private func loadAgenda(client: StudIPClient) async {
        let userID = user.id
        let known = courses
        await agenda.load {
            do {
                return try await client.calendarEvents(for: userID, courses: known)
            } catch {
                return try await client.events(for: userID, weeks: 8)
            }
        }
    }

    // MARK: - Ausfuhr

    private var exportTarget: Binding<WebTarget?> {
        Binding(get: { exportURL.map { WebTarget(url: $0) } },
                set: { if $0 == nil { exportURL = nil } })
    }

    /// Lädt den ICS-Strom herunter und reicht ihn ans Teilen-Menü weiter.
    ///
    /// **Warum nicht als `webcal://`-Abonnement:** Die Route verlangt den
    /// OAuth-Token im `Authorization`-Kopf. Die Kalender-App kann nur
    /// Basic-Auth oder gar nichts mitschicken und bekäme ein 401. Eine
    /// heruntergeladene Datei nimmt sie dagegen an — einmal je Semester
    /// genügt, denn der Export reicht bis 2036.
    private func exportCalendar() async {
        isExporting = true
        defer { isExporting = false }
        guard let text = try? await auth.freshClient.text("/v1/users/\(user.id)/events.ics"),
              !text.isEmpty else { return }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudGo-Termine.ics")
        try? text.write(to: target, atomically: true, encoding: .utf8)
        exportURL = target
    }
}

/// Waagerechte Datumsleiste über der Tagesansicht.
///
/// Ersetzt das Blättern mit Pfeilen: Wer wissen will, ob am Donnerstag etwas
/// ansteht, sieht es hier am Punkt unter dem Datum, ohne dreimal zu tippen.
struct DayStrip: View {
    @Binding var selection: Date
    /// Tage, an denen etwas stattfindet.
    var markedDays: Set<Date> = []
    /// Wie viele Tage die Leiste nach vorn umfasst, ab heute gerechnet.
    var length = 35

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Auch ein paar Tage zurück: Wer den Raum von gestern sucht, findet
        // ihn sonst nicht mehr.
        return (-7..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.timeIntervalSince1970) { day in
                        dayButton(day)
                            .id(day.timeIntervalSince1970)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(selection.timeIntervalSince1970, anchor: .center) }
            .onChange(of: selection) {
                withAnimation { proxy.scrollTo(selection.timeIntervalSince1970, anchor: .center) }
            }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = markedDays.contains(calendar.startOfDay(for: day))

        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = calendar.startOfDay(for: day) }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2)
                    .textCase(.uppercase)
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .monospacedDigit()
                Circle()
                    .fill(hasEvents ? (isSelected ? Color.white : Color.accentColor) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 44)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.accentColor
                          : (isToday ? Color.accentColor.opacity(0.12) : Color.clear))
            )
            .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.dayHeader(day))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Der gewählte Tag als Terminliste.
struct DayAgenda: View {
    let date: Date
    let events: [CourseEvent]
    var isLoading = false
    var explanation: String = ""

    private var total: TimeInterval {
        events.filter { !$0.isCancelled }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                CalendarEmptyState(symbol: Calendar.current.isDateInWeekend(date)
                                        ? "figure.walk" : "cup.and.saucer",
                                   title: Format.dayHeader(date),
                                   message: explanation,
                                   isLoading: isLoading,
                                   action: nil)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        summary
                        ForEach(events) { event in
                            NavigationLink(value: event) { DayAgendaRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
            if total > 0 {
                Chip(text: "\(Int(total / 3600)) Std", symbol: "clock", color: .accentColor)
            }
            Chip(text: events.count == 1 ? "1 Termin" : "\(events.count) Termine",
                 color: .secondary)
        }
        .padding(.bottom, 2)
    }
}

/// Ein Termin in der Tagesansicht — mit Zeitspalte und farbigem Rücken.
struct DayAgendaRow: View {
    let event: CourseEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimeColumn(start: event.start, end: event.end)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Tint.color(event.tintSeed))
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(event.isCancelled)
                    .foregroundStyle(event.isCancelled ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let topic = event.topic, topic != event.title {
                    Text(topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                    if event.isPersonal {
                        Label("Eigener Termin", systemImage: "person.crop.circle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if event.isCancelled {
                    Chip(text: "Fällt aus", symbol: "xmark.circle.fill", color: .red)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Leerzustand des Kalenders — mit **Begründung** statt bloßer Feststellung.
///
/// „Keine anstehenden Termine" sieht in den Semesterferien wie ein Fehler aus.
/// Hier steht stattdessen, warum nichts da ist und wann es weitergeht.
struct CalendarEmptyState: View {
    struct Action {
        let title: String
        let symbol: String
        let perform: () -> Void
    }

    let symbol: String
    let title: String
    var message: String = ""
    var isLoading = false
    var action: Action?

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.tertiary)
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    if !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let action {
                    Button {
                        action.perform()
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Holt eine Veranstaltung anhand ihrer ID nach — der Stundenplan kennt nur
/// die Verknüpfung, nicht den ganzen Datensatz.
struct CourseLoaderView: View {
    let courseID: String
    @Environment(AuthStore.self) private var auth
    @State private var course = Loadable<Course>()

    var body: some View {
        Group {
            if let value = course.value {
                CourseDetailView(course: value)
            } else {
                StateOverlay(isLoading: course.isLoading,
                             errorMessage: course.errorMessage,
                             isEmpty: true,
                             emptyText: "Veranstaltung nicht gefunden",
                             emptySymbol: "books.vertical",
                             retry: { Task { await load() } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if course.value == nil { await load() } }
    }

    private func load() async {
        let client = auth.client
        await course.load { try await client.course(id: courseID) }
    }
}
