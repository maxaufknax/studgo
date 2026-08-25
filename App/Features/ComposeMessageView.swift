import SwiftUI

/// Nachricht verfassen — als Neuanlage oder als Antwort auf eine erhaltene.
struct ComposeMessageView: View {
    var replyTo: Message?
    /// Aus der Teilnehmendenliste heraus steht der Empfänger schon fest —
    /// bekannt ist dort aber nur die ID, der Datensatz muss nachgeladen werden.
    var presetRecipientID: String?
    var onSent: (() async -> Void)?

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var recipients: [StudIPUser] = []
    @State private var subject = ""
    @State private var messageText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isPickingRecipient = false

    /// Verhindert, dass ein angefangener Text durch ein Wischen verloren geht.
    private var hasDraft: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        !recipients.isEmpty
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("An") {
                    ForEach(recipients) { person in
                        HStack(spacing: 10) {
                            InitialsBadge(initials: person.initials, size: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(person.formattedName)
                                Text("@\(person.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { recipients.remove(atOffsets: $0) }

                    Button {
                        isPickingRecipient = true
                    } label: {
                        Label("Empfänger hinzufügen", systemImage: "person.badge.plus")
                    }
                }

                Section("Betreff") {
                    TextField("Betreff", text: $subject)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Nachricht") {
                    TextEditor(text: $messageText)
                        .frame(minHeight: 200)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(replyTo == nil ? "Neue Nachricht" : "Antworten")
            .interactiveDismissDisabled(hasDraft)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Senden") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
            .sheet(isPresented: $isPickingRecipient) {
                RecipientPickerView { person in
                    if !recipients.contains(where: { $0.id == person.id }) {
                        recipients.append(person)
                    }
                }
            }
            .task { await prefill() }
        }
    }

    /// Bei einer Antwort stehen Empfänger und Betreff bereits fest; aus der
    /// Teilnehmendenliste heraus zumindest der Empfänger.
    private func prefill() async {
        guard recipients.isEmpty else { return }

        if let replyTo, subject.isEmpty {
            subject = replyTo.subject.hasPrefix("Re:") ? replyTo.subject : "Re: \(replyTo.subject)"
        }

        // In der Liste steht vom Gegenüber nur der Name — für den Versand
        // braucht Stud.IP die Nutzer-Ressource.
        guard let id = presetRecipientID ?? replyTo?.senderID else { return }
        if let user = try? await auth.client.user(id: id) {
            recipients = [user]
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await auth.client.sendMessage(subject: subject,
                                              body: messageText,
                                              to: recipients.map(\.id))
            // Der Store meldet allen Listen, dass sich am Postfach etwas
            // getan hat — unabhängig davon, wer das Blatt geöffnet hat.
            auth.noteMailboxChanged()
            await onSent?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Personensuche über die JSON:API — Stud.IP verlangt mindestens drei Zeichen.
struct RecipientPickerView: View {
    let onSelect: (StudIPUser) -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var results: [StudIPUser] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results) { person in
                Button {
                    onSelect(person)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        InitialsBadge(initials: person.initials, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.formattedName).foregroundStyle(.primary)
                            Text("@\(person.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $term, prompt: "Name oder Kennung")
            .overlay {
                if isSearching {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView("Suche fehlgeschlagen",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if term.count < 3 {
                    ContentUnavailableView("Mindestens drei Zeichen eingeben",
                                           systemImage: "magnifyingglass")
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: term)
                }
            }
            .navigationTitle("Empfänger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .task(id: term) { await search() }
        }
    }

    private func search() async {
        guard term.count >= 3 else {
            results = []
            return
        }
        // Kurz warten, damit nicht jeder Tastenanschlag eine Anfrage auslöst.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await auth.client.searchUsers(term)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}
