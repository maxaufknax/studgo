import SwiftUI

struct MessagesView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    enum Box: String, CaseIterable, Identifiable {
        case inbox = "Posteingang"
        case outbox = "Gesendet"
        var id: String { rawValue }
    }

    @State private var box: Box = .inbox
    @State private var inbox = Loadable<[Message]>()
    @State private var outbox = Loadable<[Message]>()
    @State private var search = ""
    @State private var isComposing = false

    private var current: Loadable<[Message]> { box == .inbox ? inbox : outbox }
    private var isOutgoing: Bool { box == .outbox }

    private var filtered: [Message] {
        let all = current.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.subject.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
                || ($0.counterpart(outgoing: isOutgoing)?
                    .localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedHeader(title: "Postfach",
                                options: Box.allCases,
                                selection: $box) { $0.rawValue }

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
                                 emptyText: search.isEmpty ? "Keine Nachrichten" : "Nichts gefunden",
                                 emptySymbol: search.isEmpty ? "envelope" : "magnifyingglass",
                                 retry: { Task { await reload(fresh: true) } })
                }
            }
            .searchable(text: $search, prompt: "Nachrichten durchsuchen")
            .navigationDestination(for: Message.self) { message in
                MessageDetailView(message: message, outgoing: isOutgoing) {
                    await reload(fresh: true)
                }
            }
            .navigationTitle("Nachrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        }
    }

    // MARK: - Laden

    private func reloadIfNeeded() async {
        guard current.value == nil else { return }
        await reload(fresh: false)
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        switch box {
        case .inbox:
            await inbox.load { try await client.inbox(for: user.id) }
            auth.noteUnread((inbox.value ?? []).filter { !$0.isRead }.count)
        case .outbox:
            await outbox.load { try await client.outbox(for: user.id) }
        }
    }

    private func setRead(_ message: Message, to read: Bool) async {
        try? await auth.client.markMessage(message.id, read: read)
        await reload(fresh: true)
    }
}

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
    var outgoing = false
    var onChange: (() async -> Void)?

    @Environment(AuthStore.self) private var auth
    @State private var isReplying = false
    @State private var didMarkRead = false

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

                Text(message.preview)
                    .font(.body)
                    .textSelection(.enabled)
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
            ComposeMessageView(replyTo: message) { await onChange?() }
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
        await onChange?()
    }
}

extension Message: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
