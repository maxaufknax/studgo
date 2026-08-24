import SwiftUI

/// Stundenplan in zwei Lesarten: die Woche als Raster und die tatsächlichen
/// Termine mit Datum.
struct ScheduleView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    enum Mode: String, CaseIterable, Identifiable {
        case week = "Woche"
        case upcoming = "Termine"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .week
    @State private var entries = Loadable<[ScheduleEntry]>()
    @State private var events = Loadable<[CourseEvent]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var selected: ScheduleEntry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedHeader(title: "Ansicht",
                                options: Mode.allCases,
                                selection: $mode) { $0.rawValue }

                switch mode {
                case .week: week
                case .upcoming: upcomingList
                }
            }
            .navigationTitle("Stundenplan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Aktualisieren")
                }
            }
            .sheet(item: $selected) { entry in
                ScheduleEntryDetailView(entry: entry)
            }
            .task { await reloadIfNeeded() }
        }
    }

    // MARK: - Woche

    private var week: some View {
        Group {
            if let plan = entries.value, !plan.isEmpty {
                TimetableView(entries: plan) { selected = $0 }
            } else {
                StateOverlay(isLoading: entries.isLoading,
                             errorMessage: entries.errorMessage,
                             isEmpty: true,
                             emptyText: "Kein Stundenplan hinterlegt",
                             emptySymbol: "calendar",
                             retry: { Task { await reload() } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Termine

    private var byDay: [(day: Date, events: [CourseEvent])] {
        // Ohne die abgeleiteten Sitzungen stünde hier "keine Termine",
        // während das Wochenraster nebenan voll ist — siehe `EventMerge`.
        let merged = EventMerge.combine(dated: events.value ?? [],
                                        plan: entries.value ?? [],
                                        semesters: semesters.value ?? [],
                                        days: 21)
        let upcoming = merged.filter { $0.end >= Date() }
        return Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
    }

    private var upcomingList: some View {
        List {
            ForEach(byDay, id: \.day) { group in
                Section(Format.dayHeader(group.day)) {
                    ForEach(group.events) { EventRow(event: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: events.isLoading,
                         errorMessage: events.errorMessage,
                         isEmpty: byDay.isEmpty,
                         emptyText: "Keine anstehenden Termine",
                         emptySymbol: "calendar.badge.checkmark",
                         retry: { Task { await reload() } })
        }
        .refreshable { await reload() }
    }

    // MARK: - Laden

    private func reloadIfNeeded() async {
        guard entries.value == nil else { return }
        await load(fresh: false)
    }

    private func reload() async {
        await load(fresh: true)
    }

    private func load(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        async let plan: Void = entries.load { try await client.schedule(for: user.id) }
        async let dates: Void = events.load { try await client.events(for: user.id) }
        async let terms: Void = semesters.load { try await client.semesters() }
        _ = await (plan, dates, terms)
    }
}

/// Was hinter einem Block im Wochenraster steckt — und der Weg von dort in
/// die zugehörige Veranstaltung.
struct ScheduleEntryDetailView: View {
    let entry: ScheduleEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title)
                            .font(.headline)
                        Text("\(entry.weekdayName), \(entry.timeRange)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Tint.surface(entry.tintSeed))
                }

                Section {
                    if let location = entry.location {
                        LabeledContent("Ort", value: location)
                    }
                    LabeledContent("Art", value: entry.isCourse ? "Veranstaltung" : "Eigener Eintrag")
                }

                if let description = entry.description?.strippingHTML, !description.isEmpty {
                    Section("Notiz") {
                        Text(description).font(.callout)
                    }
                }

                if let courseID = entry.courseID {
                    Section {
                        NavigationLink {
                            CourseLoaderView(courseID: courseID)
                        } label: {
                            RowLabel(symbol: "books.vertical", title: "Zur Veranstaltung")
                        }
                    }
                }
            }
            .navigationTitle("Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
