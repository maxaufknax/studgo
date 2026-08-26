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
    /// Der Plan des **kommenden** Semesters. Wird mitgeladen, sobald ein
    /// solches Semester bekannt ist — nicht erst in der vorlesungsfreien
    /// Zeit, weil der Umschalter im Raster ihn sonst nur manchmal anböte.
    @State private var preview = Loadable<[ScheduleEntry]>()
    /// Welchen Plan das Raster zeigt. `nil` heißt „automatisch" — die
    /// Vorauswahl aus `SchedulePlan.resolve`. Eine Wahl von Hand bleibt
    /// stehen, auch über das Neuladen hinweg.
    @State private var chosenPlan: SchedulePlanScope?
    @State private var agenda = Loadable<[CourseEvent]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var courses: [Course] = []
    @State private var exportURL: URL?
    @State private var isExporting = false
    /// Stud.IP-Seite im Blatt — für das Anlegen eigener Termine, das die
    /// JSON:API nicht anbietet.
    @State private var webTarget: WebTarget?

    /// Ein eigener `Navigator`, weil das Wochenraster aus einem Rückruf heraus
    /// weiterschaltet — ein `NavigationLink` sitzt in einem angetippten Block
    /// nicht sinnvoll unter. Er wird zugleich ins Umfeld gelegt, damit die von
    /// hier erreichbaren `PushLink`-Zeilen (etwa der Dateibereich einer
    /// Veranstaltung) in *diesen* Stapel schieben.
    @State private var navigator = Navigator()

    // MARK: - Abgeleiteter Zustand

    private var context: SemesterContext { SemesterContext(semesters.value ?? []) }

    /// Welcher Wochenplan gerade gilt. Die Entscheidung selbst steht in
    /// `App/Core/SchedulePlan.swift` — dort ist sie prüfbar, hier wäre sie es
    /// nicht.
    private var plan: SchedulePlan {
        SchedulePlan.resolve(current: entries.value ?? [],
                             upcoming: preview.value ?? [],
                             isSemesterBreak: context.isSemesterBreak,
                             preferred: chosenPlan)
    }

    /// Das Semester, zu dem der gezeigte Plan gehört.
    private var planSemester: Semester? {
        plan.scope == .upcoming ? context.upcoming() : context.current()
    }

    /// Läuft im gezeigten Plan **heute** Vorlesungszeit?
    ///
    /// Ist sie es nicht, stehen die Veranstaltungen zwar im Raster — so wie in
    /// Stud.IP auch —, finden aber gerade nicht statt. Das Raster setzt sie
    /// dann blasser, und darüber steht, woran das liegt.
    private var planIsRunning: Bool {
        guard let period = planSemester.flatMap(SemesterContext.lecturePeriod(of:)) else {
            return false
        }
        return period.contains(Date())
    }

    /// Gibt es überhaupt einen zweiten Plan zum Umschalten?
    private var upcomingHasCourses: Bool {
        SchedulePlan.hasCourses(preview.value ?? [])
    }

    /// Der Umschalter im Menü. Er zeigt, was gerade gilt — auch wenn das
    /// bislang die Automatik entschieden hat; ein Menü, das auf „nichts
    /// gewählt" steht, während sichtbar ein Plan im Bild ist, ist irreführend.
    /// Sobald jemand tippt, gilt die Wahl und die Automatik ist außen vor.
    private var planBinding: Binding<SchedulePlanScope> {
        Binding(get: { plan.scope }, set: { chosenPlan = $0 })
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

                if mode == .grid { planBanner }

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
            .sheet(item: $webTarget, onDismiss: {
                // Was in Stud.IP angelegt wurde, soll danach hier stehen.
                Task { await load(fresh: true) }
            }) { target in
                WebSheet(url: target.url)
            }
            .studGoDestinations(user: user)
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
                    // Der Umschalter steht nur da, wenn es wirklich zwei
                    // Pläne gibt. Ein Menüeintrag, der auf einen leeren Plan
                    // führt, wäre schlechter als keiner.
                    if upcomingHasCourses {
                        Divider()
                        Picker("Semester", selection: planBinding) {
                            Text(context.current()?.title ?? "Laufendes Semester")
                                .tag(SchedulePlanScope.current)
                            Text(context.upcoming()?.title ?? "Kommendes Semester")
                                .tag(SchedulePlanScope.upcoming)
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
                    navigator.push(Route.ownScheduleEntries)
                } label: {
                    Label("Eigene Termine", systemImage: "calendar.badge.plus")
                }
                // Der angetippte Tag wird als Vorgabe mitgegeben: Das Formular
                // in Stud.IP liest `dow` und `start` (siehe
                // `WebLinks.newScheduleEntry`), sodass Wochentag und Uhrzeit
                // schon stehen.
                Button {
                    webTarget = WebTarget(url: WebLinks.newScheduleEntry(
                        weekday: Weekday.of(anchor),
                        start: Format.clock(nextFullHour),
                        end: Format.clock(nextFullHour.addingTimeInterval(3600))))
                } label: {
                    Label("Termin für \(Weekday.full(Weekday.of(anchor))) anlegen",
                          systemImage: "plus.circle")
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

    /// Was über dem Raster steht — und warum überhaupt etwas.
    ///
    /// **Der Befund, der dazu geführt hat.** Nach dem Löschen der beiden
    /// eigenen Termine standen beim nächsten Aktualisieren schlagartig alle
    /// Veranstaltungen des laufenden Semesters im Raster. Beides war für sich
    /// genommen richtig — die Weboberfläche zeigt sie in den Semesterferien
    /// genauso —, aber ohne ein Wort dazu wirkt es wie ein Sprung: Eben noch
    /// zwei Blöcke, jetzt eine volle Woche, und keiner dieser Termine findet
    /// gerade statt.
    ///
    /// Das Raster beantwortet „wie liegt meine Woche", nicht „was steht
    /// an" — dafür gibt es Tag und Liste. Deshalb bleiben die Veranstaltungen
    /// stehen; darüber steht, für welches Semester sie gelten und ob gerade
    /// Vorlesungszeit ist.
    @ViewBuilder
    private var planBanner: some View {
        if let note = planNote {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: note.symbol)
                    .font(.caption)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = note.detail {
                        Text(detail)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0.85)
                    }
                    if let action = note.action {
                        Button(action.title) { chosenPlan = action.scope }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.accentColor.opacity(0.10))
        }
    }

    private struct PlanNote {
        let symbol: String
        let title: String
        var detail: String?
        var action: (title: String, scope: SchedulePlanScope)?
    }

    /// Nur belegte Angaben, keine Schätzungen.
    ///
    /// Es wäre verlockend, je Veranstaltung zu schreiben „ist beendet" — die
    /// Kennungen dafür ständen im ICS-Strom. Sie kommen dort aber über einen
    /// Namensabgleich zustande (`StudIPClient.matchCourse`), und ein
    /// verfehlter Abgleich erklärte eine laufende Veranstaltung für beendet.
    /// Das Semester dagegen liefert seine Vorlesungszeit als Datum mit; darauf
    /// ist Verlass, und für die Frage „findet das gerade statt" genügt sie.
    private var planNote: PlanNote? {
        // Vorlesungszeit im gezeigten Plan: Das Raster gilt, kein Hinweis
        // nötig.
        if planIsRunning { return nil }

        let name = planSemester?.title

        switch plan.scope {
        case .upcoming:
            var detail: String?
            if let start = planSemester?.lectureStart {
                detail = "Vorlesungsbeginn \(Format.longDay(start))\(countdownSuffix)."
            }
            let title = name.map { "Vorschau auf \($0)" } ?? "Plan des kommenden Semesters"
            let backAction: (title: String, scope: SchedulePlanScope)? =
                (title: "Zurück zum laufenden Semester", scope: .current)
            return PlanNote(symbol: "sparkles",
                            title: title,
                            detail: detail,
                            action: backAction)

        case .current:
            // Der Fall aus der Rückmeldung: Semesterferien, im Raster steht
            // der Plan des gerade beendeten Semesters — so wie in Stud.IP.
            var parts: [String] = []
            if let name {
                if let ende = planSemester?.lectureEnd {
                    parts.append("Im Raster steht der Plan des \(name); die Vorlesungszeit endete am \(Format.longDay(ende)).")
                } else {
                    parts.append("Im Raster steht der Plan des \(name).")
                }
            }
            if let next = context.upcoming(), let begin = next.lectureStart {
                parts.append("\(next.title) beginnt am \(Format.longDay(begin))\(countdownSuffix).")
            }
            let switchAction: (title: String, scope: SchedulePlanScope)? =
                upcomingHasCourses
                    ? (title: "Plan des kommenden Semesters zeigen", scope: .upcoming)
                    : nil
            return PlanNote(symbol: "moon.zzz",
                            title: "Vorlesungsfreie Zeit — nichts davon findet gerade statt",
                            detail: parts.isEmpty ? nil : parts.joined(separator: " "),
                            action: switchAction)
        }
    }

    /// „ (in 47 Tagen)" — oder nichts, wenn sich das nicht ausrechnen lässt.
    private var countdownSuffix: String {
        guard let days = context.daysUntilLectures(), days > 0 else { return "" }
        return days == 1 ? " (morgen)" : " (in \(days) Tagen)"
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
                      explanation: emptyDayText,
                      addEntry: {
                          webTarget = WebTarget(url: WebLinks.newScheduleEntry(
                              weekday: Weekday.of(anchor),
                              start: Format.clock(nextFullHour),
                              end: Format.clock(nextFullHour.addingTimeInterval(3600))))
                      })
        }
    }

    /// Welche Tage der nächsten Wochen überhaupt etwas enthalten — die
    /// Datumsleiste setzt darunter einen Punkt.
    private var daysWithEvents: Set<Date> {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: min(anchor, Date()))
        return Set(events(from: from, days: 35).map { calendar.startOfDay(for: $0.start) })
    }

    /// Die nächste volle Stunde auf dem gewählten Tag — als Vorgabe für ein
    /// neu anzulegendes Fenster. Für heute ab jetzt, für jeden anderen Tag
    /// ab 10 Uhr; „0 Uhr" wäre als Vorschlag nutzlos.
    private var nextFullHour: Date {
        let calendar = Calendar.current
        guard calendar.isDateInToday(anchor) else {
            return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: anchor) ?? anchor
        }
        let hour = calendar.component(.hour, from: Date())
        return calendar.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: anchor) ?? anchor
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
            if !plan.entries.isEmpty {
                TimetableView(entries: plan.entries,
                              visibleDays: gridColumns,
                              dimsCourses: !planIsRunning) { navigator.push($0) }
            } else {
                CalendarEmptyState(symbol: "calendar",
                                   title: gridEmptyTitle,
                                   message: context.emptyExplanation(),
                                   isLoading: entries.isLoading && !entries.hasValue,
                                   action: gridEmptyAction)
            }
        }
    }

    /// Seit 1.4.1 steht hier **nicht** mehr „Semesterferien": Der Plan des
    /// Semesters bleibt in der vorlesungsfreien Zeit im Raster stehen, das
    /// Raster ist dann also gar nicht leer. Wer diesen Hinweis jetzt noch
    /// sieht, hat wirklich keinen Stundenplan — weil er in keiner
    /// Veranstaltung eingetragen ist oder noch keinen eigenen Termin angelegt
    /// hat.
    private var gridEmptyTitle: String {
        "Kein Stundenplan hinterlegt"
    }

    /// Ist das Raster wirklich leer, hilft „erneut versuchen" nur, wenn das
    /// Laden schiefging. In der vorlesungsfreien Zeit ist es dagegen der
    /// erwartete Zustand — dort führt der Weg zu dem, was man selbst
    /// eintragen kann.
    private var gridEmptyAction: CalendarEmptyState.Action? {
        if context.isSemesterBreak {
            return CalendarEmptyState.Action(title: "Eigene Termine verwalten",
                                             symbol: "calendar.badge.plus") {
                navigator.push(Route.ownScheduleEntries)
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
            let first = Weekday.of(anchor)
            return (0..<3).map { (first - 1 + $0) % 7 + 1 }
        }
    }

    // MARK: - Liste

    private var listView: some View {
        List {
            ForEach(byDay, id: \.day) { group in
                Section(Format.dayHeader(group.day)) {
                    ForEach(group.events) { event in
                        PushLink(value: event) { EventRow(event: event) }
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

    /// Der Plan des kommenden Semesters.
    ///
    /// `filter[timestamp]` wählt in `UserScheduleShow` das Semester über
    /// `Semester::findByTimestamp()`. Kommt nichts zurück, ist man in dessen
    /// Veranstaltungen schlicht noch nicht eingetragen — das ist der
    /// Regelfall zwei Monate vor Beginn und kein Fehler.
    ///
    /// **Bis 1.4.0 lief das nur in der vorlesungsfreien Zeit.** Jetzt immer,
    /// sobald ein kommendes Semester bekannt ist: Der Umschalter im Raster
    /// muss wissen, ob es dort etwas zu sehen gibt, und diese Auskunft darf
    /// nicht von der Jahreszeit abhängen. Die Anfrage ist klein und liegt nach
    /// dem ersten Mal fünf Minuten im `ResponseCache`.
    private func loadPreview(client: StudIPClient, context: SemesterContext) async {
        guard let upcoming = context.upcoming(), let start = upcoming.start else {
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
    /// Wird angeboten, wenn an diesem Tag nichts steht: In Stud.IP lässt sich
    /// genau dann ein eigener Block eintragen, und das ist der häufigste
    /// Grund, warum jemand einen leeren Tag ansieht.
    var addEntry: (() -> Void)?

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
                                   action: addEntry.map {
                                       CalendarEmptyState.Action(title: "Eigenen Termin eintragen",
                                                                 symbol: "plus.circle",
                                                                 perform: $0)
                                   })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        summary
                        ForEach(events) { event in
                            PushButton(value: event) { DayAgendaRow(event: event) }
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
