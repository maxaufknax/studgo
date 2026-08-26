import SwiftUI

/// Das Postfach vereint, was Stud.IP getrennt führt: die klassischen
/// **Nachrichten** (`/v1/users/{id}/inbox`) und die **Blubber-Fäden**
/// (`/v1/blubber-threads`), also Direktnachrichten und Kursunterhaltungen.
/// Beides sind eingehende Mitteilungen; sie in zwei Reitern derselben
/// Ansicht zu führen, entspricht der Erwartung an ein Postfach eher als
/// zwei Menüpunkte an verschiedenen Enden der App.
struct PostfachView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    enum Section: String, CaseIterable, Identifiable {
        case messages = "Nachrichten"
        case chats = "Chats"
        var id: String { rawValue }
    }

    @State private var section: Section = .messages

    var body: some View {
        StudGoStack(user: user) {
            VStack(spacing: 0) {
                SegmentedHeader(title: "Bereich",
                                options: Section.allCases,
                                selection: $section) { $0.rawValue }

                switch section {
                case .messages: MailboxView(user: user)
                case .chats: BlubberInboxView(user: user)
                }
            }
            .navigationTitle("Postfach")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Nachrichten

/// Posteingang und Postausgang. Ohne eigenen `NavigationStack` — der kommt
/// vom `PostfachView`, sonst läge ein Stack im anderen und die Titelzeile
/// erschiene doppelt.
struct MailboxView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    enum Box: String, CaseIterable, Identifiable {
        case inbox = "Posteingang"
        case unread = "Ungelesen"
        case outbox = "Gesendet"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .inbox: return "tray"
            case .unread: return "circle.badge.exclamationmark"
            case .outbox: return "paperplane"
            }
        }
    }

    @State private var box: Box = .inbox
    @State private var inbox = Loadable<[Message]>()
    @State private var outbox = Loadable<[Message]>()
    @State private var search = ""
    @State private var isComposing = false

    private var isOutgoing: Bool { box == .outbox }
    private var current: Loadable<[Message]> { isOutgoing ? outbox : inbox }

    private var filtered: [Message] {
        var all = current.value ?? []
        if box == .unread { all = all.filter { !$0.isRead } }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.subject.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
                || ($0.counterpart(outgoing: isOutgoing)?
                    .localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        List(filtered) { message in
            PushLink(value: message) {
                MessageRow(message: message, outgoing: isOutgoing)
            }
            .swipeActions(edge: .leading) {
                if !isOutgoing {
                    Button {
                        Task { await setRead(message, to: !message.isRead) }
                    } label: {
                        Label(message.isRead ? "Ungelesen" : "Gelesen",
                              systemImage: message.isRead ? "envelope.badge" : "envelope.open")
                    }
                    .tint(.accentColor)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: current.isLoading,
                         errorMessage: current.errorMessage,
                         isEmpty: filtered.isEmpty,
                         emptyText: emptyText,
                         emptySymbol: search.isEmpty ? box.symbol : "magnifyingglass",
                         retry: { Task { await reload(fresh: true) } })
        }
        .searchable(text: $search, prompt: "Nachrichten durchsuchen")
        // Kein eigenes `navigationDestination(for: Message.self)`: Das meldet
        // `studGoDestinations()` an der Stapelwurzel an. Zwei Anmeldungen
        // desselben Typs im selben Stapel — hier und in „Heute" — öffneten
        // sonst die jeweils falsche Seite.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Postfach", selection: $box) {
                        ForEach(Box.allCases) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                } label: {
                    Label(box.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.footnote)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isComposing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Neue Nachricht")
            }
        }
        .sheet(isPresented: $isComposing) {
            ComposeMessageView { await reload(fresh: true) }
        }
        .refreshable { await reload(fresh: true) }
        .task(id: box) { await reloadIfNeeded() }
        // Die Detailseite meldet über den Store, dass sie etwas verändert hat
        // — gelesen markiert, geantwortet. Ohne das bliebe der blaue Punkt an
        // einer längst geöffneten Nachricht stehen.
        .onChange(of: auth.mailboxRevision) { Task { await reload(fresh: true) } }
    }

    private var emptyText: String {
        if !search.isEmpty { return "Nichts gefunden" }
        switch box {
        case .unread: return "Alles gelesen"
        case .outbox: return "Nichts gesendet"
        case .inbox: return "Keine Nachrichten"
        }
    }

    // MARK: - Laden

    private func reloadIfNeeded() async {
        guard current.value == nil else { return }
        await reload(fresh: false)
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        if isOutgoing {
            await outbox.load { try await client.outbox(for: user.id) }
        } else {
            await inbox.load { try await client.inbox(for: user.id) }
            auth.noteUnread((inbox.value ?? []).filter { !$0.isRead }.count)
        }
    }

    private func setRead(_ message: Message, to read: Bool) async {
        try? await auth.client.markMessage(message.id, read: read)
        await reload(fresh: true)
    }
}

