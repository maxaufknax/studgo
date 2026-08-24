import SwiftUI

/// Stundenplan in zwei Lesarten: die wiederkehrende Woche und die
/// tatsächlichen Termine mit Datum.
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedHeader(title: "Ansicht",
                                options: Mode.allCases,
                                selection: $mode) { $0.rawValue }

                switch mode {
                case .week: weekList
                case .upcoming: upcomingList
                }
            }
            .navigationTitle("Stundenplan")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await reload() }
            .task { await reloadIfNeeded() }
        }
    }

    // MARK: - Woche

    /// Stud.IP zählt Wochentage 1 = Montag … 7 = Sonntag.
    private var byWeekday: [(day: Int, entries: [ScheduleEntry])] {
        Dictionary(grouping: entries.value ?? [], by: \.weekday)
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, entries: $0.value.sorted { $0.start < $1.start }) }
    }

    private var weekList: some View {
        List {
            ForEach(byWeekday, id: \.day) { group in
                Section(group.entries.first?.weekdayName ?? "") {
                    ForEach(group.entries) { entry in
                        HStack(spacing: 12) {
                            AccentBar(seed: entry.title)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title).font(.body.weight(.medium))
                                Text(entry.timeRange)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let location = entry.location {
                                    Label(location, systemImage: "mappin.and.ellipse")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else if let description = entry.description?.strippingHTML,
                                          !description.isEmpty {
                                    Text(description)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .overlay {
            StateOverlay(isLoading: entries.isLoading,
                         errorMessage: entries.errorMessage,
                         isEmpty: byWeekday.isEmpty,
                         emptyText: "Kein Stundenplan hinterlegt",
                         emptySymbol: "calendar",
                         retry: { Task { await reload() } })
        }
    }

    // MARK: - Termine

    private var byDay: [(day: Date, events: [CourseEvent])] {
        let upcoming = (events.value ?? []).filter { $0.end >= Date() }
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
        .overlay {
            StateOverlay(isLoading: events.isLoading,
                         errorMessage: events.errorMessage,
                         isEmpty: byDay.isEmpty,
                         emptyText: "Keine anstehenden Termine",
                         emptySymbol: "calendar.badge.checkmark",
                         retry: { Task { await reload() } })
        }
    }

    // MARK: - Laden

    private func reloadIfNeeded() async {
        guard entries.value == nil else { return }
        await reload()
    }

    private func reload() async {
        let client = auth.client
        async let plan: Void = entries.load { try await client.schedule(for: user.id) }
        async let dates: Void = events.load { try await client.events(for: user.id) }
        _ = await (plan, dates)
    }
}
