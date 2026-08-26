import SwiftUI

/// Das ganze Vorlesungsverzeichnis durchsuchen — nicht nur die eigenen
/// Veranstaltungen.
///
/// Gesucht wird **serverseitig** über `/v1/courses?filter[q]=…`. Der
/// Suchbegriff braucht mindestens drei Zeichen, sonst antwortet Stud.IP mit
/// `400 Search term too short`; die Ansicht wartet deshalb ab, statt in einen
/// Fehler zu laufen.
struct CourseSearchView: View {
    @Environment(AuthStore.self) private var auth

    @State private var term = ""
    @State private var field: StudIPClient.CourseSearchField = .all
    @State private var semesterChoice: String?
    @State private var results = Loadable<[Course]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var didSearch = false
    /// Läuft, während getippt wird — eine Anfrage je Tastendruck wäre zu viel.
    @State private var pending: Task<Void, Never>?
    /// Öffnet und fokussiert das Suchfeld, sobald die Ansicht erscheint. Ohne
    /// das lag die Leiste eingeklappt über der Liste und wurde erst nach dem
    /// Herunterziehen sichtbar — es sah aus, als gäbe es kein Suchfeld.
    @State private var searchPresented = false
    /// Zählt die aufeinanderfolgenden Fehlversuche, damit ein einzelner
    /// Netzhänger nicht gleich als „Suche fehlgeschlagen" erscheint.
    @State private var failedAttempts = 0
    /// Vom ersten getippten Zeichen bis zum Ergebnis — trägt den ruhigen
    /// „Suche läuft…"-Zustand, auch während der Wartezeit vor dem Absenden.
    @State private var awaitingResults = false

