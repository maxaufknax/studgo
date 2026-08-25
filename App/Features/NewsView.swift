import SwiftUI

/// Ankündigungen aus den eigenen Veranstaltungen und vom Stud.IP-Startpunkt.
struct NewsView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    enum Scope: String, CaseIterable, Identifiable {
        case personal = "Meine"
        case global = "Uni"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .personal
    @State private var personal = Loadable<[NewsItem]>()
    @State private var global = Loadable<[NewsItem]>()

    private var current: Loadable<[NewsItem]> { scope == .personal ? personal : global }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedHeader(title: "Bereich",
                            options: Scope.allCases,
                            selection: $scope) { $0.rawValue }

            List(current.value ?? []) { item in
                NavigationLink(value: item) { NewsRow(item: item) }
            }
            .listStyle(.insetGrouped)
            .overlay {
                StateOverlay(isLoading: current.isLoading,
                             errorMessage: current.errorMessage,
                             isEmpty: (current.value ?? []).isEmpty,
                             emptyText: "Keine Ankündigungen",
                             emptySymbol: "megaphone",
                             retry: { Task { await reload(fresh: true) } })
            }
        }
        // Kein eigenes `navigationDestination`: Diese Ansicht wird immer in
        // einen Stapel geschoben, der `NewsItem` schon anmeldet.
        .navigationTitle("Ankündigungen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task(id: scope) { if current.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        switch scope {
        case .personal: await personal.load { try await client.news(for: user.id) }
        case .global: await global.load { try await client.globalNews() }
        }
    }
}

struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                if let author = item.authorName { Text(author) }
                if let date = item.publishedAt { Text(Format.listDate(date)) }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(item.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct NewsDetailView: View {
    let item: NewsItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title).font(.title3.bold())

                HStack(spacing: 6) {
                    if let author = item.authorName { Text(author) }
                    if let date = item.publishedAt {
                        Text(date, format: .dateTime.day().month(.wide).year())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                // Ankündigungen sind der Ort, an dem Lehrende formatieren:
                // Aufzählungen, Fettung, Verweise auf Seiten und Dateien.
                FormattedText(raw: item.content, font: .body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Ankündigung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension NewsItem: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
