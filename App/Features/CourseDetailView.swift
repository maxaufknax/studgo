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
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tab) { await loadCurrentTab() }
    }

    // MARK: - Info

    private var overview: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(course.title).font(.headline)
                    if let subtitle = course.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Eckdaten") {
                if let number = course.courseNumber {
                    LabeledContent("Nummer", value: number)
                }
                if let type = course.courseType {
                    LabeledContent("Art", value: type)
                }
                if let location = course.location {
                    LabeledContent("Ort", value: location)
                }
            }

            if let description = course.description?.strippingHTML, !description.isEmpty {
                Section("Beschreibung") {
                    Text(description).font(.callout)
                }
            }
        }
    }

    // MARK: - Termine

    private var dates: some View {
        let all = events.value ?? []
        let upcoming = all.filter { $0.end >= Date() }
        let past = all.filter { $0.end < Date() }.reversed().map { $0 }

        return List {
            if !upcoming.isEmpty {
                Section("Anstehend") {
                    ForEach(upcoming) { EventRow(event: $0, showDay: true) }
                }
            }
            if !past.isEmpty {
                Section("Vergangen") {
                    ForEach(past.prefix(20)) { EventRow(event: $0, showDay: true) }
                }
            }
        }
        .overlay {
            StateOverlay(isLoading: events.isLoading,
                         errorMessage: events.errorMessage,
                         isEmpty: all.isEmpty,
                         emptyText: "Keine Termine",
                         emptySymbol: "calendar",
                         retry: { Task { await load(.dates) } })
        }
        .refreshable { await load(.dates) }
    }

    // MARK: - Aushang

    private var announcements: some View {
        List(news.value ?? []) { item in
            NavigationLink(value: item) { NewsRow(item: item) }
        }
        .navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }
        .overlay {
            StateOverlay(isLoading: news.isLoading,
                         errorMessage: news.errorMessage,
                         isEmpty: (news.value ?? []).isEmpty,
                         emptyText: "Keine Ankündigungen",
                         emptySymbol: "megaphone",
                         retry: { Task { await load(.news) } })
        }
        .refreshable { await load(.news) }
    }

    // MARK: - Personen

    private var people: some View {
        let grouped = Dictionary(grouping: participants.value ?? []) { $0.role ?? "Weitere" }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }

        return List {
            ForEach(grouped, id: \.key) { group in
                Section("\(group.key) (\(group.value.count))") {
                    ForEach(group.value) { member in
                        HStack(spacing: 12) {
                            InitialsBadge(initials: member.initials, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.name)
                                if let username = member.username {
                                    Text("@\(username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            StateOverlay(isLoading: participants.isLoading,
                         errorMessage: participants.errorMessage,
                         isEmpty: (participants.value ?? []).isEmpty,
                         emptyText: "Keine Teilnehmendenliste",
                         emptySymbol: "person.2",
                         retry: { Task { await load(.people) } })
        }
        .refreshable { await load(.people) }
    }

    // MARK: - Laden

    private func loadCurrentTab() async {
        switch tab {
        case .dates where events.value == nil: await load(.dates)
        case .news where news.value == nil: await load(.news)
        case .people where participants.value == nil: await load(.people)
        default: break
        }
    }

    private func load(_ target: Tab) async {
        let client = auth.client
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

extension Participant {
    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }
}
