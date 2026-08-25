import SwiftUI

/// Was man mit einer Person tun kann, an einer Stelle.
///
/// Vorher führte jeder Tipp auf einen Namen direkt ins Nachrichtenfenster —
/// Kontakt aufnehmen oder eine Sprechstunde buchen war von dort aus gar nicht
/// erreichbar. Dieses Blatt sammelt die Möglichkeiten und zeigt nur die, die
/// es für diese Person auch wirklich gibt.
struct PersonSheet: View {
    let personID: String
    let name: String
    var subtitle: String?
    /// Steht schon fest, ob die Person im Adressbuch ist? Sonst wird es
    /// nachgeschlagen.
    var isContact: Bool?

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var isComposing = false
    @State private var contactState: Bool?
    @State private var isWorking = false
    @State private var message: String?

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        InitialsBadge(initials: initials, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.headline)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button {
                        isComposing = true
                    } label: {
                        RowLabel(symbol: "square.and.pencil", title: "Nachricht schreiben")
                    }

                    NavigationLink {
                        ConsultationsView(personID: personID, personName: name)
                    } label: {
                        RowLabel(symbol: "clock.badge.checkmark",
                                 title: "Sprechstunde",
                                 subtitle: "Termine ansehen und buchen")
                    }

                    Button {
                        Task { await toggleContact() }
                    } label: {
                        RowLabel(symbol: (contactState ?? false) ? "person.badge.minus" : "person.badge.plus",
                                 title: (contactState ?? false)
                                    ? "Aus Kontakten entfernen"
                                    : "Zu Kontakten hinzufügen")
                    }
                    .disabled(isWorking || personID == auth.currentUserID)
                } footer: {
                    if let message {
                        Text(message).font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $isComposing) {
                ComposeMessageView(presetRecipientID: personID)
            }
            .task { await determineContactState() }
        }
        .presentationDetents([.medium, .large])
    }

    private func determineContactState() async {
        if let isContact { contactState = isContact; return }
        guard contactState == nil, let me = auth.currentUserID else { return }
        let client = auth.client
        guard let list = try? await client.contacts(for: me) else { return }
        contactState = list.contains { $0.id == personID }
    }

    private func toggleContact() async {
        guard let me = auth.currentUserID else { return }
        isWorking = true
        message = nil
        let wasContact = contactState ?? false
        do {
            if wasContact {
                try await auth.client.removeContact(personID, for: me)
            } else {
                try await auth.client.addContact(personID, for: me)
            }
            contactState = !wasContact
            message = wasContact ? "Aus den Kontakten entfernt." : "Zu den Kontakten hinzugefügt."
        } catch {
            message = error.localizedDescription
        }
        isWorking = false
    }
}

// MARK: - Personensuche

/// Personen im ganzen Stud.IP finden.
///
/// `/v1/users` verlangt `filter[search]` mit **mindestens drei Zeichen** —
/// darunter antwortet der Server gar nicht erst, deshalb wartet die Ansicht
/// ab, statt in einen Fehler zu laufen.
struct PersonSearchView: View {
    @Environment(AuthStore.self) private var auth

    @State private var term = ""
    @State private var results = Loadable<[StudIPUser]>()
    @State private var selected: StudIPUser?

    private var isTooShort: Bool {
        term.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
    }

