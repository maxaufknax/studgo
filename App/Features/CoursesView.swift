import SwiftUI

struct CoursesView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var courses = Loadable<[Course]>()
    @State private var search = ""

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
            List(filtered) { course in
                NavigationLink(value: course) { CourseRow(course: course) }
            }
            .searchable(text: $search, prompt: "Veranstaltung suchen")
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .overlay {
                StateOverlay(isLoading: courses.isLoading,
                             errorMessage: courses.errorMessage,
                             isEmpty: filtered.isEmpty,
                             emptyText: search.isEmpty ? "Keine Veranstaltungen" : "Nichts gefunden",
                             emptySymbol: search.isEmpty ? "books.vertical" : "magnifyingglass",
                             retry: { Task { await reload() } })
            }
            .navigationTitle("Veranstaltungen")
            .refreshable { await reload() }
            .task { if courses.value == nil { await reload() } }
        }
    }

    private func reload() async {
        let client = auth.client
        await courses.load { try await client.courses(for: user.id) }
    }
}

struct CourseRow: View {
    let course: Course

    var body: some View {
        HStack(spacing: 12) {
            AccentBar(seed: course.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let subtitle = course.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let number = course.courseNumber { Text(number) }
                    if let type = course.courseType { Text(type) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

extension Course: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
