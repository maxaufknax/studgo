import SwiftUI

/// Profil, Ankündigungen, Semesterübersicht und alles Rechtliche.
struct MoreView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth
    @State private var showsSignOutConfirmation = false
    @State private var didClearCache = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        InitialsBadge(initials: user.initials, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.formattedName).font(.headline)
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    NavigationLink {
                        NewsView(user: user)
                    } label: {
                        RowLabel(symbol: "megaphone", title: "Ankündigungen")
                    }
                    NavigationLink {
                        SemesterListView()
                    } label: {
                        RowLabel(symbol: "calendar.badge.clock", title: "Semester")
                    }
                }

                Section("Konto") {
                    if let email = user.email {
                        LabeledContent("E-Mail", value: email)
                    }
                    LabeledContent("Server", value: AppConfig.baseURL.host() ?? "")
                }

                Section {
                    Button {
                        ResponseCache.clear()
                        didClearCache = true
                    } label: {
                        RowLabel(symbol: didClearCache ? "checkmark.circle" : "arrow.clockwise.circle",
                                 title: didClearCache ? "Zwischenspeicher geleert" : "Zwischenspeicher leeren")
                    }
                    .disabled(didClearCache)
                } footer: {
                    Text("StudGo hält die zuletzt geladenen Listen auf dem Gerät vor, damit die App sofort startet und auch ohne Empfang etwas anzeigt.")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        RowLabel(symbol: "info.circle", title: "Über StudGo")
                    }
                    Link(destination: AppConfig.baseURL) {
                        RowLabel(symbol: "safari", title: "Stud.IP im Browser öffnen")
                    }
                }

                Section {
                    Button("Abmelden", role: .destructive) {
                        showsSignOutConfirmation = true
                    }
                } footer: {
                    Text("Beim Abmelden werden die Zugangstoken aus der Keychain und alle zwischengespeicherten Daten gelöscht.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mehr")
            .confirmationDialog("Wirklich abmelden?",
                                isPresented: $showsSignOutConfirmation,
                                titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { auth.signOut() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}

struct SemesterListView: View {
    @Environment(AuthStore.self) private var auth
    @State private var semesters = Loadable<[Semester]>()

    private var sorted: [Semester] {
        (semesters.value ?? []).sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    var body: some View {
        List(sorted) { semester in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(semester.title).font(.subheadline.weight(.medium))
                    if semester.isCurrent {
                        Chip(text: "aktuell", color: .accentColor)
                    }
                    if semester.isLecturePeriod {
                        Chip(text: "Vorlesungszeit", symbol: "book", color: .green)
                    }
                }
                if let start = semester.start, let end = semester.end {
                    Text("\(start.formatted(.dateTime.day().month().year())) – \(end.formatted(.dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let from = semester.lectureStart, let to = semester.lectureEnd {
                    Text("Vorlesungen: \(from.formatted(.dateTime.day().month())) – \(to.formatted(.dateTime.day().month()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.insetGrouped)
        .overlay {
            StateOverlay(isLoading: semesters.isLoading,
                         errorMessage: semesters.errorMessage,
                         isEmpty: sorted.isEmpty,
                         emptyText: "Keine Semester",
                         emptySymbol: "calendar",
                         retry: { Task { await reload(fresh: true) } })
        }
        .navigationTitle("Semester")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload(fresh: true) }
        .task { if semesters.value == nil { await reload(fresh: false) } }
    }

    private func reload(fresh: Bool) async {
        let client = fresh ? auth.freshClient : auth.client
        await semesters.load { try await client.semesters() }
    }
}

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("StudGo").font(.title2.bold())
                    Text("Ein quelloffenes Studierendenprojekt für Stud.IP an der Leibniz Universität Hannover. Keine offizielle App der Universität.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Datenschutz") {
                Text("StudGo hat kein eigenes Backend. Die App spricht ausschließlich direkt mit \(AppConfig.baseURL.host() ?? "dem Uni-Server"). Zugangstoken liegen in der Keychain dieses Geräts, zwischengespeicherte Listen und heruntergeladene Dateien im App-eigenen Bereich. Es werden keine Daten an Dritte übertragen und keine Analyse- oder Tracking-Dienste eingesetzt.")
                    .font(.callout)
            }

            Section("Version") {
                LabeledContent("App", value: version)
                LabeledContent("Stud.IP", value: "JSON:API v1")
            }

            Section("Projekt") {
                Link(destination: URL(string: "https://github.com/maxaufknax/studgo")!) {
                    RowLabel(symbol: "chevron.left.forwardslash.chevron.right", title: "Quellcode auf GitHub")
                }
                Link(destination: URL(string: "https://maxpaasch.com")!) {
                    RowLabel(symbol: "person.crop.square", title: "Entwickler")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Über StudGo")
        .navigationBarTitleDisplayMode(.inline)
    }
}
