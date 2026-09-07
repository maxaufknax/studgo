import SwiftUI

// MARK: - Was gemeldet werden kann

/// Alles, was die Meldung über einen Inhalt wissen muss.
///
/// Jede Ansicht, die fremde Beiträge zeigt, baut sich einen solchen Wert und
/// hängt ihn per `.moderated(_:)` an die Zeile. Damit liegt die Entscheidung,
/// *was* meldbar ist, bei der Ansicht — und alles Übrige an einer Stelle.
struct ModerationTarget: Equatable, Identifiable {
    let kind: ReportTargetKind
    let contentID: String
    let authorID: String?
    let authorName: String?
    let text: String

    var id: String { "\(kind.rawValue):\(contentID)" }

    /// Blockieren geht nur, wenn bekannt ist, **wen**. Bei Wikiseiten und
    /// Ankündigungen liefert Stud.IP keine Verfasserkennung mit; dort bleibt
    /// die Meldung, der Knopf zum Blockieren verschwindet.
    var canBlock: Bool { authorID?.nilIfEmpty != nil }
}

// MARK: - Der Anhänger für Zeilen und Blasen

extension View {
    /// Macht einen Beitrag meldbar — und verdeckt ihn, wenn er es verdient.
    ///
    /// Drei Zustände, entschieden von `ModerationStore.verdict`:
    /// blockiert (gar nicht anzeigen), gefiltert (verdeckt, aufklappbar),
    /// sichtbar. Dazu kommt in jedem Fall das Kontextmenü mit „Melden" und
    /// „Blockieren".
    func moderated(_ target: ModerationTarget) -> some View {
        modifier(ModerationModifier(target: target))
    }
}

private struct ModerationModifier: ViewModifier {
    let target: ModerationTarget
    @Environment(ModerationStore.self) private var moderation
    @State private var revealed = false
    @State private var sheet: ModerationSheet?

    func body(content: Content) -> some View {
        Group {
            switch moderation.verdict(text: target.text, authorID: target.authorID) {
            case .blocked:
                // Wer blockiert ist, ist weg — sofort und ohne Platzhalter,
                // der noch an die Person erinnert. **Nicht `EmptyView()`:**
                // In einer `List` bleibt daraus je nach Fassung eine Zeile
                // mit Trennstrich stehen. Eine Fläche ohne Höhe, ohne
                // Einrückung und ohne Trenner verschwindet wirklich.
                Color.clear
                    .frame(height: 0)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            case .filtered where !revealed:
                HiddenContentNotice { revealed = true }
            default:
                content
                    .contextMenu {
                        Button {
                            sheet = .report
                        } label: {
                            Label("Beitrag melden", systemImage: "flag")
                        }
                        if target.canBlock {
                            Button(role: .destructive) {
                                sheet = .block
                            } label: {
                                Label("Person blockieren", systemImage: "hand.raised")
                            }
                        }
                    }
            }
        }
        .sheet(item: $sheet) { which in
            ReportSheet(target: target, mode: which == .block ? .block : .report)
        }
    }
}

private enum ModerationSheet: String, Identifiable {
    case report
    case block
    var id: String { rawValue }
}

/// Der Vorhang über einem Beitrag, auf den der Wortfilter angesprochen hat.
struct HiddenContentNotice: View {
    var onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Inhalt verdeckt")
                    .font(.subheadline.weight(.semibold))
                Text("Könnte anstößig sein.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Anzeigen", action: onReveal)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verdeckter Inhalt, könnte anstößig sein")
    }
}

// MARK: - Melden und Blockieren

/// Das Blatt, auf dem gemeldet oder blockiert wird.
///
/// Beides in einem: Der Unterschied ist nur, was oben steht und ob am Ende
/// zusätzlich blockiert wird. Zwei getrennte Blätter hätten denselben Aufbau
/// zweimal — und die Gefahr, dass eines später anders aussieht als das andere.
struct ReportSheet: View {
    let target: ModerationTarget
    let mode: ModerationSheetMode

    /// Von Hand geschrieben, weil der erzeugte Initialisierer wegen der
    /// privaten `@State`-Eigenschaften ebenfalls privat wäre — aufrufbar dann
    /// nur in dieser Datei.
    init(target: ModerationTarget, mode: ModerationSheetMode) {
        self.target = target
        self.mode = mode
    }

    @Environment(ModerationStore.self) private var moderation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var reason: ReportReason = .abuse
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var result: Result?

