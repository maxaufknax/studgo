import SwiftUI

/// Alles, was über den eigenen Stundenplan hinausgeht: was in den belegten
/// Veranstaltungen passiert, der öffentliche Blubber-Strom, das
/// Vorlesungsverzeichnis, Kontakte und Einrichtungen.
struct CampusView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var activities = Loadable<[ActivityItem]>()
    @State private var publicThreads = Loadable<[BlubberThread]>()
    @State private var isWritingThread = false

    private var recentActivities: [ActivityItem] {
        Array((activities.value ?? []).prefix(6))
    }

    private var recentThreads: [BlubberThread] {
        Array((publicThreads.value ?? []).prefix(4))
    }

    var body: some View {
        NavigationStack {
            List {
                meSection
                activitySection
                blubberSection
                directorySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Campus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isWritingThread = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Neuen Blubber-Faden schreiben")
                }
            }
            .sheet(isPresented: $isWritingThread) {
                NewBlubberThreadView { await reload(fresh: true) }
            }
            .navigationDestination(for: BlubberThread.self) { BlubberThreadView(thread: $0) }
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .refreshable { await reload(fresh: true) }
            .task { if activities.value == nil { await reload(fresh: false) } }
        }
    }

    // MARK: - Eigene Zahlen

    private var meSection: some View {
        Section {
            NavigationLink {
                StatisticsView(user: user)
            } label: {
                RowLabel(symbol: "chart.bar.xaxis",
                         title: "Dein Semester",
                         subtitle: "Fortschritt, Wochenlast, dein Verlauf")
            }
        }
    }

    // MARK: - Neuigkeiten

    private var activitySection: some View {
        Section {
            if recentActivities.isEmpty {
                CampusPlaceholderRow(isLoading: activities.isLoading,
                                     message: activities.errorMessage
                                        ?? "Noch keine Aktivitäten",
                                     symbol: "sparkles")
            } else {
                ForEach(recentActivities) { ActivityRow(item: $0) }
                NavigationLink {
                    ActivityStreamView(user: user)
                } label: {
                    RowLabel(symbol: "clock.arrow.circlepath", title: "Ganzer Verlauf")
                }
            }
        } header: {
            Text("Was passiert")
        } footer: {
            Text("Neue Dateien, Forenbeiträge und Ankündigungen aus den belegten Veranstaltungen.")
        }
    }

    // MARK: - Blubber

    private var blubberSection: some View {
        Section {
            if recentThreads.isEmpty {
                CampusPlaceholderRow(isLoading: publicThreads.isLoading,
                                     message: publicThreads.errorMessage
                                        ?? "Im öffentlichen Strom ist es still",
                                     symbol: "globe.europe.africa")
            } else {
                ForEach(recentThreads) { thread in
                    NavigationLink(value: thread) {
                        BlubberThreadRow(thread: thread)
                    }
                }
                NavigationLink {
                    PublicBlubberView()
                } label: {
                    RowLabel(symbol: "bubble.left.and.bubble.right", title: "Alle öffentlichen Fäden")
                }
            }
        } header: {
            Text("Öffentlicher Blubber")
        }
    }

    // MARK: - Verzeichnis

    private var directorySection: some View {
        Section("Verzeichnis") {
            NavigationLink {
                CourseSearchView()
            } label: {
                RowLabel(symbol: "magnifyingglass",
                         title: "Veranstaltungen suchen",
                         subtitle: "Das ganze Vorlesungsverzeichnis")
            }
            NavigationLink {
                PersonSearchView()
            } label: {
                RowLabel(symbol: "person.crop.circle.badge.questionmark",
                         title: "Personen finden",
                         subtitle: "Nach Name oder Kennung")
            }
            NavigationLink {
                ContactsView(user: user)
            } label: {
                RowLabel(symbol: "person.crop.circle", title: "Meine Kontakte")
            }
            NavigationLink {
                StudygroupsView()
            } label: {
                RowLabel(symbol: "person.3",
                         title: "Studiengruppen",
                         subtitle: "Vorschläge aus deinem Umfeld")
            }
            NavigationLink {
                InstitutesView(user: user)
            } label: {
                RowLabel(symbol: "building.columns", title: "Meine Einrichtungen")
            }
            NavigationLink {
                NewsView(user: user)
            } label: {
                RowLabel(symbol: "megaphone", title: "Ankündigungen")
            }
        }
    }

    // MARK: - Laden

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        async let stream: Void = activities.load { try await client.activityStream(for: user.id) }
        async let threads: Void = publicThreads.load {
            try await client.blubberThreads(.publicStream, limit: 25)
        }
        _ = await (stream, threads)
    }
}

