import SwiftUI

/// **Eigene Termine** — die selbst angelegten Blöcke des Stundenplans.
///
/// In Stud.IP heißen sie „Termine" und stehen unter *Stundenplan → Neuer
/// Termin*: das Tutorium, die AG, der Sport am Donnerstag. Anders als die
/// Sitzungen einer Veranstaltung gehören sie niemandem sonst — sie laufen
/// ohne Semesterbezug und bleiben auch in der vorlesungsfreien Zeit stehen.
///
/// **Warum das Anlegen und Löschen über die Weboberfläche läuft.** Die
/// JSON:API kennt zu `schedule-entries` genau eine Route, und die ist ein
/// `GET`:
///
/// ```php
/// $group->get('/users/{id}/schedule',        Routes\Schedule\UserScheduleShow::class);
/// $group->get('/schedule-entries/{id}',      Routes\Schedule\ScheduleEntriesShow::class);
/// $group->get('/seminar-cycle-dates/{id}',   Routes\Schedule\SeminarCycleDatesShow::class);
/// ```
///
/// Kein POST, kein PATCH, kein DELETE — es gibt keine Route, die man
/// übersehen hätte. Die Weboberfläche schreibt über
/// `calendar/schedule/entry/{id}` mit CSRF-Merkmal; genau dorthin führen die
/// Knöpfe hier. Ein nachgebauter Dialog, der beim Speichern abbricht, wäre
/// die schlechtere Antwort.
///
/// Nach dem Schließen des Blatts wird neu geladen — was in Stud.IP angelegt
/// oder gelöscht wurde, steht danach auch hier.
struct OwnScheduleEntriesView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var entries = Loadable<[ScheduleEntry]>()
    @State private var webTarget: WebTarget?
    /// Wurde ein Blatt geöffnet? Dann beim Schließen erneuern.
    @State private var needsRefresh = false

    /// Nur die selbst angelegten: Turnustermine von Veranstaltungen gehören
    /// der Veranstaltung und lassen sich hier weder ändern noch löschen.
    private var own: [ScheduleEntry] {
        (entries.value ?? []).filter { !$0.isCourse }
    }

    private var grouped: [(weekday: Int, entries: [ScheduleEntry])] {
        Dictionary(grouping: own, by: \.normalizedWeekday)
            .map { (weekday: $0.key, entries: $0.value.sorted { $0.startMinutes < $1.startMinutes }) }
            .sorted { $0.weekday < $1.weekday }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.weekday) { group in
                Section(Weekday.full(group.weekday)) {
                    ForEach(group.entries) { entry in
                        Button {
                            open(WebLinks.scheduleEntry(entry.id))
                        } label: {
                            OwnScheduleEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button {
                                open(WebLinks.scheduleEntry(entry.id))
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.accentColor)
                        }
                    }
                }
            }

            Section {
                Button {
                    open(WebLinks.newScheduleEntry())
                } label: {
                    RowLabel(symbol: "plus.circle",
                             title: "Neuen Termin anlegen",
                             subtitle: "Öffnet Stud.IP")
                }
                .buttonStyle(.plain)

                Button {
                    open(WebLinks.schedule)
                } label: {
                    RowLabel(symbol: "square.grid.3x3",
                             title: "Stundenplan in Stud.IP",
                             subtitle: "Alle Blöcke, auch die der Veranstaltungen")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Anlegen, Ändern und Löschen laufen über die Weboberfläche: Die Stud.IP-Schnittstelle bietet zu eigenen Terminen ausschließlich Lesezugriff. Nach dem Schließen wird diese Liste erneuert.")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: entries.isLoading,
                         errorMessage: entries.errorMessage,
                         isEmpty: own.isEmpty && entries.hasValue,
                         emptyText: "Keine eigenen Termine",
                         emptySymbol: "calendar.badge.plus",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Eigene Termine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    open(WebLinks.newScheduleEntry())
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Termin anlegen")
            }
        }
        .sheet(item: $webTarget, onDismiss: {
            guard needsRefresh else { return }
            needsRefresh = false
            Task { await reload(fresh: true) }
        }) { target in
            WebSheet(url: target.url)
        }
        .refreshable { await reload(fresh: true) }
        .task { if entries.value == nil { await reload(fresh: false) } }
    }

    private func open(_ url: URL) {
        needsRefresh = true
        webTarget = WebTarget(url: url)
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        let userID = user.id
        await entries.load { try await client.schedule(for: userID) }
    }
}

/// Ein eigener Termin in der Liste — Zeit, Titel, Notiz.
struct OwnScheduleEntryRow: View {
    let entry: ScheduleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Tint.color(entry.tintSeed))
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                Text(entry.timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let note = entry.description {
                    Text(StudipMarkup.plain(from: note))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "pencil.circle")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
