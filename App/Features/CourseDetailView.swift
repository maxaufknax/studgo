import SwiftUI

/// Alles zu einer Veranstaltung an einem Ort — die Unterbereiche laden erst,
/// wenn sie ausgewählt werden.
struct CourseDetailView: View {
    let course: Course
    @Environment(AuthStore.self) private var auth

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Info"
        case dates = "Termine"
        case news = "Aushang"
        case files = "Dateien"
        case people = "Personen"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .overview
    @State private var events = Loadable<[CourseEvent]>()
    @State private var news = Loadable<[NewsItem]>()
    @State private var participants = Loadable<[Participant]>()
    @State private var writingTo: Participant?

    var body: some View {
        VStack(spacing: 0) {
            SegmentedHeader(title: "Bereich",
                            options: Tab.allCases,
                            selection: $tab) { $0.rawValue }

            switch tab {
            case .overview: overview
            case .dates: dates
            case .news: announcements
            case .files: FolderBrowserView(course: course)
            case .people: people
            }
        }
        .navigationTitle(course.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $writingTo) { participant in
            ComposeMessageView(presetRecipientID: participant.userID)
        }
        .task(id: tab) { await loadCurrentTab() }
    }

    // MARK: - Info

    private var overview: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(course.shortTitle)
                        .font(.headline)
                    if let subtitle = course.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        if let number = course.courseNumber {
                            Chip(text: number, color: Tint.color(course.id))
                        }
                        if let type = auth.courseTypeName(course.typeID) {
                            Chip(text: type, color: Tint.color(course.id))
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Tint.surface(course.id))
            }

            if course.location != nil {
                Section("Eckdaten") {
                    if let location = course.location {
                        LabeledContent("Ort", value: location)
                    }
                }
            }

            if let description = course.description?.strippingHTML, !description.isEmpty {
                Section("Beschreibung") {
                    Text(description).font(.callout).textSelection(.enabled)
                }
            }

            if let extra = course.miscellaneous?.strippingHTML, !extra.isEmpty {
                Section("Sonstiges") {
                    Text(extra).font(.callout).textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Termine

    private var dates: some View {
        let all = events.value ?? []
        let upcoming = all.filter { !$0.isOver }
        let past = all.filter { $0.isOver }.reversed().map { $0 }

        return List {
            if !upcoming.isEmpty {
                Section("Anstehend") {
                    ForEach(upcoming) { EventRow(event: $0, showDay: true, preferTopic: true) }
                }
            }
            if !past.isEmpty {
                Section("Vergangen") {
                    ForEach(past.prefix(30)) { EventRow(event: $0, showDay: true, preferTopic: true) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: events.isLoading,
                         errorMessage: events.errorMessage,
                         isEmpty: all.isEmpty,
                         emptyText: "Keine Termine",
                         emptySymbol: "calendar",
                         retry: { Task { await load(.dates, fresh: true) } })
        }
        .refreshable { await load(.dates, fresh: true) }
    }

    // MARK: - Aushang

    private var announcements: some View {
        List(news.value ?? []) { item in
            NavigationLink(value: item) { NewsRow(item: item) }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }
        .overlay {
            StateOverlay(isLoading: news.isLoading,
                         errorMessage: news.errorMessage,
                         isEmpty: (news.value ?? []).isEmpty,
                         emptyText: "Keine Ankündigungen",
                         emptySymbol: "megaphone",
                         retry: { Task { await load(.news, fresh: true) } })
        }
        .refreshable { await load(.news, fresh: true) }
    }

    // MARK: - Personen

    /// Nach Rolle gruppiert, Lehrende zuerst. Alphabetisch sortiert stünde
    /// "Lehrende" hinter "Lesende" — deshalb die eigene Rangfolge.
    private var groupedParticipants: [(role: String, people: [Participant])] {
        Dictionary(grouping: participants.value ?? []) { $0.role }
            .map { (role: $0.key, people: $0.value) }
            .sorted { ($0.people.first?.roleRank ?? 9) < ($1.people.first?.roleRank ?? 9) }
    }

    private var people: some View {
        List {
            ForEach(groupedParticipants, id: \.role) { group in
                Section("\(group.role) (\(group.people.count))") {
                    ForEach(group.people) { member in
                        Button {
                            writingTo = member
                        } label: {
                            HStack(spacing: 12) {
                                InitialsBadge(initials: member.initials, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.name).foregroundStyle(.primary)
                                    if let label = member.label {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let username = member.username {
                                        Text("@\(username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "square.and.pencil")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(member.userID == nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: participants.isLoading,
                         errorMessage: participants.errorMessage,
                         isEmpty: (participants.value ?? []).isEmpty,
                         emptyText: "Keine Teilnehmendenliste",
                         emptySymbol: "person.2",
                         retry: { Task { await load(.people, fresh: true) } })
        }
        .refreshable { await load(.people, fresh: true) }
    }

    // MARK: - Laden

    private func loadCurrentTab() async {
        switch tab {
        case .dates where events.value == nil: await load(.dates, fresh: false)
        case .news where news.value == nil: await load(.news, fresh: false)
        case .people where participants.value == nil: await load(.people, fresh: false)
        default: break
        }
    }

    private func load(_ target: Tab, fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        switch target {
        case .dates:
            await events.load { try await client.events(for: course) }
        case .news:
            await news.load { try await client.news(for: course) }
        case .people:
            await participants.load { try await client.participants(of: course) }
        default:
            break
        }
    }
}
