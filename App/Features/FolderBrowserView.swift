import SwiftUI
import UniformTypeIdentifiers

/// Dateibereich einer Veranstaltung. Die Ordner werden erst beim Öffnen
/// nachgeladen — Stud.IP liefert Struktur und Inhalt getrennt.
struct FolderBrowserView: View {
    let course: Course
    @Environment(AuthStore.self) private var auth

    @State private var folders = Loadable<[Folder]>()

    var body: some View {
        List(folders.value ?? []) { folder in
            PushLink(value: folder) {
                RowLabel(symbol: "folder",
                         title: folder.name,
                         subtitle: folder.summary,
                         detail: folder.isEmpty ? "leer" : nil)
            }
        }
        .overlay {
            StateOverlay(isLoading: folders.isLoading,
                         errorMessage: folders.errorMessage,
                         isEmpty: (folders.value ?? []).isEmpty,
                         emptyText: "Keine Dateien freigegeben",
                         emptySymbol: "folder",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Dateien")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if folders.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await folders.load { try await client.rootFolders(of: course) }
    }
}

/// Inhalt eines Ordners: Unterordner und Dateien.
///
/// Kann mehr als nur zeigen — hochladen, auswählen, mehrere auf einmal
/// sichern, umbenennen, löschen und Unterordner anlegen. Was davon angeboten
/// wird, entscheidet `is-writable` am Ordner: Stud.IP gibt das Attribut je
/// Ordnertyp heraus, und ein Knopf, der hinterher am Server scheitert, ist
/// schlimmer als gar keiner.
struct FolderContentView: View {
    let folder: Folder
    @Environment(AuthStore.self) private var auth

    @State private var subfolders = Loadable<[Folder]>()
    @State private var files = Loadable<[FileRef]>()

    @State private var selection = Set<String>()
    @State private var isSelecting = false

    @State private var isImporting = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renaming: FileRef?
    @State private var renameText = ""

    @State private var transfer: TransferState?
    @State private var shareItems: [URL] = []
    @State private var isSharing = false
    @State private var message: String?

    /// Was gerade läuft — ein Zustand statt vier Boolescher.
    private enum TransferState: Equatable {
        case uploading(String)
        case downloading(done: Int, total: Int)

        var text: String {
            switch self {
            case .uploading(let name): return "\(name) wird hochgeladen…"
            case .downloading(let done, let total): return "Lädt \(done) von \(total)…"
            }
        }
    }

    private var isEmpty: Bool {
        (subfolders.value ?? []).isEmpty && (files.value ?? []).isEmpty
    }

    private var allFiles: [FileRef] { files.value ?? [] }

    private var selectedFiles: [FileRef] {
        allFiles.filter { selection.contains($0.id) }
    }

    var body: some View {
        List(selection: $selection) {
            if let banner = transfer {
                SwiftUI.Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(banner.text).font(.footnote)
                    }
                }
            }

            if let items = subfolders.value, !items.isEmpty {
                SwiftUI.Section("Ordner") {
                    ForEach(items) { child in
                        PushLink(value: child) {
                            RowLabel(symbol: "folder",
                                     title: child.name,
                                     subtitle: child.summary,
                                     detail: child.isEmpty ? "leer" : nil)
                        }
                        // Beim Auswählen sind nur Dateien gemeint — ein Ordner
                        // ließe sich nicht mit sichern.
                        .selectionDisabled()
                    }
                }
            }

            if !allFiles.isEmpty {
                SwiftUI.Section {
                    ForEach(allFiles) { file in
                        FileRow(file: file,
                                isSelecting: isSelecting,
                                canEdit: folder.allowsUpload,
                                onRename: { renaming = file; renameText = file.name },
                                onDelete: { Task { await delete(file) } })
                            .tag(file.id)
                    }
                } header: {
                    Text(allFiles.count == 1 ? "1 Datei" : "\(allFiles.count) Dateien")
                } footer: {
                    if let message {
                        Text(message).font(.caption)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .overlay {
            StateOverlay(isLoading: files.isLoading || subfolders.isLoading,
                         errorMessage: files.errorMessage ?? subfolders.errorMessage,
                         isEmpty: isEmpty && transfer == nil,
                         emptyText: folder.allowsUpload
                            ? "Ordner ist leer — du kannst hier hochladen"
                            : "Ordner ist leer",
                         emptySymbol: "folder",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selection.isEmpty { selectionBar }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            Task { await handleImport(result) }
        }
        .sheet(isPresented: $isSharing) {
            if !shareItems.isEmpty { ShareSheet(items: shareItems) }
        }
        .alert("Ordner anlegen", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Anlegen") { Task { await createFolder() } }
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Abbrechen", role: .cancel) { newFolderName = "" }
        }
        .alert("Umbenennen",
               isPresented: .init(get: { renaming != nil },
                                  set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Sichern") { Task { await rename() } }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        }
        .refreshable { await reload(fresh: true) }
        .task { if files.value == nil { await reload(fresh: false) } }
    }

    // MARK: - Werkzeugleiste

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Fertig") {
                    isSelecting = false
                    selection.removeAll()
                }
            } else {
                Menu {
                    if !allFiles.isEmpty {
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Auswählen", systemImage: "checkmark.circle")
                        }
                    }
                    if folder.allowsUpload {
                        Divider()
                        Button {
                            isImporting = true
                        } label: {
                            Label("Datei hochladen", systemImage: "arrow.up.doc")
                        }
                        Button {
                            newFolderName = ""
                            isCreatingFolder = true
                        } label: {
                            Label("Ordner anlegen", systemImage: "folder.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Weitere Möglichkeiten")
            }
        }
    }

    /// Leiste am unteren Rand, solange etwas ausgewählt ist.
    private var selectionBar: some View {
        HStack(spacing: 14) {
            Text(selection.count == 1 ? "1 Datei" : "\(selection.count) Dateien")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            Button {
                Task { await downloadSelection() }
            } label: {
                Label("Sichern", systemImage: "square.and.arrow.down")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(transfer != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Laden

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        async let children: Void = subfolders.load { try await client.subfolders(of: folder) }
        async let contents: Void = files.load { try await client.files(in: folder) }
        _ = await (children, contents)
    }

    // MARK: - Hochladen

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            // Der Standardordner der Lizenzen der Installation — Stud.IP
            // verlangt bei der Weboberfläche eine Angabe, die API nicht.
            let terms = try? await auth.client.termsOfUse()
            let termsID = (terms?.first(where: \.isDefault) ?? terms?.first)?.id

            var failed: [String] = []
            for url in urls {
                let name = url.lastPathComponent
                transfer = .uploading(name)
                // Aus „Dateien" kommt eine geschützte Adresse: ohne
                // `startAccessingSecurityScopedResource` schlägt das Lesen
                // mit „keine Berechtigung" fehl, obwohl der Nutzer die Datei
                // gerade selbst ausgewählt hat.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    try await auth.freshClient.upload(url, to: folder, named: name, termsID: termsID)
                } catch {
                    failed.append("\(name): \(error.localizedDescription)")
                }
            }
            transfer = nil
            message = failed.isEmpty
                ? (urls.count == 1 ? "Hochgeladen." : "\(urls.count) Dateien hochgeladen.")
                : failed.joined(separator: "\n")
            await reload(fresh: true)
        }
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        do {
            try await auth.freshClient.createFolder(named: name, in: folder)
            await reload(fresh: true)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Ändern

    private func rename() async {
        guard let file = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty, name != file.name else { return }
        do {
            try await auth.freshClient.renameFile(file.id, to: name)
            await reload(fresh: true)
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete(_ file: FileRef) async {
        do {
            try await auth.freshClient.deleteFile(file.id)
            selection.remove(file.id)
            await reload(fresh: true)
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Mehrere sichern

    /// Lädt die ausgewählten Dateien und übergibt sie ans Teilen-Menü.
    ///
    /// Dort steht „In Dateien sichern" — damit landen mehrere Anhänge in einem
    /// Rutsch in iCloud oder auf dem Gerät. Einen eigenen Zielordnerdialog
    /// bräuchte es dafür nicht.
    private func downloadSelection() async {
        let wanted = selectedFiles
        guard !wanted.isEmpty else { return }
        transfer = .downloading(done: 0, total: wanted.count)

        var urls: [URL] = []
        var failed: [String] = []
        for (index, file) in wanted.enumerated() {
            transfer = .downloading(done: index, total: wanted.count)
            if let url = try? await auth.client.download(file) {
                urls.append(url)
            } else {
                failed.append(file.name)
            }
        }
        transfer = nil

        if !failed.isEmpty {
            message = "Nicht geladen: \(failed.joined(separator: ", "))"
        }
        guard !urls.isEmpty else { return }
        shareItems = urls
        isSharing = true
    }
}

/// Einzelne Datei: antippen lädt herunter und öffnet die Systemvorschau.
struct FileRow: View {
    let file: FileRef
    var isSelecting = false
    var canEdit = false
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(AuthStore.self) private var auth

    @State private var localURL: URL?
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var showsPreview = false
    @State private var showsShareSheet = false

    private var subtitle: String? {
        [file.formattedSize, file.changedAt.map(Format.listDate)]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            RowLabel(symbol: file.symbolName, title: file.name, subtitle: subtitle) {
                if isDownloading {
                    ProgressView()
                } else if localURL != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Heruntergeladen")
                }
            }
        }
        .buttonStyle(.plain)
        // Im Auswahlmodus darf ein Tipp nicht die Vorschau öffnen — dort
        // bedeutet er „ankreuzen".
        .disabled(isSelecting || !file.isDownloadable || isDownloading)
        .swipeActions(edge: .trailing) {
            if canEdit, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Löschen", systemImage: "trash")
                }
            }
            if canEdit, let onRename {
                Button(action: onRename) {
                    Label("Umbenennen", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await share() }
            } label: {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                Task { await open() }
            } label: {
                Label("Öffnen", systemImage: "eye")
            }
            Button {
                Task { await share() }
            } label: {
                Label("Teilen / In Dateien sichern", systemImage: "square.and.arrow.up")
            }
            if canEdit {
                Divider()
                if let onRename {
                    Button(action: onRename) { Label("Umbenennen", systemImage: "pencil") }
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
                }
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
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showsShareSheet = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
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

    /// Holt die Datei, falls sie nicht schon lokal liegt.
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