    private enum Result: Equatable {
        case done
        case mailed
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intro)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Grund") {
                    Picker("Grund", selection: $reason) {
                        ForEach(ReportReason.allCases) { reason in
                            VStack(alignment: .leading) {
                                Text(reason.label)
                                Text(reason.hint).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Anmerkung (freiwillig)") {
                    TextField("Was ist passiert?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if !target.text.isEmpty {
                    Section("Wird mitgeschickt") {
                        Text(ModerationReport.trim(target.text))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if mode == .report, target.canBlock {
                    Section {
                        Toggle("Person zusätzlich blockieren", isOn: $alsoBlock)
                    } footer: {
                        Text("Blockierte Personen verschwinden sofort aus Blubber, Postfach, Forum und Aktivitäten.")
                    }
                }

                Section {
                    Text("Wir sehen uns jede Meldung an und entfernen anstößige Inhalte innerhalb von 24 Stunden aus der App. Verfasser, die wiederholt auffallen, werden dauerhaft ausgeschlossen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mode == .block ? "Person blockieren" : "Beitrag melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .block ? "Blockieren" : "Senden") {
                        Task { await send() }
                    }
                    .disabled(isSending)
                }
            }
            .overlay {
                if isSending { ProgressView().controlSize(.large) }
            }
            .alert("Danke", isPresented: successBinding) {
                Button("Fertig") { dismiss() }
            } message: {
                Text(result == .mailed
                     ? "Der Meldeweg war gerade nicht erreichbar — die Meldung liegt als E-Mail bereit; bitte einmal auf Senden tippen."
                     : "Die Meldung ist angekommen. Wir sehen sie uns innerhalb von 24 Stunden an.")
            }
            .alert("Das hat nicht geklappt", isPresented: failureBinding) {
                Button("Schliessen") { result = nil }
            } message: {
                if case .failed(let message) = result { Text(message) }
            }
        }
        .onAppear { if mode == .block { alsoBlock = true } }
    }

    /// `.constant` reicht für einen Alarm nicht: SwiftUI setzt die Bindung
    /// beim Schliessen auf `false` und käme sonst nie wieder heraus.
    private var successBinding: Binding<Bool> {
        Binding(get: { result == .done || result == .mailed },
                set: { if !$0 { result = nil } })
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { if case .failed = result { return true } else { return false } },
                set: { if !$0 { result = nil } })
    }

    private var intro: String {
        switch mode {
        case .report:
            return "Die Inhalte in StudGo stammen aus Stud.IP und von anderen Angehörigen deiner Hochschule. Was gegen die Nutzungsbedingungen verstößt, kannst du hier melden."
        case .block:
            return "Blockierte Personen siehst du in StudGo nicht mehr — weder ihre Beiträge noch ihre Nachrichten. Aufheben lässt sich das in den Einstellungen unter „Melden und Blockieren“."
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        let outcome: ModerationStore.Outcome
        if mode == .block || alsoBlock, let authorID = target.authorID?.nilIfEmpty {
            outcome = await moderation.block(id: authorID,
                                             name: target.authorName,
                                             reason: reason,
                                             targetKind: target.kind,
                                             targetID: target.contentID,
                                             excerpt: target.text,
                                             note: note)
        } else {
            outcome = await moderation.report(reason: reason,
                                              targetKind: target.kind,
                                              targetID: target.contentID,
                                              authorID: target.authorID,
                                              authorName: target.authorName,
                                              excerpt: target.text,
                                              note: note)
        }

        switch outcome {
        case .sent:
            result = .done
        case .needsMail(let url):
            // Die Rückfallebene: Der Endpunkt war nicht erreichbar, also geht
            // die Meldung über das Mailprogramm raus.
            openURL(url)
            result = .mailed
        case .failed(let message):
            result = .failed(message)
        }
    }
}

enum ModerationSheetMode: Equatable, Identifiable {
    case report
    case block

    var id: String { self == .block ? "block" : "report" }
}

// MARK: - Menüpunkte für Detailansichten

/// „Melden" und „Blockieren" als Menü — für Ansichten mit Werkzeugleiste, wo
/// ein Kontextmenü zu gut versteckt wäre.
struct ModerationMenu: View {
    let target: ModerationTarget
    @State private var sheet: ModerationSheetMode?

    var body: some View {
        Menu {
            Button {
                sheet = .report
            } label: {
                Label("Melden", systemImage: "flag")
            }
            if target.canBlock {
                Button(role: .destructive) {
                    sheet = .block
                } label: {
                    Label("Person blockieren", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Melden oder blockieren")
        }
        .sheet(item: $sheet) { mode in
            ReportSheet(target: target, mode: mode)
        }
    }
}

// MARK: - Fertige Ziele für die Modelle

/// Damit die Ansichten nicht jedes Mal fünf Felder von Hand zusammensetzen —
/// und damit sich später an *einer* Stelle ändern lässt, was mitgeschickt wird.
extension ActivityItem {
    var moderationTarget: ModerationTarget {
        ModerationTarget(kind: .activity,
                         contentID: id,
                         authorID: actorID,
                         authorName: actorName,
                         text: [title, content].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

extension ForumEntry {
    var moderationTarget: ModerationTarget {
        ModerationTarget(kind: .forumEntry,
                         contentID: id,
                         authorID: authorID,
                         authorName: authorName,
                         text: [title, text].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

extension NewsItem {
    /// Ankündigungen tragen in Stud.IP keine Verfasserkennung, nur einen
    /// Namen — melden ja, blockieren nein.
    var moderationTarget: ModerationTarget {
        ModerationTarget(kind: .news,
                         contentID: id,
                         authorID: nil,
                         authorName: authorName,
                         text: [title, preview].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}