/// Platzhalterzeile in einer Karte — Spinner, Fehler oder Hinweis, ohne die
/// ganze Liste zu überlagern.
struct CampusPlaceholderRow: View {
    let isLoading: Bool
    let message: String
    var symbol: String = "tray"

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: symbol).foregroundStyle(.tertiary)
            }
            Text(isLoading ? "Wird geladen…" : message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Aktivitätenstrom

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.symbol)
                .font(.system(size: 14))
                .foregroundStyle(Tint.color(item.tintSeed))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Tint.surface(item.tintSeed))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)

                if !item.content.isEmpty {
                    Text(item.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Chip(text: item.kindLabel, color: Tint.color(item.tintSeed))
                    if let course = item.courseName {
                        Text(course)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if let created = item.createdAt {
                Text(Format.listDate(created))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct ActivityStreamView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var activities = Loadable<[ActivityItem]>()
    @State private var kind: String?

    /// Die tatsächlich vorkommenden Arten — eine feste Liste zu zeigen hieße,
    /// Filter anzubieten, die in dieser Installation nie etwas treffen.
    private var kinds: [String] {
        Array(Set((activities.value ?? []).compactMap(\.activityType))).sorted()
    }

    private var filtered: [ActivityItem] {
        guard let kind else { return activities.value ?? [] }
        return (activities.value ?? []).filter { $0.activityType == kind }
    }

    private var grouped: [(day: Date, items: [ActivityItem])] {
        Dictionary(grouping: filtered.filter { $0.createdAt != nil }) {
            Calendar.current.startOfDay(for: $0.createdAt ?? Date())
        }
        .sorted { $0.key > $1.key }
        .map { (day: $0.key, items: $0.value) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.day) { group in
                Section(Format.dayHeader(group.day)) {
                    ForEach(group.items) { ActivityRow(item: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: activities.isLoading,
                         errorMessage: activities.errorMessage,
                         isEmpty: filtered.isEmpty,
                         emptyText: "Keine Aktivitäten",
                         emptySymbol: "sparkles",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Art", selection: $kind) {
                        Text("Alles").tag(String?.none)
                        ForEach(kinds, id: \.self) { value in
                            Text(label(for: value)).tag(String?.some(value))
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable { await reload(fresh: true) }
        .task { if activities.value == nil { await reload(fresh: false) } }
    }

    private func label(for value: String) -> String {
        switch value {
        case "documents": return "Dateien"
        case "forum": return "Forum"
        case "news": return "Ankündigungen"
        case "wiki": return "Wiki"
        case "schedule": return "Termine"
        case "participants": return "Teilnahme"
        case "message": return "Nachrichten"
        default: return value.capitalized
        }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await activities.load { try await client.activityStream(for: user.id, limit: 150) }
    }
}

// MARK: - Öffentlicher Blubber

struct PublicBlubberView: View {
    @Environment(AuthStore.self) private var auth

    @State private var threads = Loadable<[BlubberThread]>()
    @State private var search = ""

    var body: some View {
        List(threads.value ?? []) { thread in
            NavigationLink(value: thread) {
                BlubberThreadRow(thread: thread)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: threads.isLoading,
                         errorMessage: threads.errorMessage,
                         isEmpty: (threads.value ?? []).isEmpty,
                         emptyText: "Nichts im öffentlichen Strom",
                         emptySymbol: "globe.europe.africa",
                         retry: { Task { await reload(fresh: true) } })
        }
        // Serverseitig gesucht: der öffentliche Strom kann Tausende Fäden
        // führen, von denen die App nur einen Ausschnitt geladen hat.
        .searchable(text: $search, prompt: "Öffentliche Fäden durchsuchen")
        .onSubmit(of: .search) { Task { await reload(fresh: true) } }
        .navigationTitle("Öffentlich")
        .navigationBarTitleDisplayMode(.inline)
        // Das Ziel meldet `CampusView` für den ganzen Stapel an.
        .refreshable { await reload(fresh: true) }
        .task { if threads.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        await threads.load {
            try await client.blubberThreads(.publicStream,
                                            search: term.isEmpty ? nil : term,
                                            limit: 80)
        }
    }
}

// MARK: - Kontakte

struct ContactsView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var contacts = Loadable<[Contact]>()
    @State private var search = ""
    @State private var selected: Contact?

    private var filtered: [Contact] {
        let all = contacts.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || ($0.username?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        List(filtered) { contact in
            Button {
                selected = contact
            } label: {
                HStack(spacing: 12) {
                    InitialsBadge(initials: contact.initials, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).foregroundStyle(.primary)
                        if let username = contact.username {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await remove(contact) }
                } label: {
                    Label("Entfernen", systemImage: "person.badge.minus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: contacts.isLoading,
                         errorMessage: contacts.errorMessage,
                         isEmpty: filtered.isEmpty,
                         emptyText: search.isEmpty ? "Keine Kontakte" : "Nichts gefunden",
                         emptySymbol: search.isEmpty ? "person.crop.circle" : "magnifyingglass",
                         retry: { Task { await reload(fresh: true) } })
        }
        .searchable(text: $search, prompt: "Kontakte durchsuchen")
        .navigationTitle("Kontakte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PersonSearchView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Kontakt hinzufügen")
            }
        }
        .sheet(item: $selected) { contact in
            PersonSheet(personID: contact.id,
                        name: contact.name,
                        subtitle: contact.username.map { "@\($0)" },
                        isContact: true)
        }
        .refreshable { await reload(fresh: true) }
        .task { if contacts.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await contacts.load { try await client.contacts(for: user.id) }
    }

    private func remove(_ contact: Contact) async {
        try? await auth.client.removeContact(contact.id, for: user.id)
        await reload(fresh: true)
    }
}

// MARK: - Einrichtungen

struct InstitutesView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var institutes = Loadable<[Institute]>()

    var body: some View {
        List(institutes.value ?? []) { institute in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(institute.name).font(.subheadline.weight(.medium))
                    if institute.isFaculty {
                        Chip(text: "Fakultät", color: .accentColor)
                    }
                }
                if let type = institute.typeName {
                    Text(type).font(.caption).foregroundStyle(.secondary)
                }
                if let address = institute.address {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let phone = institute.phone {
                    Label(phone, systemImage: "phone")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: institutes.isLoading,
                         errorMessage: institutes.errorMessage,
                         isEmpty: (institutes.value ?? []).isEmpty,
                         emptyText: "Keine Einrichtungen",
                         emptySymbol: "building.columns",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Einrichtungen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if institutes.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await institutes.load { try await client.instituteMemberships(for: user.id) }
    }
}
