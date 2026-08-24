import SwiftUI

struct CoursesView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    /// Ohne Filter liefert Stud.IP alle je belegten Veranstaltungen. Nach ein
    /// paar Semestern ist das eine Liste, in der niemand mehr etwas findet —
    /// deshalb steht das laufende Semester voreingestellt.
    enum SemesterChoice: Hashable {
        case undecided
        case all
        case one(String)
    }

    @State private var courses = Loadable<[Course]>()
    @State private var semesters = Loadable<[Semester]>()
    @State private var choice: SemesterChoice = .undecided
    @State private var search = ""

    private var sortedSemesters: [Semester] {
        (semesters.value ?? []).sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    private var choiceLabel: String {
        switch choice {
        case .all: return "Alle Semester"
        case .one(let id):
            return sortedSemesters.first { $0.id == id }?.title ?? "Semester"
        case .undecided: return "…"
        }
    }

    private var filtered: [Course] {
        let all = (courses.value ?? []).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || ($0.courseNumber?.localizedCaseInsensitiveContains(search) ?? false)
                || ($0.subtitle?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filtered.isEmpty {
                    Section {
                        ForEach(filtered) { course in
                            NavigationLink(value: course) {
                                CourseRow(course: course,
                                          typeName: auth.courseTypeName(course.typeID))
                            }
                        }
                    } header: {
                        Text("\(filtered.count) \(filtered.count == 1 ? "Veranstaltung" : "Veranstaltungen")")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Veranstaltung suchen")
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .overlay {
                StateOverlay(isLoading: courses.isLoading,
                             errorMessage: courses.errorMessage,
                             isEmpty: filtered.isEmpty,
                             emptyText: emptyText,
                             emptySymbol: search.isEmpty ? "books.vertical" : "magnifyingglass",
                             retry: { Task { await reload(fresh: true) } })
            }
            .navigationTitle("Veranstaltungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Semester", selection: $choice) {
                            Text("Alle Semester").tag(SemesterChoice.all)
                            ForEach(sortedSemesters) { semester in
                                Text(semester.title).tag(SemesterChoice.one(semester.id))
                            }
                        }
                    } label: {
                        Label(choiceLabel, systemImage: "line.3.horizontal.decrease.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                    }
                }
            }
            .refreshable { await reload(fresh: true) }
            .task { await prepare() }
            .task(id: choice) { await reloadIfNeeded() }
        }
    }

    private var emptyText: String {
        if !search.isEmpty { return "Nichts gefunden" }
        if case .one = choice { return "Keine Veranstaltungen in diesem Semester" }
        return "Keine Veranstaltungen"
    }

    // MARK: - Laden

    /// Zuerst die Semester holen, um das laufende vorzuwählen. Klappt das
    /// nicht — etwa ohne Netz und ohne Zwischenspeicher — wird eben alles
    /// gezeigt, statt die Liste leer zu lassen.
    private func prepare() async {
        guard choice == .undecided else { return }
        let client = auth.client
        await semesters.load { try await client.semesters() }
        if let current = (semesters.value ?? []).first(where: { $0.isCurrent }) {
            choice = .one(current.id)
        } else {
            choice = .all
        }
    }

    private func reloadIfNeeded() async {
        guard choice != .undecided else { return }
        await reload(fresh: false)
    }

    private func reload(fresh: Bool) async {
        guard choice != .undecided else { return }
        let client = fresh ? auth.freshClient : auth.client
        let semester: String? = {
            if case .one(let id) = choice { return id }
            return nil
        }()
        await courses.load { try await client.courses(for: user.id, semester: semester) }
    }
}

struct CourseRow: View {
    let course: Course
    var typeName: String?

    var body: some View {
        HStack(spacing: 12) {
            AccentBar(seed: course.id)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.shortTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let subtitle = course.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    if let number = course.courseNumber {
                        Chip(text: number, color: Tint.color(course.id))
                    }
                    if let typeName {
                        Chip(text: typeName)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

extension Course: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
