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
        StudGoStack {
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
            NavigationLink(value: message) {
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
/// Stud.IP führt Direktnachrichten, Veranstaltungs- und öffentliche Fäden über
/// dieselbe Ressource — nur unter verschiedenen Pfaden. Hier liegen alle drei
/// beieinander, weil sie für den Lesenden dasselbe sind: Unterhaltungen. Der
/// öffentliche Strom stand bis 1.2.0 im Campus-Reiter; dort suchte ihn
/// niemand, und er lud eine Liste, die mit „Verzeichnis" nichts zu tun hat.
struct BlubberInboxView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    /// Welche Fäden gezeigt werden.
    enum Scope: String, CaseIterable, Identifiable {
        /// Alles Persönliche: Direktnachrichten und die eigenen Kursfäden.
        case mine = "Meine Chats"
        /// Nur die Fäden aus belegten Veranstaltungen.
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
                return "Direktnachrichten und die Fäden deiner Veranstaltungen."
            case .courses:
                return "Nur, was in belegten Veranstaltungen geschrieben wurde."
            case .openStream:
                return "Der offene Strom der ganzen Universität. Alle Angemeldeten können mitlesen."
            }
        }
    }

    @State private var scope: Scope = .mine
    @State private var personal = Loadable<[BlubberThread]>()
    @State private var openStream = Loadable<[BlubberThread]>()
    @State private var search = ""
    @State private var isWriting = false
    /// Erst beim Öffnen des Verfassen-Blatts geholt: Für die Liste selbst
    /// wird die Veranstaltungsliste nicht gebraucht.
    @State private var courses: [Course] = []

    private var current: Loadable<[BlubberThread]> {
        scope == .openStream ? openStream : personal
    }

    private var filtered: [BlubberThread] {
        var all = current.value ?? []
        if scope == .courses { all = all.filter { $0.context == .course } }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    /// Fäden mit Neuigkeiten zuerst — sonst rutscht eine frische Antwort
    /// unter zwanzig stille Kursfäden.
    private var grouped: [(title: String, threads: [BlubberThread])] {
        let fresh = filtered.filter(\.hasNews)
        let rest = filtered.filter { !$0.hasNews }
        var sections: [(String, [BlubberThread])] = []
        if !fresh.isEmpty { sections.append(("Neu", fresh)) }
        if !rest.isEmpty { sections.append((fresh.isEmpty ? "Unterhaltungen" : "Älter", rest)) }
        return sections.map { (title: $0.0, threads: $0.1) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.title) { group in
                SwiftUI.Section {
                    ForEach(group.threads) { thread in
                        NavigationLink(value: thread) {
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
        let source = thread.context == .privateChat ? (thread.authorName ?? thread.name) : thread.name
        let parts = source.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                InitialsBadge(initials: initials, size: 38)
                if thread.hasNews {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.name)
                    .font(thread.hasNews ? .subheadline.bold() : .subheadline)
                    .lineLimit(1)

                Text(thread.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Chip(text: thread.context.label,
                         symbol: thread.context.symbol,
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

    /// Wie viele Beiträge auf einmal geholt werden.
    private let pageSize = 60

    private var canSend: Bool {
        thread.isCommentable
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if thread.isCommentable {
                Divider()
                composer
            }
        }
        .navigationTitle(thread.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if comments.value == nil { await reload(fresh: false) } }
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
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                StateOverlay(isLoading: comments.isLoading,
                             errorMessage: comments.errorMessage,
                             isEmpty: (comments.value ?? []).isEmpty && thread.preview.isEmpty,
                             emptyText: "Noch keine Beiträge",
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
        if !thread.preview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: thread.context.symbol).font(.caption2)
                    Text(thread.authorName ?? thread.context.label)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if let created = thread.createdAt {
                        Text(Format.listDate(created))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(Tint.color(thread.tintSeed))

                FormattedText(raw: thread.content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(Tint.surface(thread.tintSeed))
        }
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

    /// Holt die **jüngste** Seite des Verlaufs.
    ///
    /// Ohne `sort` gibt Stud.IP die *ältesten* Beiträge heraus
    /// (`CommentsByThreadIndex` sortiert `ORDER BY mkdate` und schneidet
    /// vorne ab). In einer laufenden Unterhaltung stand deshalb der Anfang
    /// von vor Monaten im Bild, während die letzten Antworten gar nicht
    /// geladen wurden — der Chat wirkte leer oder eingefroren.
    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        // Ohne `Loadable.load`, weil neben der Liste noch `hasOlder` aus
        // derselben Antwort kommt. Die Regel bleibt dieselbe: Ein
        // fehlgeschlagenes Nachladen lässt den bisherigen Verlauf stehen.
        if comments.value == nil { comments.isLoading = true }
        do {
            let page = try await client.blubberComments(threadID: thread.id, limit: pageSize)
            comments.value = page.comments
            comments.errorMessage = nil
            hasOlder = page.hasOlder
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