// MARK: - Chats (Blubber)

/// Blubber als Nachrichtenliste.
///
/// **Wie die Weboberfläche das führt:** `dispatch.php/blubber` zeigt links
/// alle Fäden untereinander — den globalen Strom, die Direktnachrichten und
/// die Ströme der Veranstaltungen und Studiengruppen —, rechts den gewählten
/// Verlauf. Genau diese eine Liste steht hier. Bis 1.3.0 fehlte darin der
/// **globale Blubber**, obwohl er in der Weboberfläche der erste Eintrag ist:
/// Er trägt `context-type = public` und fiel damit durch dasselbe Sieb, das
/// den öffentlichen Strom aus dem Postfach heraushält.
struct BlubberInboxView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    /// Welche Fäden gezeigt werden.
    enum Scope: String, CaseIterable, Identifiable {
        /// Alles Persönliche: der globale Strom, Direktnachrichten und die
        /// eigenen Kursfäden — die Auswahl der Weboberfläche.
        case mine = "Alle Chats"
        /// Nur die Fäden aus belegten Veranstaltungen und Studiengruppen.
        case courses = "Veranstaltungen"
        /// Der Strom der ganzen Universität.
        case openStream = "Öffentlich"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .mine: return "bubble.left.and.bubble.right"
            case .courses: return "books.vertical"
            case .openStream: return "globe.europe.africa"
            }
        }

        var emptyText: String {
            switch self {
            case .mine: return "Keine Unterhaltungen"
            case .courses: return "In deinen Veranstaltungen ist es still"
            case .openStream: return "Im öffentlichen Strom ist es still"
            }
        }

        var hint: String {
            switch self {
            case .mine:
                return "Der globale Blubber, deine Direktnachrichten und die Ströme deiner Veranstaltungen und Studiengruppen — dieselbe Auswahl wie unter „Blubber“ in Stud.IP."
            case .courses:
                return "Nur, was in belegten Veranstaltungen und Studiengruppen geschrieben wurde."
            case .openStream:
                return "Der offene Strom der ganzen Universität. Alle Angemeldeten können mitlesen."
            }
        }
    }

    @State private var scope: Scope = .mine
    @State private var personal = Loadable<[BlubberThread]>()
    @State private var openStream = Loadable<[BlubberThread]>()
    /// Der globale Strom wird eigens geholt: Er soll auch dann in der Liste
    /// stehen, wenn die Sammelroute an einem verwaisten Faden scheitert.
    @State private var global: BlubberThread?
    @State private var search = ""
    @State private var isWriting = false
    /// Erst beim Öffnen des Verfassen-Blatts geholt: Für die Liste selbst
    /// wird die Veranstaltungsliste nicht gebraucht.
    @State private var courses: [Course] = []

    private var current: Loadable<[BlubberThread]> {
        scope == .openStream ? openStream : personal
    }

    /// Alle Fäden des Bereichs — mit dem globalen Strom vorn, falls er nicht
    /// ohnehin schon aus der Sammelroute kam.
    private var all: [BlubberThread] {
        var threads = current.value ?? []
        if scope != .courses, let global, !threads.contains(where: { $0.isGlobal }) {
            threads.insert(global, at: 0)
        }
        return threads
    }

    private var filtered: [BlubberThread] {
        var threads = all
        if scope == .courses { threads = threads.filter { $0.context == .course } }
        guard !search.isEmpty else { return threads }
        return threads.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    /// Der globale Strom steht ganz oben — wie in der Weboberfläche. Darunter
    /// Fäden mit Neuigkeiten, sonst rutscht eine frische Antwort unter zwanzig
    /// stille Kursfäden. Und darunter, in „Alle Chats", nach Art getrennt:
    /// Direktnachrichten, Kursfäden und der Rest.
    private var grouped: [(title: String, threads: [BlubberThread])] {
        let pinned = filtered.filter(\.isGlobal)
        let others = filtered.filter { !$0.isGlobal }
        let fresh = others.filter(\.hasNews)
        let rest = others.filter { !$0.hasNews }

        var sections: [(String, [BlubberThread])] = []
        if !pinned.isEmpty { sections.append(("Universität", pinned)) }
        if !fresh.isEmpty { sections.append(("Neu", fresh)) }

        switch scope {
        case .mine:
            let direct = rest.filter { $0.context == .privateChat }
            let courseThreads = rest.filter { $0.context == .course }
            let other = rest.filter { $0.context != .privateChat && $0.context != .course }
            if !direct.isEmpty { sections.append(("Direktnachrichten", direct)) }
            if !courseThreads.isEmpty { sections.append(("Aus Veranstaltungen", courseThreads)) }
            if !other.isEmpty { sections.append(("Weitere", other)) }
        case .courses, .openStream:
            if !rest.isEmpty {
                sections.append((fresh.isEmpty ? "Unterhaltungen" : "Älter", rest))
            }
        }
        return sections.map { (title: $0.0, threads: $0.1) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.title) { group in
                SwiftUI.Section {
                    ForEach(group.threads) { thread in
                        PushLink(value: thread) {
                            BlubberThreadRow(thread: thread)
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if group.title == grouped.last?.title {
                        Text(scope.hint)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: current.isLoading,
                         errorMessage: current.errorMessage,
                         isEmpty: filtered.isEmpty,
                         emptyText: search.isEmpty ? scope.emptyText : "Nichts gefunden",
                         emptySymbol: search.isEmpty ? scope.symbol : "magnifyingglass",
                         retry: { Task { await reload(fresh: true) } })
        }
        .searchable(text: $search, prompt: "Unterhaltungen durchsuchen")
        // Der öffentliche Strom wird serverseitig durchsucht: Er kann Tausende
        // Fäden führen, von denen die App nur einen Ausschnitt geladen hat.
        .onSubmit(of: .search) {
            if scope == .openStream { Task { await reload(fresh: true) } }
        }
        // Kein eigenes `navigationDestination(for: BlubberThread.self)` —
        // das meldet `studGoDestinations()` an der Stapelwurzel an.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Bereich", selection: $scope) {
                        ForEach(Scope.allCases) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                } label: {
                    Label(scope.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.footnote)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isWriting = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Neuen Faden schreiben")
            }
        }
        .sheet(isPresented: $isWriting) {
            NewBlubberThreadView(courses: courses) { await reload(fresh: true) }
        }
        .task(id: isWriting) { await loadCoursesIfNeeded() }
        .refreshable { await reload(fresh: true) }
        .task(id: scope) { if current.value == nil { await reload(fresh: false) } }
    }

    /// Ohne die Veranstaltungsliste stünde im Verfassen-Blatt nur
    /// „Öffentlicher Strom" zur Wahl — in eine Veranstaltung ließe sich von
    /// hier aus gar nichts schreiben.
    private func loadCoursesIfNeeded() async {
        guard isWriting, courses.isEmpty else { return }
        courses = (try? await auth.client.courses(for: user.id)) ?? []
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        let userID = user.id
        switch scope {
        case .mine, .courses:
            await personal.load { try await client.personalBlubberThreads(for: userID) }
            // Nacheinander statt nebenläufig: `StudIPClient` trägt zwei
            // Closures (Tokenbeschaffung, 401-Meldung) und ist damit nicht
            // `Sendable` — ein `async let` schöbe ihn über eine Aufgabengrenze.
            if let found = await client.globalBlubberThread() { global = found }
        case .openStream:
            let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            await openStream.load {
                try await client.blubberThreads(.publicStream,
                                                search: term.isEmpty ? nil : term,
                                                limit: 80)
            }
        }
    }
}

/// Eine Unterhaltung in der Liste.
struct BlubberThreadRow: View {
    let thread: BlubberThread

    private var initials: String {
        let source = thread.context == .privateChat
            ? (thread.authorName ?? thread.displayName)
            : thread.displayName
        let parts = source.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }

    /// Der globale Strom trägt keinen Aufschlag — dort stünde sonst eine
    /// leere Zeile, wo die Weboberfläche „Was gibt es Neues?" zeigt.
    private var subtitle: String {
        let preview = thread.preview
        if !preview.isEmpty { return preview }
        return thread.isGlobal
            ? "Der offene Strom der ganzen Universität"
            : "Unterhaltung öffnen"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                if thread.isGlobal {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.accentColor))
                } else {
                    InitialsBadge(initials: initials, size: 38)
                }
                if thread.hasNews {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.displayName)
                    .font(thread.hasNews ? .subheadline.bold() : .subheadline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Chip(text: thread.isGlobal ? "Universität" : thread.context.label,
                         symbol: thread.isGlobal ? "globe.europe.africa.fill" : thread.context.symbol,
                         color: Tint.color(thread.tintSeed))
                    if thread.unseenComments > 0 {
                        Chip(text: "\(thread.unseenComments) neu", color: .accentColor)
                    }
                }
            }

            Spacer(minLength: 4)

            if let activity = thread.latestActivity {
                Text(Format.listDate(activity))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Ein Faden als Verlauf — Beiträge von unten nach oben, Eingabefeld am Fuß.
///
/// **Was hier 1.3.0 nicht konnte:** In jedem Chat stand „Noch keine
/// Beiträge". Der Grund liegt im Aufbau von Stud.IP: Ein Faden trägt einen
/// eigenen Text und darunter die Beiträge — bei Direktnachrichten und beim
/// globalen Strom ist der Text aber **leer**, der ganze Verlauf steckt in den
/// Beiträgen. Kam von der Kommentarroute nichts, blieb der Bildschirm leer,
/// ohne dass irgendwo stand, woran es lag.
///
/// Jetzt holt `StudIPClient.blubberConversation(id:)` den Verlauf über drei
/// verschiedene Wege und meldet zurück, welcher getragen hat. Bleibt es
/// wirklich bei nichts, steht die Spur unter „Warum ist hier nichts?" —
/// zusammen mit dem Knopf, der denselben Faden in Stud.IP öffnet.
struct BlubberThreadView: View {
    let thread: BlubberThread
    @Environment(AuthStore.self) private var auth

    @State private var comments = Loadable<[BlubberComment]>()
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?
    /// Steht am Anfang des Verlaufs noch Älteres?
    @State private var hasOlder = false
    @State private var isLoadingOlder = false
    /// Der vollständig nachgeladene Faden. Die Liste reicht den Faden ohne
    /// gesicherten Anfangsbeitrag herein — die Einzelroute holt ihn nach.
    @State private var resolved: BlubberThread?
    /// Welche Route was geantwortet hat. Steht nur im Bild, wenn nichts kam.
    @State private var trail: [String] = []
    @State private var showsTrail = false
    @State private var webTarget: WebTarget?

    /// Wie viele Beiträge auf einmal geholt werden.
    private let pageSize = 60

    /// Der Faden, wie er angezeigt wird: der nachgeladene, sobald er da ist,
    /// sonst der aus der Liste.
    private var shown: BlubberThread { resolved ?? thread }

    /// Wirklich leer — weder Aufschlag noch ein einziger Beitrag.
    private var isBlank: Bool {
        (comments.value ?? []).isEmpty && shown.preview.isEmpty
    }

    private var canSend: Bool {
        shown.isCommentable
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if shown.isCommentable {
                Divider()
                composer
            }
        }
        .navigationTitle(shown.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    webTarget = WebTarget(url: WebLinks.blubber(thread: thread.id))
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("In Stud.IP öffnen")
            }
        }
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url)
        }
        .task { await load() }
    }

    /// Anfangsbeitrag und Verlauf in **einem** Ablauf holen. Solange etwas
    /// unterwegs ist, trägt `comments.isLoading` den Spinner; „Noch keine
    /// Beiträge" erscheint erst, wenn alle Wege durch sind und wirklich
    /// nichts da ist.
    private func load() async {
        guard comments.value == nil else { return }
        await reload(fresh: false)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hasOlder { olderButton }
                    opener

                    ForEach(comments.value ?? []) { comment in
                        BlubberCommentBubble(comment: comment,
                                             isOwn: comment.authorID == auth.currentUserID)
                            .id(comment.id)
                    }

                    if isBlank && !comments.isLoading { blankNote }
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                // Der Leerzustand wird hier bewusst **nicht** überlagert: Er
                // steht als Karte im Verlauf, damit die Spur darunter passt
                // und der Verweis nach Stud.IP antippbar bleibt.
                StateOverlay(isLoading: comments.isLoading,
                             errorMessage: comments.errorMessage,
                             isEmpty: isBlank && comments.value == nil,
                             emptyText: "Wird geladen…",
                             emptySymbol: "bubble.left",
                             retry: { Task { await reload(fresh: true) } })
            }
            .refreshable { await reload(fresh: true) }
            // Beim Öffnen und nach jedem neuen Beitrag ans Ende springen —
            // dort steht, worauf man geantwortet haben will.
            .onChange(of: (comments.value ?? []).last?.id) {
                guard !isLoadingOlder, let last = comments.value?.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    /// Der Verlauf wird von hinten geladen; wer weiter zurück will, holt sich
    /// die vorherige Seite.
    private var olderButton: some View {
        Button {
            Task { await loadOlder() }
        } label: {
            HStack(spacing: 6) {
                if isLoadingOlder {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle")
                }
                Text(isLoadingOlder ? "Wird geladen…" : "Ältere Beiträge laden")
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoadingOlder)
    }

    /// Der Beitrag, mit dem der Faden aufgemacht wurde.
    @ViewBuilder
    private var opener: some View {
        if !shown.preview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: shown.context.symbol).font(.caption2)
                    Text(shown.authorName ?? shown.context.label)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if let created = shown.createdAt {
                        Text(Format.listDate(created))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(Tint.color(shown.tintSeed))

                FormattedText(raw: shown.content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(Tint.surface(shown.tintSeed))
        }
    }

    /// Steht wirklich nichts da, dann bitte mit Begründung.
    private var blankNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Noch keine Beiträge", systemImage: "bubble.left")
                .font(.subheadline.weight(.semibold))

            Text(shown.isCommentable
                 ? "Schreib den ersten Beitrag — das Feld unten gehört dazu."
                 : "In diesem Faden darfst du nicht schreiben.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                webTarget = WebTarget(url: WebLinks.blubber(thread: thread.id))
            } label: {
                Label("In Stud.IP ansehen", systemImage: "safari")
                    .font(.footnote.weight(.medium))
            }

            if !trail.isEmpty {
                DisclosureGroup("Warum ist hier nichts?", isExpanded: $showsTrail) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(trail, id: \.self) { line in
                            Text("• " + line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
                TextField("Beitrag schreiben…", text: $draft, axis: .vertical)
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
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                }
                .disabled(!canSend)
                .accessibilityLabel("Absenden")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Laden und Senden

    /// Holt Faden und jüngste Seite des Verlaufs über alle Wege, die es gibt.
    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        // Ohne `Loadable.load`, weil neben der Liste noch `hasOlder` und die
        // Spur aus derselben Antwort kommen. Die Regel bleibt dieselbe: Ein
        // fehlgeschlagenes Nachladen lässt den bisherigen Verlauf stehen.
        if comments.value == nil { comments.isLoading = true }
        do {
            let conversation = try await client.blubberConversation(id: thread.id,
                                                                    limit: pageSize)
            if let full = conversation.thread { resolved = full }
            comments.value = conversation.comments
            comments.errorMessage = nil
            hasOlder = conversation.hasOlder
            trail = conversation.trail
        } catch {
            comments.errorMessage = error.localizedDescription
        }
        comments.isLoading = false
    }

    /// Eine Seite weiter in die Vergangenheit. Die Beiträge werden **vorne**
    /// angehängt, damit der gelesene Teil stehen bleibt.
    private func loadOlder() async {
        guard !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        let known = comments.value ?? []
        guard let page = try? await auth.client.blubberComments(threadID: thread.id,
                                                                limit: pageSize,
                                                                offset: known.count)
        else { return }

        let seen = Set(known.map(\.id))
        let fresh = page.comments.filter { !seen.contains($0.id) }
        comments.value = fresh + known
        hasOlder = page.hasOlder && !fresh.isEmpty
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        sendError = nil
        do {
            try await auth.client.postBlubberComment(threadID: thread.id, content: text)
            draft = ""
            await reload(fresh: true)
        } catch {
            sendError = error.localizedDescription
        }
        isSending = false
    }
}

/// Ein einzelner Beitrag. Eigene Beiträge rechts und in der Akzentfarbe —
/// die Zuordnung ist damit ohne Namenszeile ablesbar.
struct BlubberCommentBubble: View {
    let comment: BlubberComment
    var isOwn = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn { Spacer(minLength: 40) }

            if !isOwn {
                InitialsBadge(initials: comment.initials, size: 28)
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn, let author = comment.authorName {
                    Text(author)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // `FormattedText` statt `Text`: Ein Blubber-Beitrag kommt als
                // `content-html` und trägt Verweise, Erwähnungen und
                // Betonungen — als Klartext standen dort die Tags.
                FormattedText(raw: comment.content, font: .callout)
                    .foregroundStyle(isOwn ? Color.white : Color.primary)
                    .tint(isOwn ? Color.white : Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isOwn ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                    )

                if let created = comment.createdAt {
                    Text(Format.listDate(created))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isOwn { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Zeile und Detailansicht einer Nachricht

struct MessageRow: View {
    let message: Message
    /// Im Postausgang steht als Absender die eigene Person — dort gehört
    /// stattdessen hin, an wen die Nachricht ging.
    var outgoing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isRead || outgoing ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if message.isUrgent {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(message.subject)
                        .font(message.isRead || outgoing ? .subheadline : .subheadline.bold())
                        .lineLimit(1)
                }
                if let person = message.counterpart(outgoing: outgoing) {
                    Text(outgoing ? "An: \(person)" : person)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(message.preview)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if let sentAt = message.sentAt {
                Text(Format.listDate(sentAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.isRead || outgoing
                            ? message.subject
                            : "Ungelesen, \(message.subject)")
    }
}

struct MessageDetailView: View {
    let message: Message

    @Environment(AuthStore.self) private var auth
    @State private var isReplying = false
    @State private var didMarkRead = false

    /// Ob die Nachricht von einem selbst stammt, steht am Absender — dafür
    /// braucht es keinen Parameter vom Aufrufer.
    ///
    /// Das ist nicht bloß bequemer: Seit die Detailseite zentral angemeldet
    /// wird (`studGoDestinations`), *kann* der Aufrufer nichts mehr mitgeben.
    private var outgoing: Bool {
        guard let me = auth.currentUserID, let sender = message.senderID else { return false }
        return sender == me
    }

    private var person: String { message.counterpart(outgoing: outgoing) ?? "Unbekannt" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(message.subject).font(.title3.bold())

                HStack(spacing: 10) {
                    InitialsBadge(initials: initials, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outgoing ? "An: \(person)" : person).font(.subheadline)
                        if let sentAt = message.sentAt {
                            Text(sentAt, format: .dateTime.day().month(.wide).year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if message.isUrgent {
                        Chip(text: "Wichtig", symbol: "exclamationmark.circle.fill", color: .orange)
                    }
                }

                // Mehrere Empfänger passen nicht in die Kopfzeile.
                if outgoing && message.recipientNames.count > 1 {
                    Text(message.recipientNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                FormattedText(raw: message.body, font: .body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Nachricht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isReplying = true
                } label: {
                    Label("Antworten", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(message.senderID == nil || outgoing)
            }
        }
        .sheet(isPresented: $isReplying) {
            ComposeMessageView(replyTo: message)
        }
        .task { await markReadIfNeeded() }
    }

    private var initials: String {
        let parts = person.split(separator: " ")
            .prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }

    /// Das Öffnen markiert die Nachricht serverseitig als gelesen — genau
    /// einmal, damit ein erneutes Erscheinen der Ansicht nichts wiederholt.
    private func markReadIfNeeded() async {
        guard !outgoing, !message.isRead, !didMarkRead else { return }
        didMarkRead = true
        try? await auth.client.markMessage(message.id, read: true)
        auth.noteMailboxChanged()
    }
}

extension Message: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
