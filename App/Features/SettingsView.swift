import SwiftUI
import UIKit

/// Profil, Darstellung, Semesterübersicht und alles Rechtliche.
///
/// Erscheint als Blatt über „Heute" statt als eigener Reiter — ein fünfter
/// Reiter „Mehr" hätte den Platz gekostet, den jetzt „Campus" bekommt.
struct SettingsView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var showsSignOutConfirmation = false
    @State private var didClearCache = false
    @State private var webTarget: WebTarget?

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

                Section("Darstellung") {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        RowLabel(symbol: "paintpalette",
                                 title: "Farben & Erscheinungsbild",
                                 subtitle: ThemeStore.currentName)
                    }
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
                    Link(destination: StudIPClient.myCoursesURL) {
                        RowLabel(symbol: "rectangle.stack.badge.person.crop",
                                 title: "Veranstaltungen verwalten",
                                 subtitle: "Ein- und austragen in Stud.IP")
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
                    Button {
                        webTarget = WebTarget(url: AppConfig.webmailURL)
                    } label: {
                        RowLabel(symbol: "envelope",
                                 title: "Uni-Mail (SOGo)",
                                 subtitle: "Öffnet kalender.uni-hannover.de")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        MailSetupView()
                    } label: {
                        RowLabel(symbol: "gearshape.2",
                                 title: "Uni-Mail einrichten",
                                 subtitle: "Serverdaten für Apple Mail")
                    }
                } footer: {
                    // Warum StudGo kein eigener Mailclient ist, steht
                    // ausführlich in docs/SOGO-MAIL.md.
                    Text("Die Uni-Mail kennt nur Anmeldung per Passwort — weder IMAP noch SOGo bieten OAuth an. StudGo fragt deshalb grundsätzlich kein Uni-Passwort ab und verweist stattdessen auf SOGo und die Mail-App des Geräts.")
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
            .studGoDestinations()
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $webTarget) { target in
                WebSheet(url: target.url).ignoresSafeArea()
            }
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
                HStack(alignment: .top, spacing: 14) {
                    AppLogoView(size: 62, cornerRadius: 14)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("StudGo").font(.title3.bold())
                        Text("Ein quelloffenes Studierendenprojekt für Stud.IP an der Leibniz Universität Hannover. Keine offizielle App der Universität.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
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


/// Die Serverdaten der Uni-Mail zum Abtippen — mit Kopierknöpfen.
///
/// StudGo baut bewusst **keinen** eigenen Mailclient: Dovecot an der LUH
/// bietet nur `AUTH=PLAIN`, SOGos DAV-Endpunkt nur HTTP Basic. Ein
/// Posteingang in der App hieße, das zentrale Uni-Passwort abzufragen und
/// vorzuhalten — das widerspricht der Zusage, dass nur widerrufbare Tokens
/// auf dem Gerät liegen. Ausführlich in docs/SOGO-MAIL.md.
struct MailSetupView: View {
    private struct Entry: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private let incoming = [
        Entry(label: "Servertyp", value: "IMAP"),
        Entry(label: "Server", value: "mail.uni-hannover.de"),
        Entry(label: "Port", value: "993"),
        Entry(label: "Verschlüsselung", value: "SSL/TLS"),
    ]

    private let outgoing = [
        Entry(label: "Server", value: "smtp.uni-hannover.de"),
        Entry(label: "Port", value: "587"),
        Entry(label: "Verschlüsselung", value: "STARTTLS"),
    ]

    private let calendar = [
        Entry(label: "CalDAV / CardDAV", value: "kalender.uni-hannover.de"),
        Entry(label: "Pfad", value: "/SOGo/dav/"),
    ]

    var body: some View {
        List {
            Section {
                Text("Uni-Mail und Uni-Kalender laufen am besten in den Apps des Geräts: Einstellungen → Apps → Mail → Accounts → Account hinzufügen → Andere. Benutzername und Passwort sind die der zentralen LUH-Kennung.")
                    .font(.callout)
            }

            Section("Posteingang") { rows(incoming) }
            Section("Postausgang") { rows(outgoing) }

            Section {
                rows(calendar)
            } header: {
                Text("Kalender und Kontakte")
            } footer: {
                Text("Der Stundenplan aus Stud.IP steckt bereits in StudGo — diese Adresse ist für den persönlichen SOGo-Kalender gedacht.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Uni-Mail einrichten")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rows(_ entries: [Entry]) -> some View {
        ForEach(entries) { entry in
            HStack {
                Text(entry.label)
                Spacer(minLength: 8)
                Text(entry.value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = entry.value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("\(entry.label) kopieren")
            }
            .font(.callout)
        }
    }
}
