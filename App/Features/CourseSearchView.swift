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
        .searchable(text: $term, prompt: "Titel, Lehrende oder Nummer")
        .onSubmit(of: .search) { schedule(delay: 0) }
        // Von selbst suchen, sobald genug getippt ist. Vorher musste man die
        // Eingabetaste treffen — wer das nicht tat, hielt die Suche für kaputt.
        .onChange(of: term) { schedule(delay: 500) }
        .navigationTitle("Suchen")
        .navigationBarTitleDisplayMode(.inline)
        // Kein eigenes `navigationDestination(for: Course.self)`: Diese
        // Ansicht wird immer in einen Stapel geschoben, der es schon
        // anmeldet. Zwei Anmeldungen desselben Typs im selben Stapel
        // beschwert SwiftUI zur Laufzeit.
        .task { if semesters.value == nil { await loadSemesters() } }
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
        if results.isLoading {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        } else if let message = results.errorMessage {
            Section {
                ContentUnavailableView {
                    Label("Suche fehlgeschlagen", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Erneut versuchen") { Task { await search() } }
                }
            }
        } else if let found = results.value {
            Section {
                if found.isEmpty {
                    Text("Keine Veranstaltung gefunden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(found) { course in
                        NavigationLink(value: course) {
                            CourseRow(course: course,
                                      typeName: auth.courseTypeName(course.typeID))
                        }
                    }
                }
            } header: {
                Text(found.isEmpty ? "Kein Treffer" : "\(found.count) Treffer")
            } footer: {
                if !found.isEmpty {
                    Text("Zum Eintragen eine Veranstaltung öffnen — die Anmeldung läuft über die Stud.IP-Weboberfläche.")
                }
            }
        } else {
            Section {
                ContentUnavailableView("Veranstaltung suchen",
                                       systemImage: "magnifyingglass",
                                       description: Text("Mindestens drei Zeichen eingeben — gesucht wird von selbst."))
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
        guard !isTermTooShort else {
            // Zurück auf den Ausgangszustand, sobald der Begriff zu kurz wird
            // — ein alter Trefferstand zu einem gelöschten Suchwort verwirrt.
            if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.value = nil
                results.errorMessage = nil
                didSearch = false
            }
            return
        }
        pending = Task {
            if milliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(milliseconds))
                guard !Task.isCancelled else { return }
            }
            await search()
        }
    }

    private func search() async {
        guard !isTermTooShort else { return }
        didSearch = true
        let client = auth.client
        let query = term
        let selectedField = field
        let semester = semesterChoice
        await results.load {
            try await client.searchCourses(query, field: selectedField, semesterID: semester)
        }
    }
}
