import SwiftUI
import UIKit

/// Die Courseware einer Veranstaltung — Kapitel für Kapitel bis zu den
/// Blöcken.
///
/// **Was hier lesend integriert ist und was nicht:** Die JSON:API liefert den
/// ganzen Baum (`/v1/courses/{id}/courseware` → Kapitel → Abschnitte →
/// Blöcke). Textnahe Blöcke setzt die App selbst; verweisende Blöcke öffnen
/// ihr Ziel; Datei- und Video-Blöcke sagen, dass sie in Stud.IP stehen —
/// ihre Inhalte hängen an Dateien, die sich über die Beziehung `file-refs`
/// einzeln auflösen ließen, aber nicht an einer Route, die StudGo schon
/// benutzt. Das **Bearbeiten** ist ein eigener Editor mit Zustand je
/// Blocktyp; der Knopf oben rechts führt in die Weboberfläche.
struct CoursewareView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var chapter = Loadable<CoursewareChapter>()
    @StateObject private var children = Loadable<[CoursewareChapter]>()
    @StateObject private var sections = Loadable<[CoursewareSection]>()
    @State private var blocksBySection: [String: [CoursewareBlock]] = [:]
    @State private var webTarget: WebTarget?

    var body: some View {
        List {
            if let root = chapter.value {
                chapterSection(root)
                subchaptersSection
                contentSections
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: chapter.isLoading && children.isLoading,
                         errorMessage: chapter.errorMessage ?? children.errorMessage,
                         isEmpty: chapter.value == nil,
                         emptyText: "Keine Courseware",
                         emptySymbol: "square.grid.2x2",
                         retry: { Task { await load(fresh: true) } })
        }
        .navigationTitle("Courseware")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    webTarget = WebTarget(url: WebLinks.courseware(courseID: course.id))
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("In Stud.IP öffnen")
            }
        }
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url)
        }
        .refreshable { await load(fresh: true) }
        .task { await load(fresh: false) }
    }

    // MARK: - Abschnitte

    private func chapterSection(_ root: CoursewareChapter) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(root.title).font(.headline)
                if let summary = root.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var subchaptersSection: some View {
        let chapters = children.value ?? []
        if !chapters.isEmpty {
            Section("Kapitel") {
                ForEach(chapters) { child in
                    PushLink(value: Route.coursewareChapter(course, child)) {
                        RowLabel(symbol: "book.pages", title: child.title,
                                 subtitle: child.summary)
                    }
                }
            }
        }
    }

    /// Die Abschnitte dieses Kapitels mit ihren Blöcken — der eigentliche
    /// Inhalt.
    @ViewBuilder
    private var contentSections: some View {
        let all = sections.value ?? []
        if !all.isEmpty {
            ForEach(all) { section in
                Section(section.title) {
                    ForEach(blocksBySection[section.id] ?? []) { block in
                        CoursewareBlockRow(block: block,
                                           courseID: course.id,
                                           openWeb: { webTarget = WebTarget(url: $0) })
                    }
                    if (blocksBySection[section.id] ?? []).isEmpty
                        && sections.hasValue {
                        Text("Nichts angelegt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if sections.hasValue {
            Section {
                Text("Dieses Kapitel hat keine Abschnitte.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Laden

    private func load(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        let courseID = course.id

        // Das Wurzelkapitel gehört zu beiden Anfragen — erst seine Kennung,
        // dann alles darunter.
        let root = try? await client.coursewareRootID(of: courseID)
        guard let root, !root.isEmpty else {
            chapter.value = nil
            children.value = []
            sections.value = []
            return
        }
        await chapter.load { try await client.coursewareChapter(id: root) }
        await children.load { try await client.coursewareChildren(of: root) }
        await sections.load { try await client.coursewareSections(of: root) }

        // Blöcke je Abschnitt — nacheinander, der Client ist nicht teilbar
        // über Aufgabengrenzen (siehe `StudIPClient`).
        var collected: [String: [CoursewareBlock]] = [:]
        for section in sections.value ?? [] {
            collected[section.id] = try? await client.coursewareBlocks(of: section.id)
        }
        blocksBySection = collected
    }
}

/// Ein Kapitel unterhalb des Wurzelkapitels — derselbe Aufbau wie die
/// Startseite, nur mit eigenen Kindern.
struct CoursewareChapterView: View {
    let chapter: CoursewareChapter
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var children = Loadable<[CoursewareChapter]>()
    @StateObject private var sections = Loadable<[CoursewareSection]>()
    @State private var blocksBySection: [String: [CoursewareBlock]] = [:]
    @State private var webTarget: WebTarget?

    var body: some View {
        List {
            if let summary = chapter.summary {
                Section {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            subchaptersSection
            contentSections
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: children.isLoading,
                         errorMessage: children.errorMessage,
                         isEmpty: false,
                         emptyText: "",
                         emptySymbol: "square.grid.2x2",
                         retry: { Task { await load(fresh: true) } })
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    webTarget = WebTarget(url: WebLinks.courseware(courseID: course.id))
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("In Stud.IP öffnen")
            }
        }
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url)
        }
        .refreshable { await load(fresh: true) }
        .task { await load(fresh: false) }
    }

    @ViewBuilder
    private var subchaptersSection: some View {
        let chapters = children.value ?? []
        if !chapters.isEmpty {
            Section("Kapitel") {
                ForEach(chapters) { child in
                    PushLink(value: Route.coursewareChapter(course, child)) {
                        RowLabel(symbol: "book.pages", title: child.title,
                                 subtitle: child.summary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contentSections: some View {
        let all = sections.value ?? []
        if !all.isEmpty {
            ForEach(all) { section in
                Section(section.title) {
                    ForEach(blocksBySection[section.id] ?? []) { block in
                        CoursewareBlockRow(block: block,
                                           courseID: course.id,
                                           openWeb: { webTarget = WebTarget(url: $0) })
                    }
                }
            }
        }
    }

    private func load(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await children.load { try await client.coursewareChildren(of: chapter.id) }
        await sections.load { try await client.coursewareSections(of: chapter.id) }

        var collected: [String: [CoursewareBlock]] = [:]
        for section in sections.value ?? [] {
            collected[section.id] = try? await client.coursewareBlocks(of: section.id)
        }
        blocksBySection = collected
    }
}

/// Ein Block, so gut es die Sorte hergibt.
struct CoursewareBlockRow: View {
    let block: CoursewareBlock
    let courseID: String
    var openWeb: (URL) -> Void

    var body: some View {
        switch block.content {
        case .formatted(let text), .html(let text):
            VStack(alignment: .leading, spacing: 8) {
                header
                FormattedText(raw: text, font: .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

        case .link(let url, let title):
            Button {
                if let address = URL(string: url) { openExternally(address) }
            } label: {
                RowLabel(symbol: "link",
                         title: title ?? url,
                         subtitle: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

        case .file:
            RowLabel(symbol: "paperclip",
                     title: block.title ?? block.typeTitle,
                     subtitle: "Datei in der Courseware",
                     detail: "In Stud.IP öffnen")

        case .unsupported:
            RowLabel(symbol: "square.dashed",
                     title: block.title ?? block.typeTitle,
                     subtitle: "\(block.typeTitle), in Stud.IP ansehen")
        }
    }

    /// Eigener Titel oder der Name der Blockart — ohne Zeile bleibt der
    /// Block sonst namenlos im Bild.
    @ViewBuilder
    private var header: some View {
        if let title = block.title, !title.isEmpty {
            Text(title).font(.subheadline.weight(.semibold))
        }
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
