import SwiftUI

/// Dateibereich einer Veranstaltung. Die Ordner werden erst beim Öffnen
/// nachgeladen — Stud.IP liefert Struktur und Inhalt getrennt.
struct FolderBrowserView: View {
    let course: Course
    @Environment(AuthStore.self) private var auth

    @State private var folders = Loadable<[Folder]>()

    var body: some View {
        List(folders.value ?? []) { folder in
            NavigationLink {
                FolderContentView(folder: folder)
            } label: {
                RowLabel(symbol: "folder",
                         title: folder.name,
                         subtitle: folder.description,
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
        .refreshable { await reload(fresh: true) }
        .task { if folders.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await folders.load { try await client.rootFolders(of: course) }
    }
}

/// Inhalt eines Ordners: Unterordner und Dateien in einer Liste.
struct FolderContentView: View {
    let folder: Folder
    @Environment(AuthStore.self) private var auth

    @State private var subfolders = Loadable<[Folder]>()
    @State private var files = Loadable<[FileRef]>()

    private var isEmpty: Bool {
        (subfolders.value ?? []).isEmpty && (files.value ?? []).isEmpty
    }

    var body: some View {
        List {
            if let items = subfolders.value, !items.isEmpty {
                Section("Ordner") {
                    ForEach(items) { child in
                        NavigationLink {
                            FolderContentView(folder: child)
                        } label: {
                            RowLabel(symbol: "folder",
                                     title: child.name,
                                     detail: child.isEmpty ? "leer" : nil)
                        }
                    }
                }
            }

            if let items = files.value, !items.isEmpty {
                Section("Dateien") {
                    ForEach(items) { FileRow(file: $0) }
                }
            }
        }
        .overlay {
            StateOverlay(isLoading: files.isLoading || subfolders.isLoading,
                         errorMessage: files.errorMessage ?? subfolders.errorMessage,
                         isEmpty: isEmpty,
                         emptyText: "Ordner ist leer",
                         emptySymbol: "folder",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if files.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        async let children: Void = subfolders.load { try await client.subfolders(of: folder) }
        async let contents: Void = files.load { try await client.files(in: folder) }
        _ = await (children, contents)
    }
}

/// Einzelne Datei: antippen lädt herunter und öffnet die Systemvorschau.
struct FileRow: View {
    let file: FileRef
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
        .disabled(!file.isDownloadable || isDownloading)
        .swipeActions(edge: .trailing) {
            if localURL != nil {
                Button {
                    showsShareSheet = true
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)
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
        // Einmal geladene Dateien direkt wieder anzeigen.
        if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
            showsPreview = true
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            localURL = try await auth.client.download(file)
            showsPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
