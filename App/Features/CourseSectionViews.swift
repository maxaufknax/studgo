import SwiftUI

/// Die Unterseiten einer Veranstaltung.
///
/// **Jede lädt ihre Liste selbst.** Bis 1.3.0 reichte die Übersicht ihr
/// bereits geladenes `Loadable` herein - das ging nur, solange sie die
/// Unterseite als `NavigationLink { … }` selbst aufbaute, und genau diese
/// Bauform war die Ursache der Routing-Fehler (siehe `Route`). Über den Pfad
/// geschoben wird ein *Wert*, keine Ansicht; die Liste muss also von hier aus
/// beschafft werden. Teuer ist das nicht: Die Übersicht hat dieselbe Adresse
/// gerade eben abgefragt, und `ResponseCache` beantwortet sie fünf Minuten
/// lang von der Platte.

// MARK: - Termine

struct CourseDatesView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var events = Loadable<[CourseEvent]>()

    private var upcoming: [CourseEvent] {
        (events.value ?? []).filter { !$0.isOver }
    }

    /// Vergangene Sitzungen rückwärts: die zuletzt gehaltene zuerst - danach
    /// sucht man, wenn man das Thema der letzten Woche nachschlägt.
    private var past: [CourseEvent] {
        (events.value ?? []).filter(\.isOver).reversed().map { $0 }
    }

    var body: some View {
        List {
            if !upcoming.isEmpty {
                Section("Anstehend") {
                    ForEach(upcoming) { event in
                        PushLink(value: event) {
                            EventRow(event: event, showDay: true, preferTopic: true)
                        }
                    }
                }
            }
            if !past.isEmpty {
                Section("Vergangen") {
                    ForEach(past) { event in
                        PushLink(value: event) {
                            EventRow(event: event, showDay: true, preferTopic: true)
                        }
                    }
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
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Termine")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if events.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await events.load { try await client.events(for: course) }
    }
}

// MARK: - Teilnehmende

struct CourseParticipantsView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var participants = Loadable<[Participant]>()
    @StateObject private var groups = Loadable<[StatusGroup]>()
    @State private var search = ""
    @State private var selected: Participant?
    /// „Gruppen“ statt „Teilnehmende“ zeigen - erreicht, wer die Umschaltung
    /// antippt; sie erscheint nur, wenn der Kurs wirklich Gruppen hat.
    @State private var showsGroups = false
    @State private var webTarget: WebTarget?

    private var filtered: [Participant] {
        let all = participants.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || ($0.username?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    /// Nach Rolle gruppiert, Lehrende zuerst. Alphabetisch sortiert stünde
    /// "Lehrende" hinter "Lesende" - deshalb die eigene Rangfolge.
    private var grouped: [(role: String, people: [Participant])] {
        Dictionary(grouping: filtered) { $0.role }
            .map { (role: $0.key, people: $0.value) }
            .sorted { ($0.people.first?.roleRank ?? 9) < ($1.people.first?.roleRank ?? 9) }
    }

    /// Zeigt die Umschaltung nur, wenn der Kurs Gruppen hat. Ein Fehlschlag
    /// dieses Abrufs (etwa eine 403 ohne das Recht `canShowCourse`) ist kein
    /// Grund, die Teilnehmenden damit zu verlieren - er zeigt sich einfach
    /// nicht, die Liste läuft unberührt weiter.
    private var showsToggle: Bool { !(groups.value ?? []).isEmpty }

    var body: some View {
        List {
            if showsToggle {
                Section {
                    Picker("Ansicht", selection: $showsGroups) {
                        Text("Teilnehmende").tag(false)
                        Text("Gruppen").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Ansicht wechseln")
                }
            }

            if showsToggle, showsGroups {
                groupsSection
            } else {
                ForEach(grouped, id: \.role) { group in
                    Section("\(group.role) (\(group.people.count))") {
                        ForEach(group.people) { member in
                            Button {
                                selected = member
                            } label: {
                                ParticipantRow(member: member)
                            }
                            .buttonStyle(.plain)
                            .disabled(member.userID == nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            // Die Leere-Anzeige betrifft die Teilnehmendenliste; in der
            // Gruppenansicht wäre sie fehl am Platz.
            StateOverlay(isLoading: participants.isLoading,
                         errorMessage: participants.errorMessage,
                         isEmpty: !showsGroups && filtered.isEmpty,
                         emptyText: search.isEmpty ? "Keine Teilnehmendenliste" : "Nichts gefunden",
                         emptySymbol: search.isEmpty ? "person.2" : "magnifyingglass",
                         retry: { Task { await reload(fresh: true) } })
        }
        .searchable(text: $search, prompt: "Personen durchsuchen")
        .navigationTitle("Personen")
        .navigationBarTitleDisplayMode(.inline)
        // Nicht mehr direkt ins Nachrichtenfenster: von hier aus lässt sich
        // jetzt auch die Sprechstunde buchen oder die Person in die Kontakte
        // aufnehmen.
        .sheet(item: $selected) { participant in
            if let userID = participant.userID {
                PersonSheet(personID: userID,
                            name: participant.name,
                            subtitle: participant.label ?? participant.role)
            }
        }
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url).ignoresSafeArea()
        }
        .refreshable { await reload(fresh: true) }
        .task {
            if participants.value == nil { await reload(fresh: false) }
        }
    }

    /// Die Gruppen des Kurses: Name, Beschreibung, Kapazität, Zeitraum.
    /// Mitglieder und das Eintragen führt die App auf die Weboberfläche -
    /// die Schnittstelle liefert beides nicht (siehe `StatusGroup`).
    private var groupsSection: some View {
        Section {
            ForEach(groups.value ?? []) { group in
                StatusGroupRow(group: group)
            }
            Button {
                webTarget = WebTarget(url: WebLinks.courseGroups(course.id))
            } label: {
                RowLabel(symbol: "safari",
                        title: "Mitglieder ansehen und eintragen",
                        subtitle: "Öffnet die Weboberfläche von Stud.IP")
            }
            .buttonStyle(.plain)
        } header: {
            Text("Gruppen")
        } footer: {
            Text("Die Liste nennt keine Mitglieder. In der Weboberfläche stehen sie - dort lässt sich auch ein- und austragen, soweit die Gruppe das erlaubt.")
        }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await participants.load { try await client.participants(of: course) }
        // Gruppen still nachziehen: Ein Fehlschlag dieses Abrufs darf die
        // Teilnehmendenliste nicht beeinträchtigen (siehe `showsToggle`).
        await groups.load { try await client.statusGroups(of: course) }
    }
}

/// Zeile einer Statusgruppe.
private struct StatusGroupRow: View {
    let group: StatusGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.shortName)
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                Label(capacity, systemImage: "person.2")
                if let window = window { Label(window, systemImage: "calendar") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let description = group.description {
                FormattedText(raw: description, font: .callout, blockLimit: 3)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// **0 heißt unbegrenzt** - es ist die Kapazität der Gruppe, keine
    /// Belegung, und auch nicht „voll“.
    private var capacity: String {
        group.size > 0
            ? String(localized: "maximal \(group.size) Plätze")
            : String(localized: "ohne Kapazitätsgrenze")
    }

    /// Der Eintragungszeitraum von Gruppen mit freier Einschreibung.
    private var window: String? {
        guard group.isSelfassignable else { return nil }
        switch (group.selfassignStart, group.selfassignEnd) {
        case let (start?, end?):
            return String(localized: "Eintragen vom \(start.formatted(date: .abbreviated, time: .omitted)) bis \(end.formatted(date: .abbreviated, time: .omitted))")
        case let (start?, nil):
            return String(localized: "Eintragen ab \(start.formatted(date: .abbreviated, time: .omitted))")
        case let (nil, end?):
            return String(localized: "Eintragen bis \(end.formatted(date: .abbreviated, time: .omitted))")
        case (nil, nil):
            return String(localized: "Eintragen jederzeit möglich")
        }
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
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Aushang

struct CourseNewsView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var news = Loadable<[NewsItem]>()

    var body: some View {
        List(news.value ?? []) { item in
            PushLink(value: item) { NewsRow(item: item) }
        }
        .listStyle(.insetGrouped)
        // Das Ziel meldet der Reiter an seiner Wurzel an - siehe
        // `StudGoDestinations`.
        .overlay {
            StateOverlay(isLoading: news.isLoading,
                         errorMessage: news.errorMessage,
                         isEmpty: (news.value ?? []).isEmpty,
                         emptyText: "Keine Ankündigungen",
                         emptySymbol: "megaphone",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Aushang")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if news.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
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
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var categories = Loadable<[ForumCategory]>()

    var body: some View {
        List(categories.value ?? []) { category in
            PushLink(value: Route.forumCategory(category)) {
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
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var entries = Loadable<[ForumEntry]>()

    var body: some View {
        List(entries.value ?? []) { entry in
            PushLink(value: Route.forumEntry(entry)) {
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
            .moderated(entry.moderationTarget)
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
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var replies = Loadable<[ForumEntry]>()
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline)
                        FormattedText(raw: entry.content)
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
                            FormattedText(raw: reply.content)
                        }
                        .moderated(reply.moderationTarget)
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
                        Image(systemName: "arrow.up.circle.fill").font(.title)
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
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var pages = Loadable<[WikiPage]>()

    var body: some View {
        List(pages.value ?? []) { page in
            PushLink(value: Route.wikiPage(page)) {
                RowLabel(symbol: "doc.text",
                         title: page.name,
                         subtitle: page.changedAt.map { String(localized: "Geändert \(Format.listDate($0))") },
                         detail: "v\(page.version)")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            // Ein leeres Wiki beantwortet Stud.IP mit 404; der Client fängt
            // das ab und liefert eine leere Liste. Hier steht deshalb der
            // ehrliche Hinweis statt einer Fehlermeldung.
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

/// Eine Wikiseite.
///
/// Wikitexte sind der Regelfall für Stud.IP-Auszeichnung: Überschriften mit
/// `!`, Aufzählungen mit `-`, Verweise als `[Text]url`. Als Klartext gezeigt
/// stand davon jedes Sonderzeichen wörtlich auf dem Schirm.
struct WikiPageView: View {
    let page: WikiPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(page.name).font(.title3.bold())
                    if page.isStartPage {
                        Chip(text: "Startseite", color: .accentColor)
                    }
                }
                if let changed = page.changedAt {
                    Text("Fassung \(page.version) · geändert \(Format.listDate(changed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                if page.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Diese Seite ist leer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    FormattedText(raw: page.content, font: .body, isDocument: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Wiki")
        .navigationBarTitleDisplayMode(.inline)
    }
}


// MARK: - Blubber einer Veranstaltung

struct CourseBlubberView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var threads = Loadable<[BlubberThread]>()
    @State private var isWriting = false

    private var isStudygroup: Bool { auth.studygroupKinds.contains(course.typeID) }

    var body: some View {
        List(threads.value ?? []) { thread in
            PushLink(value: thread) {
                BlubberThreadRow(thread: thread)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: threads.isLoading,
                         errorMessage: threads.errorMessage,
                         isEmpty: (threads.value ?? []).isEmpty,
                         emptyText: isStudygroup
                            ? "In dieser Gruppe wurde noch nichts geschrieben"
                            : "In dieser Veranstaltung wurde noch nichts geschrieben",
                         emptySymbol: "bubble.left.and.bubble.right",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Blubber")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isWriting = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Beitrag schreiben")
            }
        }
        .sheet(isPresented: $isWriting) {
            NewBlubberThreadView(courses: [course]) { await reload(fresh: true) }
        }
        .refreshable { await reload(fresh: true) }
        .task { if threads.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await threads.load { try await client.blubberThreads(.course(id: course.id)) }
    }
}
