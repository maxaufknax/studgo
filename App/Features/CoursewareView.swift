import SwiftUI
import UIKit

/// Die Courseware einer Veranstaltung - Kapitel für Kapitel bis zu den
/// Blöcken.
///
/// **Was hier lesend integriert ist und was nicht:** Die JSON:API liefert den
/// ganzen Baum (`/v1/courses/{id}/courseware` → Kapitel → Abschnitte →
/// Blöcke). Textnahe Blöcke setzt die App selbst; verweisende Blöcke öffnen
/// ihr Ziel; dateibasierte Blöcke lösen ihre Datei über `file-refs` auf und
/// öffnen sie in der Systemvorschau. Das **Bearbeiten** ist ein eigener
/// Editor mit Zustand je Blocktyp; der Knopf oben rechts führt in die
/// Weboberfläche.
struct CoursewareView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var chapter = Loadable<CoursewareChapter>()
    @StateObject private var children = Loadable<[CoursewareChapter]>()
    @StateObject private var sections = Loadable<[CoursewareSection]>()
    @State private var blocksBySection: [String: [CoursewareBlock]] = [:]
    /// Dateiblöcke nach Kennung aufgelöst - Name und Größe stehen erst hier.
    @State private var fileRefs: [String: FileRef] = [:]
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

    /// Die Abschnitte dieses Kapitels mit ihren Blöcken - der eigentliche
    /// Inhalt.
    @ViewBuilder
    private var contentSections: some View {
        let all = sections.value ?? []
        if !all.isEmpty {
            ForEach(all) { section in
                Section(section.title) {
                    ForEach(blocksBySection[section.id] ?? []) { block in
                        CoursewareBlockRow(block: block,
                                           file: fileRefs[block.fileID ?? ""],
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

        // Das Wurzelkapitel gehört zu beiden Anfragen - erst seine Kennung,
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

        // Blöcke je Abschnitt - nacheinander, der Client ist nicht teilbar
        // über Aufgabengrenzen (siehe `StudIPClient`).
        var collected: [String: [CoursewareBlock]] = [:]
        for section in sections.value ?? [] {
            collected[section.id] = try? await client.coursewareBlocks(of: section.id)
        }
        blocksBySection = collected
        fileRefs = await resolveFiles(in: collected, client: client)
    }
}

/// Ein Kapitel unterhalb des Wurzelkapitels - derselbe Aufbau wie die
/// Startseite, nur mit eigenen Kindern.
struct CoursewareChapterView: View {
    let chapter: CoursewareChapter
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var children = Loadable<[CoursewareChapter]>()
    @StateObject private var sections = Loadable<[CoursewareSection]>()
    @State private var blocksBySection: [String: [CoursewareBlock]] = [:]
    @State private var fileRefs: [String: FileRef] = [:]
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
                                           file: fileRefs[block.fileID ?? ""],
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
        fileRefs = await resolveFiles(in: collected, client: client)
    }
}

/// Ein Block, so gut es die Sorte hergibt.
struct CoursewareBlockRow: View {
    let block: CoursewareBlock
    /// Die aufgelöste Datei des Blocks - oder nichts, wenn sie nicht zu
    /// holen war; dann verweist die Zeile auf die Weboberfläche.
    var file: FileRef? = nil
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
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)

        case .file:
            if let file {
                CoursewareFileBlock(file: file,
                                    fallbackTitle: block.title ?? block.typeTitle)
            } else {
                RowLabel(symbol: "paperclip",
                         title: block.title ?? block.typeTitle,
                         subtitle: "Datei in der Courseware",
                         detail: "In Stud.IP öffnen")
            }

        case .unsupported:
            RowLabel(symbol: "square.dashed",
                     title: block.title ?? block.typeTitle,
                     subtitle: "\(block.typeTitle), in Stud.IP ansehen")
        }
    }

    /// Eigener Titel oder der Name der Blockart - ohne Zeile bleibt der
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


/// Dateiblöcke zu Dateien auflösen - einmal je Kennung, auch wenn dieselbe
/// Datei in mehreren Abschnitten steht. Fehlt eine Datei (gelöscht, Rechte,
/// kaputte Kennung), bleibt sie einfach weg; der Block zeigt dann seinen
/// Stud.IP-Verweis.
private func resolveFiles(in blocks: [String: [CoursewareBlock]],
                          client: StudIPClient) async -> [String: FileRef] {
    let wanted = Set(blocks.values.flatMap { $0 }.compactMap(\.fileID))
    var refs: [String: FileRef] = [:]
    for id in wanted {
        if let ref = try? await client.fileRef(id: id) { refs[id] = ref }
    }
    return refs
}

/// Ein dateibasierter Block - die Datei steckt hinter einer eigenen Kennung,
/// StudGo holt sie auf Antippen in den temporären Ordner und zeigt sie in
/// der Systemvorschau. Derselbe Ablauf wie im Dateibereich
/// (siehe `FolderBrowserView`), nur ohne Ordner drumherum.
struct CoursewareFileBlock: View {
    let file: FileRef
    /// Name des Blocks, solange die Datei noch lädt - die Zeile soll nie
    /// leer dastehen, auch nicht zwischen den Anfragen.
    var fallbackTitle: String

    @EnvironmentObject private var auth: AuthStore
    @State private var localURL: URL?
    @State private var showsPreview = false
    @State private var showsShareSheet = false
    @State private var errorMessage: String?
    @State private var isDownloading = false

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            RowLabel(symbol: file.symbolName,
                     title: file.name.isEmpty ? fallbackTitle : file.name,
                     subtitle: "Datei in der Courseware",
                     detail: file.formattedSize) {
                if isDownloading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await share() }
            } label: {
                Label("Teilen / In Dateien sichern", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $showsPreview) {
            if let localURL {
                NavigationStack {
                    QuickLookPreview(url: localURL)
                        .ignoresSafeArea()
                        .navigationTitle(file.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button {
                                    showsShareSheet = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .accessibilityLabel("Teilen")
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            if let localURL { ShareSheet(items: [localURL]) }
        }
        .alert("Download fehlgeschlagen",
               isPresented: .init(get: { errorMessage != nil },
                                  set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func open() async {
        guard await ensureDownloaded() else { return }
        showsPreview = true
    }

    private func share() async {
        guard await ensureDownloaded() else { return }
        showsShareSheet = true
    }

    private func ensureDownloaded() async -> Bool {
        if let localURL, FileManager.default.fileExists(atPath: localURL.path) { return true }
        isDownloading = true
        defer { isDownloading = false }
        do {
            localURL = try await auth.client.download(file)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