    private var sortedSemesters: [Semester] {
        (semesters.value ?? []).sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    private var semesterLabel: String {
        guard let semesterChoice else { return "Alle Semester" }
        return sortedSemesters.first { $0.id == semesterChoice }?.title ?? "Semester"
    }

    private var isTermTooShort: Bool {
        term.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
    }

    var body: some View {
        List {
            filterSection
            resultSection
        }
        .listStyle(.insetGrouped)
        // Immer sichtbar statt eingeklappt, und beim Erscheinen gleich
        // fokussiert: Die Suche ist der Zweck dieser Seite.
        .searchable(text: $term,
                    isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Titel, Lehrende oder Nummer")
        .onSubmit(of: .search) { schedule(delay: 0) }
        // Von selbst suchen, sobald genug getippt ist. Vorher musste man die
        // Eingabetaste treffen — wer das nicht tat, hielt die Suche für kaputt.
        .onChange(of: term) { schedule(delay: 400) }
        .navigationTitle("Suchen")
        .navigationBarTitleDisplayMode(.inline)
        // Kein eigenes `navigationDestination(for: Course.self)`: Diese
        // Ansicht wird immer in einen Stapel geschoben, der es schon
        // anmeldet. Zwei Anmeldungen desselben Typs im selben Stapel
        // beschwert SwiftUI zur Laufzeit.
        .task { if semesters.value == nil { await loadSemesters() } }
        .task {
            // Nach dem Aufbau — nicht in `onAppear`, das liefe noch in die
            // Schiebe-Animation hinein und der Fokus verpuffte.
            searchPresented = true
        }
    }

    // MARK: - Filter

    private var filterSection: some View {
        Section {
            Picker("Suchen in", selection: $field) {
                ForEach(StudIPClient.CourseSearchField.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Picker("Semester", selection: $semesterChoice) {
                Text("Alle Semester").tag(String?.none)
                ForEach(sortedSemesters) { semester in
                    Text(semester.title).tag(String?.some(semester.id))
                }
            }
        } header: {
            Text("Eingrenzen")
        } footer: {
            Text(isTermTooShort
                 ? "Mindestens drei Zeichen — Stud.IP lehnt kürzere Anfragen ab."
                 : "Aktuell: \(field.label) · \(semesterLabel)")
        }
        // Bei geänderten Filtern gleich neu suchen — aber nur, wenn schon
        // einmal gesucht wurde, sonst feuert die Ansicht beim Aufbau los.
        .onChange(of: field) { if didSearch { schedule(delay: 0) } }
        .onChange(of: semesterChoice) { if didSearch { schedule(delay: 0) } }
    }

    // MARK: - Treffer

    @ViewBuilder
    private var resultSection: some View {
        if let found = results.value, !found.isEmpty {
            // Sind Treffer da, gewinnen sie **immer**: Ein misslungenes
            // Nachschlagen darf die Liste nicht hinter einer Fehlermeldung
            // wegräumen. Ein neuer Lauf zeigt sich als kleiner Fortschritt in
            // der Kopfzeile, nicht als leerer Bildschirm.
            Section {
                ForEach(found) { course in
                    PushLink(value: course) {
                        CourseRow(course: course,
                                  typeName: auth.courseTypeName(course.typeID))
                    }
                }
            } header: {
                HStack {
                    Text("\(found.count) Treffer")
                    if awaitingResults {
                        Spacer()
                        ProgressView().controlSize(.mini)
                    }
                }
            } footer: {
                Text("Zum Eintragen eine Veranstaltung öffnen — die Anmeldung läuft über die Stud.IP-Weboberfläche.")
            }
        } else if awaitingResults {
            // Ruhiger Zwischenstand vom ersten Zeichen an, statt kurz „nichts
            // gefunden" oder „fehlgeschlagen" aufblitzen zu lassen.
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suche läuft…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } else if didSearch, results.errorMessage != nil {
            Section {
                ContentUnavailableView {
                    Label("Suche gerade nicht möglich", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Stud.IP hat nicht rechtzeitig geantwortet. Das liegt meist an der Verbindung — noch einmal versuchen geht oft sofort.")
                } actions: {
                    Button("Erneut suchen") { schedule(delay: 0) }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else if results.value != nil {
            Section {
                Text("Keine Veranstaltung gefunden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Kein Treffer")
            }
        } else {
            Section {
                ContentUnavailableView("Veranstaltung suchen",
                                       systemImage: "magnifyingglass",
                                       description: Text("Tippen genügt — ab drei Zeichen wird von selbst gesucht."))
            }
        }
    }

    // MARK: - Laden

    private func loadSemesters() async {
        let client = auth.client
        await semesters.load { try await client.semesters() }
    }

    /// Wartet kurz ab, bevor gesucht wird, und verwirft dabei die vorige
    /// noch nicht abgeschickte Anfrage.
    private func schedule(delay milliseconds: Int) {
        pending?.cancel()
        failedAttempts = 0
        guard !isTermTooShort else {
            awaitingResults = false
            // Zurück auf den Ausgangszustand, sobald der Begriff zu kurz wird
            // — ein alter Trefferstand zu einem gelöschten Suchwort verwirrt.
            if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.value = nil
                results.errorMessage = nil
                didSearch = false
            }
            return
        }
        // Sofort ansagen, dass gesucht wird — noch vor Ablauf der Wartezeit.
        awaitingResults = true
        pending = Task {
            if milliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(milliseconds))
                guard !Task.isCancelled else { return }
            }
            await search()
        }
    }

    private func search() async {
        guard !isTermTooShort else { awaitingResults = false; return }
        didSearch = true
        let client = auth.client
        let query = term
        let selectedField = field
        let semester = semesterChoice
        await results.load {
            try await client.searchCourses(query, field: selectedField, semesterID: semester)
        }

        // Ein einzelner Fehlversuch wird still wiederholt, statt sofort als
        // „fehlgeschlagen" zu erscheinen — das nimmt der Suche das Zappelige.
        if results.errorMessage != nil, term == query {
            failedAttempts += 1
            if failedAttempts < 2, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, term == query else { awaitingResults = false; return }
                await search()
                return
            }
        }
        awaitingResults = false
    }
}
