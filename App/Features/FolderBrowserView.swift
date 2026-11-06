import SwiftUI
import UniformTypeIdentifiers

/// Dateibereich einer Veranstaltung. Die Ordner werden erst beim Öffnen
/// nachgeladen - Stud.IP liefert Struktur und Inhalt getrennt.
struct FolderBrowserView: View {
    let course: Course
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var folders = Loadable<[Folder]>()

    /// Suche über den ganzen Dateibereich der Veranstaltung: Ordner für
    /// Ordner, Datei für Datei - ab zwei Zeichen; jedes weitere würde sonst
    /// den Baum von neuem gehen.
    @State private var search = ""
    @State private var searchHits: [FileRef]?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var isSearchingList: Bool {
        search.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        List {
            if isSearchingList {
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Suche im Dateibereich…").font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // Ein Element statt zwei: Der Balken hat keinen eigenen
                    // Namen, der Text gehört zu ihm.
                    .accessibilityElement(children: .combine)
                }
                if let hits = searchHits ?? (isSearching ? nil : []) {
                    if hits.isEmpty {
                        Text("Nichts gefunden").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(hits) { file in
                            FileRow(file: file)
                        }
                    }
                }
            } else {
                ForEach(folders.value ?? []) { folder in
                    PushLink(value: folder) {
                        RowLabel(symbol: "folder",
                                 title: folder.name,
                                 subtitle: folder.summary,
                                 detail: folder.isEmpty ? "leer" : nil)
                    }
                }
            }
        }
        .overlay {
            StateOverlay(isLoading: folders.isLoading && !isSearchingList,
                         errorMessage: isSearchingList ? nil : folders.errorMessage,
                         isEmpty: (folders.value ?? []).isEmpty && !isSearchingList,
                         emptyText: "Keine Dateien freigegeben",
                         emptySymbol: "folder",
                         retry: { Task { await reload(fresh: true) } })
        }
        .searchable(text: $search, prompt: "Dateien suchen")
        .onChange(of: search) { term in
            runSearch(term)
        }
        .onSubmit(of: .search) { runSearch(search) }
        .navigationTitle("Dateien")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if folders.value == nil { await reload(fresh: false) } }
        // Der Kurskontext für die Dateizeilen: Offline behalten ordnet die
        // Kopie der Veranstaltung zu (siehe `courseContext`).
        .environment(\.courseContext, course)
    }

    /// Geht den Baum der Veranstaltung durch und sammelt, was den Suchtext
    /// im Namen trägt. Der vorherige Lauf wird abgebrochen - sonst stapelten
    /// sich die Suchen, während noch getippt wird.
    private func runSearch(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard term.count >= 2 else {
            searchHits = nil
            isSearching = false
            return
        }
        searchHits = nil
        isSearching = true
        let client = auth.client
        searchTask = Task {
            var hits: [FileRef] = []
            var stack: [Folder] = folders.value ?? []
            if stack.isEmpty {
                stack = (try? await client.rootFolders(of: course)) ?? []
            }
            while let current = stack.popLast() {
                if Task.isCancelled { return }
                let files = (try? await client.files(in: current)) ?? []
                hits += files.filter {
                    $0.name.localizedCaseInsensitiveContains(term)
                }
                stack += (try? await client.subfolders(of: current)) ?? []
            }
            guard !Task.isCancelled else { return }
            searchHits = hits.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            isSearching = false
        }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await folders.load { try await client.rootFolders(of: course) }
    }
}

/// Inhalt eines Ordners: Unterordner und Dateien.
///
/// Kann mehr als nur zeigen - hochladen, auswählen, mehrere auf einmal
/// sichern, umbenennen, löschen und Unterordner anlegen. Was davon angeboten
/// wird, entscheidet `is-writable` am Ordner: Stud.IP gibt das Attribut je
/// Ordnertyp heraus, und ein Knopf, der hinterher am Server scheitert, ist
/// schlimmer als gar keiner.
struct FolderContentView: View {
    let folder: Folder
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var subfolders = Loadable<[Folder]>()
    @StateObject private var files = Loadable<[FileRef]>()

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

    /// Ordner offline behalten: Der Vorbereitungslauf sammelt den Baum und
    /// fragt dann; der eigentliche Lauf lädt Datei für Datei und lässt sich
    /// abbrechen.
    @Environment(\.courseContext) private var course
    @State private var keepFolderTask: Task<Void, Never>?
    @State private var keepPlan: (files: [FileRef], size: Int)?

    /// Was gerade läuft - ein Zustand statt vier Boolescher.
    private enum TransferState: Equatable {
        case uploading(String)
        case downloading(done: Int, total: Int)
        case keeping(done: Int, total: Int)
        /// Sammelt den Ordner ein: Wie viel dahintersteckt, weiß erst dieser
        /// Lauf - der Balken zeigt das Prüfen, danach fragt ein Dialog.
        case collecting

