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

    private var filtered: [Message] {
        let all = current.value ?? []
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.subject.localizedCaseInsensitiveContains(search)
                || $0.body.localizedCaseInsensitiveContains(search)
                || ($0.senderName?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedHeader(title: "Postfach",
                                options: Box.allCases,
                                selection: $box) { $0.rawValue }

                List(filtered) { message in
                    NavigationLink(value: message) { MessageRow(message: message) }
                }
                .overlay {
                    StateOverlay(isLoading: current.isLoading,
                                 errorMessage: current.errorMessage,
                                 isEmpty: filtered.isEmpty,
                                 emptyText: search.isEmpty ? "Keine Nachrichten" : "Nichts gefunden",
                                 emptySymbol: search.isEmpty ? "envelope" : "magnifyingglass",
                                 retry: { Task { await reload() } })
                }
            }
            .searchable(text: $search, prompt: "Nachrichten durchsuchen")
            .navigationDestination(for: Message.self) { message in
                MessageDetailView(message: message) { await reload() }
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
                ComposeMessageView { await reload() }
            }
            .refreshable { await reload() }
            .task(id: box) { await reloadIfNeeded() }
        }
    }

    private func reloadIfNeeded() async {
        guard current.value == nil else { return }
        await reload()
    }

    private func reload() async {
        let client = auth.client
        switch box {
        case .inbox: await inbox.load { try await client.inbox(for: user.id) }
        case .outbox: await outbox.load { try await client.outbox(for: user.id) }
        }
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.subject)
                    .font(message.isRead ? .body : .body.bold())
                    .lineLimit(1)
                if let sender = message.senderName {
                    Text(sender).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.body.strippingHTML)
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
        .accessibilityLabel(message.isRead ? message.subject : "Ungelesen, \(message.subject)")
    }
}

struct MessageDetailView: View {
    let message: Message
    var onChange: (() async -> Void)?

    @Environment(AuthStore.self) private var auth
    @State private var isReplying = false
    @State private var didMarkRead = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(message.subject).font(.title3.bold())

                HStack(spacing: 10) {
                    InitialsBadge(initials: senderInitials, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.senderName ?? "Unbekannt").font(.subheadline)
                        if let sentAt = message.sentAt {
                            Text(sentAt, format: .dateTime.day().month(.wide).year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Text(message.body.strippingHTML)
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
                .disabled(message.senderID == nil)
            }
        }
        .sheet(isPresented: $isReplying) {
            ComposeMessageView(replyTo: message) { await onChange?() }
        }
        .task { await markReadIfNeeded() }
    }

    private var senderInitials: String {
        let parts = (message.senderName ?? "?").split(separator: " ")
            .prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }

    /// Das Öffnen markiert die Nachricht serverseitig als gelesen — genau
    /// einmal, damit ein erneutes Erscheinen der Ansicht nichts wiederholt.
    private func markReadIfNeeded() async {
        guard !message.isRead, !didMarkRead else { return }
        didMarkRead = true
        try? await auth.client.markMessage(message.id, read: true)
        await onChange?()
    }
}

extension Message: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
