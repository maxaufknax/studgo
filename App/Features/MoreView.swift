import SwiftUI

/// Profil, Ankündigungen, Semesterübersicht und alles Rechtliche.
struct MoreView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth
    @State private var showsSignOutConfirmation = false

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
                    Text("Beim Abmelden werden die lokal gespeicherten Zugangstoken aus der Keychain gelöscht.")
                }
            }
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
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(semester.title).font(.body.weight(.medium))
                    if semester.isCurrent {
                        Text("aktuell")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.tint.opacity(0.15)))
                            .foregroundStyle(.tint)
                    }
                }
                if let start = semester.start, let end = semester.end {
                    Text("\(start.formatted(.dateTime.day().month().year())) – \(end.formatted(.dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            StateOverlay(isLoading: semesters.isLoading,
                         errorMessage: semesters.errorMessage,
                         isEmpty: sorted.isEmpty,
                         emptyText: "Keine Semester",
                         emptySymbol: "calendar",
                         retry: { Task { await reload() } })
        }
        .navigationTitle("Semester")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if semesters.value == nil { await reload() } }
    }

    private func reload() async {
        let client = auth.client
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
                Text("StudGo hat kein eigenes Backend. Die App spricht ausschließlich direkt mit \(AppConfig.baseURL.host() ?? "dem Uni-Server"). Zugangstoken liegen in der Keychain dieses Geräts, heruntergeladene Dateien im temporären Bereich der App. Es werden keine Daten an Dritte übertragen und keine Analyse- oder Tracking-Dienste eingesetzt.")
                    .font(.callout)
            }

            Section("Version") {
                LabeledContent("App", value: version)
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
        .navigationTitle("Über StudGo")
        .navigationBarTitleDisplayMode(.inline)
    }
}