        var text: String {
            switch self {
            case .uploading(let name): return String(localized: "\(name) wird hochgeladen…")
            case .downloading(let done, let total): return String(localized: "Lädt \(done) von \(total)…")
            case .keeping(let done, let total): return String(localized: "Behält \(done) von \(total) offline…")
            case .collecting: return String(localized: "Ordner wird geprüft…")
            }
        }

        /// Während „offline behalten“ gibt es ein Abbrechen - der Rest ist zu
        /// kurz, als dass sich der Knopf lohnte.
        var isCancellable: Bool {
            if case .keeping = self { return true }
            return false
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
                        Text(banner.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if banner.isCancellable {
                            Button {
                                keepFolderTask?.cancel()
                            } label: {
                                Text("Abbrechen").font(.footnote)
                            }
                            .accessibilityLabel("Offline behalten abbrechen")
                        }
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
                        // Beim Auswählen sind nur Dateien gemeint - ein Ordner
                        // ließe sich nicht mit sichern. (`selectionDisabled`
                        // gibt es erst ab iOS 17; ohne Berührung bleibt der
                        // Ordner im Auswahlmodus unangetippt.)
                        .allowsHitTesting(!isSelecting)
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
                            ? "Ordner ist leer, du kannst hier hochladen"
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
        .confirmationDialog("Ordner offline behalten?",
                            isPresented: .init(get: { keepPlan != nil },
                                               set: { if !$0 { keepPlan = nil } }),
                            titleVisibility: .visible) {
            Button("Offline behalten") {
                if let plan = keepPlan { Task { await keepFolder(plan.files) } }
                keepPlan = nil
            }
            Button("Abbrechen", role: .cancel) { keepPlan = nil }
        } message: {
            if let plan = keepPlan {
                Text(String(localized: "\(plan.files.count) Dateien (\(ByteCountFormatter.string(fromByteCount: Int64(plan.size), countStyle: .file))) werden heruntergeladen und bleiben ohne Empfang lesbar."))
            }
        }
        .refreshable { await reload(fresh: true) }
        .task { if files.value == nil { await reload(fresh: false) } }
    }

    // MARK: - Werkzeugleiste

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
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
                    Button {
                        Task { await collectFolder() }
                    } label: {
                        Label("Ordner offline behalten", systemImage: "internaldrive")
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

    // MARK: - Ordner offline behalten

    /// Der Vorbereitungslauf: Ordner samt Unterordnern einsammeln und
    /// zusammenzählen - erst dann steht fest, was der Dialog zur Größe sagt.
    private func collectFolder() async {
        transfer = .collecting
        defer { transfer = nil }
        let client = auth.client
        var collected: [FileRef] = []
        var stack: [Folder] = [folder]
        do {
            while let current = stack.popLast() {
                if Task.isCancelled { return }
                collected += try await client.files(in: current)
                stack += try await client.subfolders(of: current)
            }
        } catch {
            message = error.localizedDescription
            return
        }
        let unique = Dictionary(collected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let files = unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !files.isEmpty else {
            message = String(localized: "Keine Dateien in diesem Ordner.")
            return
        }
        // Die Größenangabe vorab: Stud.IP nennt sie je Datei; unbekannt
        // rechnet als nichts - die Warnung „0 MB“ wäre gelogen, aber der
        // Download merkt es ohnehin.
        keepPlan = (files, max(OfflineFiles.expectedSize(of: files), 1))
    }

    /// Der Lauf selbst: Datei für Datei behalten, mit Fortschritt und
    /// Abbruch. Was bei einem Abbruch schon liegt, bleibt - es ist ja
    /// gewollt gewesen; die Fehlermeldung am Ende sagt, was fehlte.
    private func keepFolder(_ files: [FileRef]) async {
        guard let course else {
            message = String(localized: "Datei konnte nicht zugeordnet werden.")
            return
        }
        let task = Task {
            var failed: [String] = []
            for (index, file) in files.enumerated() {
                transfer = .keeping(done: index, total: files.count)
                if Task.isCancelled { break }
                do {
                    try await OfflineStore.shared.keep(file, in: course,
                                                       client: auth.client,
                                                       alreadyLoaded: nil)
                } catch {
                    failed.append(file.name)
                }
            }
            transfer = nil
            if !failed.isEmpty {
                message = String(localized: "Nicht offline behalten: \(failed.joined(separator: ", "))")
            }
        }
        keepFolderTask = task
        await task.value
        keepFolderTask = nil
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
        await refreshOutdatedFiles(client: client)
    }

    /// Aktualisiert gehaltene Dateien, deren `chdate` sich am Server geändert
    /// hat - gescheiterte Versuche bleiben folgenlos, die alte Kopie bleibt
    /// ja lesbar. Das ist Gelegenheitsarbeit: Die Liste, die diesen Ordner
    /// ohnehin frisch lädt, liefert den Vergleichsstand mit.
    private func refreshOutdatedFiles(client: StudIPClient) async {
        guard let course, let list = files.value, !list.isEmpty else { return }
        let outdated = OfflineStore.shared.outdated(in: list)
        for file in outdated {
            try? await OfflineStore.shared.refresh(file, in: course, client: client)
        }
    }

    // MARK: - Hochladen

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            // Der Standardordner der Lizenzen der Installation - Stud.IP
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
                ? (urls.count == 1 ? String(localized: "Hochgeladen.") : String(localized: "\(urls.count) Dateien hochgeladen."))
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
    /// Dort steht „In Dateien sichern" - damit landen mehrere Anhänge in einem
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
            message = String(localized: "Nicht geladen: \(failed.joined(separator: ", "))")
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

    @EnvironmentObject private var auth: AuthStore
    /// Die Veranstaltung, zu deren Dateibereich diese Zeile gehört - über die
    /// Umgebung, weil die Zeile aus dem Navigationspfad kommt und ihr Kurs
    /// nicht mit auf den Weg nimmt.
    @Environment(\.courseContext) private var course
    @ObservedObject private var offline = OfflineStore.shared

    @State private var localURL: URL?
    @State private var isDownloading = false
    @State private var isKeepingOffline = false
    @State private var errorMessage: String?
    @State private var showsPreview = false
    @State private var showsShareSheet = false

    private var isKeptOffline: Bool { offline.contains(file) }

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
                if isDownloading || isKeepingOffline {
                    ProgressView()
                } else if isKeptOffline {
                    // Der Pfeil in den Speicher: Diese Datei übersteht das
                    // Wegräumen des Systems.
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Offline behalten")
                } else if localURL != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Heruntergeladen")
                }
            }
        }
        .buttonStyle(.plain)
        // Im Auswahlmodus darf ein Tipp nicht die Vorschau öffnen - dort
        // bedeutet er „ankreuzen".
        .disabled(isSelecting || !file.isDownloadable || isDownloading || isKeepingOffline)
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
            if file.isDownloadable {
                Button {
                    Task { await toggleOffline() }
                } label: {
                    if isKeptOffline {
                        Label("Nur offline entfernen", systemImage: "internaldrive.badge.xmark")
                    } else {
                        Label("Offline behalten", systemImage: "internaldrive")
                    }
                }
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
                            ToolbarItem(placement: .navigationBarTrailing) {
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
        // Offline behalten heißt: auch ohne Netz lesbar. Die lokale Kopie
        // geht vor jedem Download - nur wenn sie fehlt, fällt die Zeile auf
        // das gewöhnliche Laden zurück.
        if let keptURL = offline.localURL(for: file) {
            localURL = keptURL
            showsPreview = true
            return
        }
        guard await ensureDownloaded() else { return }
        showsPreview = true
    }

    private func share() async {
        if let keptURL = offline.localURL(for: file) {
            localURL = keptURL
        }
        guard await ensureDownloaded() else { return }
        showsShareSheet = true
    }

    /// Behält diese Datei offline - oder hebt das wieder auf.
    ///
    /// Ohne Kurskontext (nur rechnerisch erreichbar) zeigt die Zeile einen
    /// Fehler statt still zu versagen: Der Eintrag braucht die Veranstaltung
    /// für die Übersicht in den Einstellungen.
    private func toggleOffline() async {
        if isKeptOffline {
            offline.remove(file)
            return
        }
        guard let course else {
            errorMessage = String(localized: "Datei konnte nicht zugeordnet werden.")
            return
        }
        isKeepingOffline = true
        defer { isKeepingOffline = false }
        do {
            try await offline.keep(file, in: course, client: auth.client,
                                   alreadyLoaded: localURL)
        } catch {
            errorMessage = error.localizedDescription
        }
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

/// Der Kurskontext der Dateiansichten - über die Umgebung, weil der
/// Navigationspfad nur den Ordner trägt.
///
/// **Wofür das nötig ist:** Offline behaltene Dateien zählen in den
/// Einstellungen je Veranstaltung auf; die kennt nur der Wurzelordner, aus
/// dem der Weg begann. Die Umgebung wandert den Stapel hinunter, auch in
/// die Ziele, die aus `PushLink` entstehen.
private struct CourseContextKey: EnvironmentKey {
    static let defaultValue: Course? = nil
}

extension EnvironmentValues {
    var courseContext: Course? {
        get { self[CourseContextKey.self] }
        set { self[CourseContextKey.self] = newValue }
    }
}
