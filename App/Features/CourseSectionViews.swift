import SwiftUI

/// Die Unterseiten einer Veranstaltung. Termine, Aushang und Teilnehmende
/// bekommen die bereits geladene Liste von der Übersicht gereicht — sie ist
/// ein `Loadable`, also ein Referenztyp, und bleibt damit dieselbe Instanz.

// MARK: - Termine

struct CourseDatesView: View {
    let course: Course
    let events: Loadable<[CourseEvent]>
    @Environment(AuthStore.self) private var auth

    private var upcoming: [CourseEvent] {
        (events.value ?? []).filter { !$0.isOver }
    }

    /// Vergangene Sitzungen rückwärts: die zuletzt gehaltene zuerst — danach
    /// sucht man, wenn man das Thema der letzten Woche nachschlägt.
    private var past: [CourseEvent] {
        (events.value ?? []).filter(\.isOver).reversed().map { $0 }
    }

    var body: some View {
        List {
            if !upcoming.isEmpty {
                Section("Anstehend") {
                    ForEach(upcoming) { EventRow(event: $0, showDay: true, preferTopic: true) }
                }
            }
            if !past.isEmpty {
                Section("Vergangen") {
                    ForEach(past) { EventRow(event: $0, showDay: true, preferTopic: true) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: events.isLoading,
                         errorMessage: events.errorMessage,
                         isEmpty: (events.value ?? []).isEmpty,
                         emptyText: "Keine Termine",
                         emptySymbol: "calendar",
                         retry: { Task { await reload() } })
        }
        .navigationTitle("Termine")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
    }

    private func reload() async {
        let client = auth.freshClient
        await events.load { try await client.events(for: course) }
    }
}

// MARK: - Teilnehmende

struct CourseParticipantsView: View {
    let course: Course
    let participants: Loadable<[Participant]>
    @Environment(AuthStore.self) private var auth

    @State private var search = ""
    @State private var writingTo: Participant?

    private var filtered: [Participant] {
        let all = participants.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || ($0.username?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    /// Nach Rolle gruppiert, Lehrende zuerst. Alphabetisch sortiert stünde
    /// "Lehrende" hinter "Lesende" — deshalb die eigene Rangfolge.
    private var grouped: [(role: String, people: [Participant])] {
        Dictionary(grouping: filtered) { $0.role }
            .map { (role: $0.key, people: $0.value) }
            .sorted { ($0.people.first?.roleRank ?? 9) < ($1.people.first?.roleRank ?? 9) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.role) { group in
                Section("\(group.role) (\(group.people.count))") {
                    ForEach(group.people) { member in
                        Button {
                            writingTo = member
                        } label: {
                            ParticipantRow(member: member)
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
                         isEmpty: filtered.isEmpty,
                         emptyText: search.isEmpty ? "Keine Teilnehmendenliste" : "Nichts gefunden",
                         emptySymbol: search.isEmpty ? "person.2" : "magnifyingglass",
                         retry: { Task { await reload() } })
        }
        .searchable(text: $search, prompt: "Personen durchsuchen")
        .navigationTitle("Personen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $writingTo) { participant in
            ComposeMessageView(presetRecipientID: participant.userID)
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        let client = auth.freshClient
        await participants.load { try await client.participants(of: course) }
    }
}

struct ParticipantRow: View {
    let member: Participant

    var body: some View {
        HStack(spacing: 12) {
            InitialsBadge(initials: member.initials, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).foregroundStyle(.primary)
                if let label = member.label {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                } else if let username = member.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "square.and.pencil")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Aushang

struct CourseNewsView: View {
    let course: Course
    let news: Loadable<[NewsItem]>
    @Environment(AuthStore.self) private var auth

    var body: some View {
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
                         retry: { Task { await reload() } })
        }
        .navigationTitle("Aushang")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
    }

    private func reload() async {
        let client = auth.freshClient
        await news.load { try await client.news(for: course) }
    }
}

// MARK: - Forum

/// Die Bereiche des Veranstaltungsforums und ihre Beiträge.
///
/// Stud.IP staffelt das Forum dreifach: Bereich → Thema → Beitrag. Die
/// JSON:API bildet das über `/forum-categories/{id}/entries` und
/// `/forum-entries/{id}/entries` ab.
struct CourseForumView: View {
    let course: Course
    @Environment(AuthStore.self) private var auth

    @State private var categories = Loadable<[ForumCategory]>()

    var body: some View {
        List(categories.value ?? []) { category in
            NavigationLink {
                ForumCategoryView(category: category)
            } label: {
                RowLabel(symbol: "folder.badge.person.crop", title: category.title)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: categories.isLoading,
                         errorMessage: categories.errorMessage,
                         isEmpty: (categories.value ?? []).isEmpty,
                         emptyText: "Kein Forum in dieser Veranstaltung",
                         emptySymbol: "text.bubble",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Forum")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if categories.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await categories.load { try await client.forumCategories(of: course) }
    }
}

struct ForumCategoryView: View {
    let category: ForumCategory
    @Environment(AuthStore.self) private var auth

    @State private var entries = Loadable<[ForumEntry]>()

    var body: some View {
        List(entries.value ?? []) { entry in
            NavigationLink {
                ForumEntryView(entry: entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: entries.isLoading,
                         errorMessage: entries.errorMessage,
                         isEmpty: (entries.value ?? []).isEmpty,
                         emptyText: "Keine Themen",
                         emptySymbol: "text.bubble",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if entries.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await entries.load { try await client.forumEntries(in: category) }
    }
}

/// Ein Thema samt Antworten, mit Eingabefeld am Fuß.
struct ForumEntryView: View {
    let entry: ForumEntry
    @Environment(AuthStore.self) private var auth

    @State private var replies = Loadable<[ForumEntry]>()
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline)
                        Text(entry.text).font(.callout).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    ForEach(replies.value ?? []) { reply in
                        VStack(alignment: .leading, spacing: 4) {
                            if reply.title != entry.title {
                                Text(reply.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(reply.text).font(.callout).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await reload(fresh: true) }

            Divider()
            composer
        }
        .navigationTitle("Thema")
        .navigationBarTitleDisplayMode(.inline)
        .task { if replies.value == nil { await reload(fresh: false) } }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Antwort schreiben…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Antwort absenden")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await replies.load { try await client.forumEntries(under: entry) }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        sendError = nil
        do {
            // Stud.IP verlangt auch bei einer Antwort einen Titel; die
            // Weboberfläche setzt dort denselben wie beim Ursprungsbeitrag.
            try await auth.client.replyToForumEntry(entry.id,
                                                    title: entry.title,
                                                    content: text)
            draft = ""
            await reload(fresh: true)
        } catch {
            sendError = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - Wiki

struct CourseWikiView: View {
    let course: Course
    @Environment(AuthStore.self) private var auth

    @State private var pages = Loadable<[WikiPage]>()

    var body: some View {
        List(pages.value ?? []) { page in
            NavigationLink {
                WikiPageView(page: page)
            } label: {
                RowLabel(symbol: "doc.text",
                         title: page.name,
                         subtitle: page.changedAt.map { "Geändert \(Format.listDate($0))" },
                         detail: "v\(page.version)")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: pages.isLoading,
                         errorMessage: pages.errorMessage,
                         isEmpty: (pages.value ?? []).isEmpty,
                         emptyText: "Kein Wiki in dieser Veranstaltung",
                         emptySymbol: "book.closed",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Wiki")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if pages.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await pages.load { try await client.wikiPages(of: course) }
    }
}

struct WikiPageView: View {
    let page: WikiPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(page.name).font(.title3.bold())
                if let changed = page.changedAt {
                    Text("Fassung \(page.version) · geändert \(Format.listDate(changed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(page.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Wiki")
        .navigationBarTitleDisplayMode(.inline)
    }
}
