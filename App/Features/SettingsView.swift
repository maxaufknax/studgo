import SwiftUI
import UIKit

/// Profil, Darstellung, Semesterübersicht und alles Rechtliche.
///
/// Erscheint als Blatt über „Heute" statt als eigener Reiter — ein fünfter
/// Reiter „Mehr" hätte den Platz gekostet, den jetzt „Campus" bekommt.
struct SettingsView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var showsSignOutConfirmation = false
    @State private var didClearCache = false
    @State private var webTarget: WebTarget?
    /// Der Pfad dieses Blatts — siehe Kommentar an `NavigationStack` unten.
    @State private var navigator = Navigator()

    private var notificationSummary: String {
        var parts: [String] = []
        if preferences.eventReminders {
            parts.append(Preferences.leadLabel(preferences.leadMinutes))
        }
        if preferences.mailboxAlerts { parts.append("Postfach") }
        return parts.isEmpty ? "Aus" : parts.joined(separator: " · ")
    }

    /// Die anderen Systeme der LUH.
    ///
    /// Sie gehören nicht in die App, weil keines davon eine Schnittstelle hat
    /// — aber sie gehören in Reichweite: Wer die Prüfungsanmeldung sucht,
    /// sucht sie hier und nicht im Browserverlauf.
    private var quickLinks: some View {
        Section {
            linkRow("Prüfungen & Noten (QIS)", "checkmark.seal", WebLinks.qis,
                    hint: "Anmeldung, Notenspiegel, Bescheinigungen")
            linkRow("Account-Manager", "key", WebLinks.accountManager,
                    hint: "Kennwort, Mailweiterleitung, Dienste")
            linkRow("IT-Dienste (LUIS)", "server.rack", WebLinks.itServices)
            linkRow("Standortfinder", "map", WebLinks.campusMap,
                    hint: "Gebäude und Hörsäle auf dem Campus")
            linkRow("Mensa & Speiseplan", "fork.knife", WebLinks.canteen)
        } header: {
            Text("Schnellzugriff")
        } footer: {
            Text("Öffnet sich im eingebauten Browser. Prüfungsanmeldung und Noten laufen über QIS und nicht über Stud.IP — dafür gibt es keine Schnittstelle.")
        }
    }

    private func linkRow(_ title: String, _ symbol: String, _ url: URL,
                         hint: String? = nil) -> some View {
        Button {
            webTarget = WebTarget(url: url)
        } label: {
            RowLabel(symbol: symbol, title: title, subtitle: hint) {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Der Hinweis, der im Demo-Modus über allem steht.
    ///
    /// Er beantwortet die zwei Fragen, die sich sonst niemand von selbst
    /// beantworten kann: Woher kommen diese Daten, und wie komme ich hier
    /// wieder heraus.
    private var demoSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Demo-Modus").font(.headline)
                    Text("Alle Inhalte sind Beispieldaten und liegen nur auf diesem Gerät. Es besteht keine Verbindung zu Stud.IP.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button {
                showsSignOutConfirmation = true
            } label: {
                RowLabel(symbol: "person.crop.circle.badge.checkmark",
                         title: "Mit Stud.IP anmelden",
                         subtitle: "Verlässt die Demo")
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        // Ein **eigener** Navigator: Das Profil ist ein Blatt über dem Reiter
        // und führt seinen Stapel getrennt. Ohne ihn landeten Sprünge von
        // hier aus im Pfad des Reiters darunter — sichtbar würde davon
        // nichts, bis man das Blatt schliesst.
        NavigationStack(path: $navigator.path) {
            List {
                if auth.isDemo { demoSection }

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

                    // Ein Profilbild will zugeschnitten und beschnitten
                    // werden; die API kennt dafür überhaupt nichts
                    // (`Schemas/User` gibt die Adresse des Bildes heraus,
                    // mehr nicht). Der Weg dorthin ist ehrlicher als ein
                    // halbes Werkzeug.
                    Button {
                        webTarget = WebTarget(url: WebLinks.avatarSettings)
                    } label: {
                        RowLabel(symbol: "person.crop.circle.badge.plus",
                                 title: "Profilbild ändern",
                                 subtitle: "In Stud.IP") {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Darstellung") {
                    PushLink(value: Route.appearance) {
                        RowLabel(symbol: "paintpalette",
                                 title: "Farben & Erscheinungsbild",
                                 subtitle: ThemeStore.currentName)
                    }
                    PushLink(value: Route.notificationSettings) {
                        RowLabel(symbol: "bell.badge",
                                 title: "Benachrichtigungen",
                                 subtitle: notificationSummary)
                    }
                }

                quickLinks

                Section {
                    PushLink(value: Route.announcements) {
                        RowLabel(symbol: "megaphone", title: "Ankündigungen")
                    }
                    PushLink(value: Route.semesters) {
                        RowLabel(symbol: "calendar.badge.clock", title: "Semester")
                    }
                    Button {
                        webTarget = WebTarget(url: StudIPClient.myCoursesURL)
                    } label: {
                        RowLabel(symbol: "rectangle.stack.badge.person.crop",
                                 title: "Veranstaltungen verwalten",
                                 subtitle: "Ein- und austragen in Stud.IP")
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Toggle(isOn: Binding(get: { preferences.sharesWebSession },
                                         set: { preferences.sharesWebSession = $0 })) {
                        RowLabel(symbol: "person.badge.key",
                                 title: "Im Browser angemeldet bleiben")
                    }
                } footer: {
                    // Der Handel steht ausführlich in `Preferences`.
                    Text(preferences.sharesWebSession
                         ? "Die Anmeldung läuft in der Safari-Sitzung. Weil Stud.IP über Shibboleth anmeldet, bist du damit auch auf allen Seiten angemeldet, die StudGo öffnet — Eintragen, Profilbild, QIS. Wirkt ab der nächsten Anmeldung."
                         : "Die Anmeldung läuft in einer eigenen Sitzung: Es bleibt kein Cookie in Safari zurück, dafür verlangt jede geöffnete Stud.IP-Seite eine eigene Anmeldung. Wirkt ab der nächsten Anmeldung.")
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
                    PushLink(value: Route.mailSetup) {
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
                    PushLink(value: Route.about) {
                        RowLabel(symbol: "info.circle", title: "Über StudGo")
                    }
                    Button {
                        webTarget = WebTarget(url: WebLinks.studipHome)
                    } label: {
                        RowLabel(symbol: "safari", title: "Stud.IP im Browser öffnen")
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button(auth.isDemo ? "Demo verlassen" : "Abmelden", role: .destructive) {
                        showsSignOutConfirmation = true
                    }
                } footer: {
                    Text(auth.isDemo
                         ? "Führt zurück zur Anmeldung. Die Beispieldaten der Demo werden dabei verworfen."
                         : "Beim Abmelden werden die Zugangstoken aus der Keychain und alle zwischengespeicherten Daten gelöscht.")
                }
            }
            .listStyle(.insetGrouped)
            .studGoDestinations(user: user)
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
            .confirmationDialog(auth.isDemo ? "Demo verlassen?" : "Wirklich abmelden?",
                                isPresented: $showsSignOutConfirmation,
                                titleVisibility: .visible) {
                Button(auth.isDemo ? "Demo verlassen" : "Abmelden", role: .destructive) {
                    Task {
                        await Notifications.clearAll()
                        Notifications.cancelBackgroundRefresh()
                        auth.signOut()
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                if auth.isDemo {
                    Text("Die Beispieldaten werden verworfen und du landest wieder auf der Anmeldung.")
                } else {
                    Text(preferences.sharesWebSession
                         ? "Tokens und Zwischenspeicher werden gelöscht. Die Anmeldung im Browser bleibt bestehen — sie liegt bei Safari, nicht bei StudGo."
                         : "Tokens und Zwischenspeicher werden gelöscht.")
                }
            }
        }
        .environment(navigator)
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
                        Text("Ein quelloffenes Studierendenprojekt, das Stud.IP auf dem Telefon bedienbar macht. Keine offizielle App einer Hochschule.")
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
                Text("Uni-Mail und Uni-Kalender laufen am besten in den Apps des Geräts: Einstellungen → Apps → Mail → Accounts → Account hinzufügen → Andere. Benutzername und Passwort sind die der zentralen Uni-Kennung.")
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

/// Benachrichtigungen einstellen — und ehrlich sagen, was sie leisten.
///
/// StudGo hat **kein** Backend, also auch kein echtes Push (ausführlich in
/// `Notifications`). Was es gibt: Terminerinnerungen, die im Voraus auf dem
/// Gerät geplant werden und deshalb sogar ohne Netz kommen, und ein
/// Hintergrundlauf fürs Postfach, den iOS nach eigenem Ermessen weckt.
///
/// Die Ansicht verschweigt den Unterschied nicht. Eine Einstellung, die
/// „sofortige Benachrichtigung" verspricht und dann zwei Stunden braucht, ist
/// schlimmer als eine, die von vornherein sagt, woran man ist.
struct NotificationSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AuthStore.self) private var auth

    @State private var isAuthorized: Bool?
    @State private var pendingCount = 0

    var body: some View {
        @Bindable var preferences = preferences

        List {
            if isAuthorized == false {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Benachrichtigungen sind gesperrt", systemImage: "bell.slash")
                            .font(.subheadline.weight(.semibold))
                        Text("In den Einstellungen des Geräts unter „StudGo → Mitteilungen“ wieder erlauben.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Einstellungen öffnen", destination: url)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Toggle(isOn: $preferences.eventReminders) {
                    RowLabel(symbol: "clock.badge", title: "Vor Veranstaltungen erinnern")
                }
                if preferences.eventReminders {
                    Picker("Vorlauf", selection: $preferences.leadMinutes) {
                        ForEach(Preferences.leadOptions, id: \.self) { minutes in
                            Text(Preferences.leadLabel(minutes)).tag(minutes)
                        }
                    }
                }
            } header: {
                Text("Termine")
            } footer: {
                Text("Wird auf dem Gerät geplant und funktioniert auch ohne Empfang. Fällt eine Sitzung aus, verschwindet die Erinnerung beim nächsten Laden des Kalenders."
                     + (pendingCount > 0 ? " Zurzeit sind \(pendingCount) Erinnerungen vorgemerkt." : ""))
            }

            Section {
                Toggle(isOn: $preferences.mailboxAlerts) {
                    RowLabel(symbol: "tray.full", title: "Neue Nachrichten und Beiträge")
                }
                Toggle(isOn: $preferences.quietWeekend) {
                    RowLabel(symbol: "moon.zzz", title: "Am Wochenende still bleiben")
                }
                .disabled(!preferences.wantsNotifications)
            } header: {
                Text("Postfach")
            } footer: {
                Text("StudGo hat keinen eigenen Server: Es fragt bei Stud.IP nach, wenn iOS die App im Hintergrund weckt — typisch einige Male am Tag, nicht in Echtzeit. Für ein Gespräch, in dem du auf Antwort wartest, ist der Chat in der App der schnellere Weg.")
            }

            Section {
                Button {
                    webTarget = WebTarget(url: WebLinks.notificationSettings)
                } label: {
                    RowLabel(symbol: "envelope.badge",
                             title: "Stud.IPs eigene Benachrichtigungen",
                             subtitle: "Was per E-Mail herausgeht")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Stud.IP verschickt unabhängig von StudGo E-Mails. Was davon kommt, steht in den Einstellungen der Weboberfläche.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url).ignoresSafeArea()
        }
        .task { await refreshStatus() }
        .onChange(of: preferences.eventReminders) { _, isOn in
            Task { await apply(remindersEnabled: isOn) }
        }
        .onChange(of: preferences.leadMinutes) {
            Task { await apply(remindersEnabled: preferences.eventReminders) }
        }
        .onChange(of: preferences.mailboxAlerts) { _, isOn in
            Task { await apply(mailboxEnabled: isOn) }
        }
    }

    @State private var webTarget: WebTarget?

    private func refreshStatus() async {
        isAuthorized = await Notifications.isAuthorized()
        pendingCount = await Notifications.pendingReminderCount()
    }

    /// Beim Einschalten erst nach der Erlaubnis fragen — und den Schalter
    /// wieder zurückstellen, wenn sie verweigert wird. Ein Schalter, der an
    /// bleibt, ohne dass je etwas ankommt, ist eine Lüge.
    private func apply(remindersEnabled: Bool) async {
        if remindersEnabled {
            guard await ensureAuthorization() else {
                preferences.eventReminders = false
                return
            }
            // Sofort planen, nicht erst beim nächsten Öffnen von „Heute" —
            // sonst schaltet man es ein und es tut sichtbar nichts.
            await scheduleNow()
        } else {
            await Notifications.clearEventReminders()
        }
        await refreshStatus()
    }

    /// Holt den Kalender und legt die Erinnerungen gleich an. Der ICS-Strom
    /// ist die verlässliche Quelle (echte Sitzungen samt Ausfällen); klappt er
    /// nicht, tut es die kurze Terminliste auch.
    private func scheduleNow() async {
        guard preferences.eventReminders, let userID = auth.currentUserID else { return }
        // Zwei getrennte `await`, nicht in einer `??`-Kette: Der rechte Operand
        // von `??` ist ein nicht-nebenläufiger Autoclosure — ein `await` darin
        // lehnt der Compiler ab. Der ICS-Strom ist die verlässliche Quelle;
        // bleibt er leer, tut es die kurze Terminliste auch.
        var events = (try? await auth.client.calendarEvents(for: userID)) ?? []
        if events.isEmpty {
            events = (try? await auth.client.events(for: userID, weeks: 4)) ?? []
        }
        await Notifications.scheduleEventReminders(events,
                                                   leadMinutes: preferences.leadMinutes,
                                                   quietWeekend: preferences.quietWeekend)
    }

    private func apply(mailboxEnabled: Bool) async {
        if mailboxEnabled {
            guard await ensureAuthorization() else {
                preferences.mailboxAlerts = false
                return
            }
            Notifications.scheduleBackgroundRefresh()
        } else {
            Notifications.cancelBackgroundRefresh()
        }
        await refreshStatus()
    }

    private func ensureAuthorization() async -> Bool {
        if await Notifications.isAuthorized() { return true }
        let granted = await Notifications.requestAuthorization()
        isAuthorized = granted
        return granted
    }
}