    var body: some View {
        List {
            if let found = results.value {
                if found.isEmpty {
                    Text("Niemanden gefunden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(found) { person in
                        Button {
                            selected = person
                        } label: {
                            HStack(spacing: 12) {
                                InitialsBadge(initials: person.initials, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.formattedName).foregroundStyle(.primary)
                                    Text("@\(person.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if results.isLoading {
                ProgressView()
            } else if results.value == nil {
                ContentUnavailableView("Personen finden",
                                       systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("Mindestens drei Zeichen eingeben und die Eingabetaste drücken."))
            } else if let message = results.errorMessage {
                ContentUnavailableView {
                    Label("Suche fehlgeschlagen", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            }
        }
        .searchable(text: $term, prompt: "Name oder Kennung")
        .onSubmit(of: .search) { Task { await search() } }
        .navigationTitle("Personensuche")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { person in
            PersonSheet(personID: person.id,
                        name: person.formattedName,
                        subtitle: "@\(person.username)")
        }
    }

    private func search() async {
        guard !isTooShort else { return }
        let client = auth.client
        let query = term
        await results.load { try await client.searchUsers(query) }
    }
}

// MARK: - Studiengruppen

/// Studiengruppen, die Stud.IP vorschlägt.
///
/// Die Auswahl entsteht daraus, in welchen Gruppen Leute aus den eigenen
/// Veranstaltungen sind — es ist also ein echter Vorschlag, keine Liste
/// aller Gruppen. Beitreten geht wie bei jeder Veranstaltung nur über die
/// Weboberfläche.
struct StudygroupsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var groups = Loadable<[Course]>()

    var body: some View {
        List {
            Section {
                ForEach(groups.value ?? []) { group in
                    NavigationLink(value: group) {
                        CourseRow(course: group, typeName: auth.courseTypeName(group.typeID))
                    }
                }
            } footer: {
                if !(groups.value ?? []).isEmpty {
                    Text("Vorgeschlagen, weil Leute aus deinen Veranstaltungen dabei sind. Beitreten läuft über die Stud.IP-Weboberfläche.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: groups.isLoading,
                         errorMessage: groups.errorMessage,
                         isEmpty: (groups.value ?? []).isEmpty,
                         emptyText: "Keine Vorschläge",
                         emptySymbol: "person.3",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Studiengruppen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if groups.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await groups.load { try await client.studygroupProposals() }
    }
}

// MARK: - Sprechstunden

/// Die Sprechstundenblöcke einer Person und ihre buchbaren Termine.
struct ConsultationsView: View {
    let personID: String
    let personName: String

    @Environment(AuthStore.self) private var auth

    @State private var blocks = Loadable<[ConsultationBlock]>()
    @State private var slotsByBlock: [String: [ConsultationSlot]] = [:]
    @State private var expanded: String?
    @State private var booking: ConsultationSlot?

    var body: some View {
        List {
            ForEach(blocks.value ?? []) { block in
                Section {
                    Button {
                        Task { await toggle(block) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(blockTitle(block))
                                    .font(.subheadline.weight(.medium))
                                if let room = block.room {
                                    Text(room).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: expanded == block.id ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    if expanded == block.id {
                        slotRows(for: block)
                    }
                } footer: {
                    if let note = block.note, expanded == block.id {
                        Text(note)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: blocks.isLoading,
                         errorMessage: blocks.errorMessage,
                         isEmpty: (blocks.value ?? []).isEmpty,
                         emptyText: "Keine Sprechstunden eingetragen",
                         emptySymbol: "clock.badge.questionmark",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Sprechstunde")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $booking) { slot in
            ConsultationBookingSheet(slot: slot, personName: personName) {
                await refreshSlots()
            }
        }
        .refreshable { await reload(fresh: true) }
        .task { if blocks.value == nil { await reload(fresh: false) } }
    }

    @ViewBuilder
    private func slotRows(for block: ConsultationBlock) -> some View {
        let slots = slotsByBlock[block.id]
        if let slots {
            if slots.isEmpty {
                Text("Keine Termine in diesem Block.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(slots) { slot in
                    Button {
                        booking = slot
                    } label: {
                        HStack {
                            Text(slot.timeLabel)
                                .font(.callout)
                                .monospacedDigit()
                            Spacer(minLength: 8)
                            Chip(text: slot.statusLabel,
                                 color: slot.isBookable && !slot.isPast ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!slot.isBookable || slot.isPast)
                }
            }
        } else {
            HStack { ProgressView(); Text("Termine werden geladen…").font(.caption) }
        }
    }

    private func blockTitle(_ block: ConsultationBlock) -> String {
        guard let start = block.start else { return "Sprechstunde" }
        guard let end = block.end else { return Format.eventTime(start) }
        return "\(Format.dayShort(start)) · \(Format.timeRange(start, end))"
    }

    // MARK: - Laden

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        slotsByBlock = [:]
        await blocks.load { try await client.consultationBlocks(userID: personID) }
    }

    private func toggle(_ block: ConsultationBlock) async {
        if expanded == block.id {
            expanded = nil
            return
        }
        expanded = block.id
        guard slotsByBlock[block.id] == nil else { return }
        let client = auth.client
        slotsByBlock[block.id] = (try? await client.consultationSlots(blockID: block.id)) ?? []
    }

    /// Nach einer Buchung ist der Termin nicht mehr frei — die Liste muss
    /// wirklich vom Server kommen, nicht aus dem Zwischenspeicher.
    private func refreshSlots() async {
        guard let id = expanded else { return }
        let client = auth.freshClient
        slotsByBlock[id] = (try? await client.consultationSlots(blockID: id)) ?? []
    }
}

/// Buchungsblatt für einen Sprechstundentermin.
struct ConsultationBookingSheet: View {
    let slot: ConsultationSlot
    let personName: String
    var onBooked: (() async -> Void)?

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didBook = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Bei", value: personName)
                    LabeledContent("Zeit", value: slot.timeLabel)
                    if let start = slot.start {
                        LabeledContent("Tag", value: Format.dayShort(start))
                    }
                }

                Section {
                    TextField("Worum geht es?", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Anliegen")
                } footer: {
                    Text("Manche Sprechstunden verlangen eine Angabe. Ein Stichwort genügt meist.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await book() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                            } else {
                                Text(didBook ? "Gebucht" : "Verbindlich buchen")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSending || didBook)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Termin buchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func book() async {
        guard let me = auth.currentUserID else { return }
        isSending = true
        errorMessage = nil
        do {
            try await auth.client.bookConsultation(slotID: slot.id, userID: me, reason: reason)
            didBook = true
            await onBooked?()
            dismiss()
        } catch {
            // 409 heißt: In der Zwischenzeit hat jemand anders gebucht.
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - Neuen Blubber-Faden schreiben

/// Einen Faden aufmachen — öffentlich oder in einer Veranstaltung.
struct NewBlubberThreadView: View {
    /// Zur Auswahl stehende Veranstaltungen. Aus einer Veranstaltung heraus
    /// steht hier genau eine, und die ist dann auch vorbelegt.
    var courses: [Course] = []
    var onPosted: (() async -> Void)?

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var courseID: String?
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// Wird die Ansicht aus genau einer Veranstaltung heraus geöffnet, ist der
    /// öffentliche Strom fast sicher nicht gemeint — dann steht sie vorne.
    private var preselected: String? {
        courses.count == 1 ? courses[0].id : nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Wohin", selection: $courseID) {
                        Text("Öffentlicher Strom").tag(String?.none)
                        ForEach(courses) { course in
                            Text(course.shortTitle).tag(String?.some(course.id))
                        }
                    }
                } footer: {
                    Text(courseID == nil
                         ? "Alle an der Universität können den Beitrag lesen."
                         : "Nur Teilnehmende dieser Veranstaltung sehen den Beitrag.")
                }

                Section("Beitrag") {
                    TextField("Was gibt es Neues?", text: $content, axis: .vertical)
                        .lineLimit(4...12)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Neuer Faden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { Task { await post() } }
                        .disabled(!canSend)
                }
            }
            .task {
                if courseID == nil { courseID = preselected }
            }
        }
    }

    private func post() async {
        isSending = true
        errorMessage = nil
        do {
            try await auth.client.createBlubberThread(
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                courseID: courseID)
            await onPosted?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
