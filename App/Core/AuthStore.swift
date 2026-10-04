import Combine
import Foundation

/// Hält den Anmeldezustand der App und erneuert Tokens bei Bedarf.
@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(StudIPUser)
        /// Angemeldet, aber das Profil ist gerade nicht erreichbar - etwa
        /// beim ersten Start ohne Netz. Kein Grund, die Sitzung wegzuwerfen.
        case unavailable(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false

    /// **Demo-Modus** - die App läuft an erfundenen Daten statt an Stud.IP.
    ///
    /// Er ist der einzige Weg, StudGo ohne Kennung der Leibniz Universität
    /// überhaupt zu sehen: Die Anmeldung läuft über Shibboleth, und ein
    /// dauerhaft gültiges Prüfkonto beim Rechenzentrum gibt es nicht. Wer
    /// die Demo betritt, bekommt denselben Funktionsumfang; nur die Antworten
    /// kommen aus `DemoServer` statt aus dem Netz. Siehe `DemoData`.
    @Published private(set) var isDemo = false

    /// Merkt den Demo-Modus über einen Neustart hinweg - sonst stünde beim
    /// nächsten Öffnen wieder die Anmeldung da, ohne dass jemand sich
    /// abgemeldet hätte.
    private static let demoKey = "studgo.demo.active"

    /// Zahl der ungelesenen Nachrichten für das Kennzeichen am Tab. Wird von
    /// den Ansichten gemeldet, die das Postfach ohnehin laden - ein eigener
    /// Abruf nur für die Ziffer wäre eine Anfrage zu viel.
    @Published private(set) var unreadCount = 0

    /// Klartext zu `course-type`. Einmal geholt, dann für die ganze Laufzeit
    /// gültig - die Veranstaltungsarten ändern sich nicht im Semester.
    @Published private(set) var semTypes: [String: String] = [:]

    /// Welche Veranstaltungsarten in dieser Installation Studiengruppen sind.
    /// Steht in keinem Schema und wird deshalb abgeleitet - siehe
    /// `StudygroupKinds`.
    @Published private(set) var studygroupKinds: StudygroupKinds = .unknown

    private let oauth = OAuthService()
    private var tokens: TokenSet?

    /// **Passiv** heißt: Diese Instanz liest und erneuert Tokens, beendet aber
    /// nie eine Sitzung - kein Leeren der Keychain, kein Abmelden.
    ///
    /// So läuft der Hintergrundlauf (`BackgroundSync`). Er baut sich eine
    /// eigene Instanz, weil iOS die App dafür auch kalt starten kann. Bis
    /// 1.8.1 durfte diese Instanz abmelden: Antwortete Stud.IP nachts mit 503,
    /// stand morgens die Anmeldung da. Ob eine Sitzung vorbei ist, entscheidet
    /// jetzt allein die Oberfläche - mit der Person davor, die es erfährt.
    let isPassive: Bool

    init(passive: Bool = false) {
        isPassive = passive
    }

    // MARK: - Gemeinsamer Stand aller Instanzen

    /// Die laufende Erneuerung - **für alle Instanzen gemeinsam**, nicht je
    /// Instanz.
    ///
    /// Stud.IP rotiert Refresh-Tokens: Wer erneuert, macht den alten Token
    /// (und den alten Access-Token) ungültig. Erneuerten Oberfläche und
    /// Hintergrundlauf unabhängig voneinander, verbrauchte der eine den
    /// Token des anderen - und der Verlierer hielt eine Ablehnung für das
    /// Ende der Sitzung. Beide laufen auf dem Hauptaktor; ein gemeinsamer
    /// Merker genügt, damit pro Refresh-Token nur eine Anfrage hinausgeht.
    private static var runningRefresh: (refreshToken: String, task: Task<TokenSet, Error>)?

    /// Zählt jede beendete Sitzung. Eine Erneuerung, die über ein Abmelden
    /// hinweg lief, darf ihr Ergebnis nicht mehr in die Keychain schreiben -
    /// sonst wäre nach dem Abmelden beim nächsten Start wieder jemand
    /// angemeldet.
    private static var sessionGeneration = 0

    /// Liest bevorzugt aus dem Zwischenspeicher - für den ersten Aufbau
    /// einer Ansicht.
    var client: StudIPClient {
        var client = StudIPClient(
            tokenProvider: { [weak self] in
                guard let self else { throw AuthError.notAuthenticated }
                return try await self.validAccessToken()
            },
            onUnauthorized: { [weak self] rejected, isRetry in
                guard let self else { return nil }
                return try await self.recoverAuthorization(rejected: rejected, isRetry: isRetry)
            }
        )
        client.isDemo = isDemo
        return client
    }

    /// Fragt in jedem Fall den Server - für „nach unten ziehen" und nach
    /// jedem schreibenden Aufruf.
    var freshClient: StudIPClient { client.fresh }

    /// Zählt hoch, sobald sich am Postfach etwas geändert hat - gelesen
    /// markiert, gesendet, gelöscht. Die Listenansichten hängen daran und
    /// laden nach.
    ///
    /// **Warum nicht über einen Rückruf am Ziel:** Die Detailseite wird
    /// zentral angemeldet (`studGoDestinations`), damit im selben Stapel nicht
    /// zwei Anmeldungen desselben Typs liegen. Sie kennt die Liste, aus der
    /// sie geöffnet wurde, deshalb nicht mehr.
    @Published private(set) var mailboxRevision = 0

    func noteUnread(_ count: Int) {
        unreadCount = count
    }

    func noteMailboxChanged() {
        mailboxRevision &+= 1
    }

    /// Die eigene Nutzer-ID, sofern angemeldet. Der Blubber-Verlauf braucht
    /// sie, um eigene Beiträge von fremden zu unterscheiden.
    var currentUserID: String? {
        if case .signedIn(let user) = state { return user.id }
        return nil
    }

    func courseTypeName(_ id: Int?) -> String? {
        guard let id else { return nil }
        return semTypes[String(id)]?.nilIfEmpty
    }

    /// Beim App-Start: gespeichertes Token laden und den Nutzer holen.
    func restore() async {
        if UserDefaults.standard.bool(forKey: Self.demoKey) {
            // Der Hintergrundlauf hat in der Demo nichts zu tun - und
            // `enterDemo` räumt Zwischenspeicher und Demo-Stand ab, was er
            // der offenen Oberfläche nicht antun darf.
            if isPassive {
                state = .signedOut
                return
            }
            await enterDemo()
            return
        }
        guard let stored = KeychainStore.load() else {
            state = .signedOut
            return
        }
        tokens = stored
        do {
            state = .signedIn(try await client.currentUser())
        } catch let error as APIError where error.isUnauthorized {
            // Auch der Wiederholungsversuch des Clients (siehe
            // `recoverAuthorization`) wurde abgewiesen - die Sitzung ist hin.
            endSession()
        } catch let error as AuthError where error.endsSession {
            // Der Refresh-Token wurde ausdrücklich abgelehnt.
            endSession()
        } catch {
            // Funkloch, Wartung, Überlast (auch ein 503 beim Erneuern): Die
            // Sitzung bleibt. Abmelden hieße, dass jede Störung auf Seiten von
            // Stud.IP die Person aus der App wirft - genau das passierte bis
            // 1.8.1 am Semesterstart.
            state = .unavailable(error.localizedDescription)
        }
    }

    func signIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let newTokens = try await oauth.authenticate()
            try KeychainStore.save(newTokens)
            tokens = newTokens
            // Ein voriges Konto darf auf diesem Gerät nichts hinterlassen.
            ResponseCache.clear()
            state = .signedIn(try await freshClient.currentUser())
        } catch AuthError.cancelled {
            // Bewusster Abbruch durch den Nutzer, keine Fehlermeldung.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        discardSession()
    }

    // MARK: - Demo

    /// Die Demo betreten - ohne Anmeldung, ohne Netz.
    func signInDemo() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        // Ein voriges Konto darf in der Demo nicht durchscheinen, und
        // umgekehrt dürfen die erfundenen Antworten später nicht als echte
        // gelten: Der Zwischenspeicher wird an beiden Übergängen geleert.
        KeychainStore.clear()
        tokens = nil
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        await enterDemo()
    }

    private func enterDemo() async {
        ResponseCache.clear()
        DemoStore.shared.reset()
        isDemo = true
        semTypes = [:]
        studygroupKinds = .unknown
        unreadCount = 0
        // Widgets zeigen Beispieldaten im Demo-Modus - aber erst, wenn „Heute“
        // sie geschrieben hat. Der Stand des vorigen echten Kontos weg damit.
        WidgetBridge.clear()
        do {
            state = .signedIn(try await client.currentUser())
        } catch {
            // Kann eigentlich nicht scheitern - die Antwort kommt aus der
            // App selbst. Bliebe es doch einmal hängen, ist die Anmeldung
            // der richtige Ort, nicht ein leerer Bildschirm.
            isDemo = false
            UserDefaults.standard.set(false, forKey: Self.demoKey)
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    /// Nach `.unavailable` erneut versuchen, ohne sich neu anzumelden.
    func retryProfile() async {
        guard case .unavailable = state else { return }
        state = .loading
        await restore()
    }

    /// Lädt die Veranstaltungsarten nach und leitet daraus ab, was in dieser
    /// Installation eine Studiengruppe ist. Fehlschlag ist folgenlos - dann
    /// bleibt bei den Kursen eben die Art unbeschriftet.
    func loadSemTypes() async {
        guard semTypes.isEmpty else { return }
        guard let types = try? await client.semTypes() else { return }
        semTypes = Dictionary(types.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        // Ein paar Vorschläge genügen als Stichprobe: Was `/studygroup-proposals`
        // liefert, ist per Konstruktion eine Studiengruppe, und über die
        // Klassenzuordnung der Arten ergibt sich der Rest.
        let proposals = (try? await client.studygroupProposals(limit: 8)) ?? []
        let kinds = StudygroupKinds(proposals: proposals, semTypes: types)
        if kinds.isKnown { studygroupKinds = kinds }
    }

    // MARK: - Sitzung

    /// Beendet die Sitzung, weil Stud.IP sie nicht mehr anerkennt.
    ///
    /// Eine passive Instanz (der Hintergrundlauf) vergisst nur ihren eigenen
    /// Stand: Ob wirklich abgemeldet wird, entscheidet die Oberfläche beim
    /// nächsten Start - sie fragt dann selbst bei Stud.IP nach.
    private func endSession(message: String? = nil) {
        guard !isPassive else {
            tokens = nil
            state = .signedOut
            return
        }
        discardSession()
        if let message { errorMessage = message }
    }

    private func discardSession() {
        Self.sessionGeneration &+= 1
        KeychainStore.clear()
        ResponseCache.clear()
        if isDemo {
            DemoStore.shared.reset()
            isDemo = false
            UserDefaults.standard.set(false, forKey: Self.demoKey)
        }
        tokens = nil
        semTypes = [:]
        studygroupKinds = .unknown
        unreadCount = 0
        mailboxRevision = 0
        // Was auf dem Sperrbildschirm steht, darf das nächste Konto nicht
        // sehen: Widgets zeigen Termine und Nachrichten des bisherigen.
        WidgetBridge.clear()
        // Dasselbe gilt für den Kalender „StudGo“ im Systemkalender.
        CalendarSync.removeCalendar()
        state = .signedOut
    }

    private static var expiredMessage: String {
        String(localized: "Die Sitzung ist abgelaufen. Bitte melde dich erneut an.")
    }

    // MARK: - Token-Lebenszyklus

    private func validAccessToken() async throws -> String {
        // Im Demo-Modus fragt niemand einen Server - der Wert wird nie
        // verschickt, nur der Aufruf muss durchgehen.
        if isDemo { return "demo" }
        guard let current = tokens else { throw AuthError.notAuthenticated }
        guard current.isExpired else { return current.accessToken }
        // Bevor erneuert wird: Hat das ein anderer Lauf schon getan?
        adoptStoredTokens()
        guard let latest = tokens else { throw AuthError.notAuthenticated }
        guard latest.isExpired else { return latest.accessToken }
        return try await refreshed(from: latest).accessToken
    }

    /// Die Keychain ist die gemeinsame Wahrheit aller Instanzen.
    ///
    /// Hat der Hintergrundlauf inzwischen erneuert, liegt dort ein neuerer
    /// Stand als im Speicher dieser Instanz - und der alte ist bei Stud.IP
    /// schon zurückgezogen. Gelesen wird nur an den zwei Stellen, an denen
    /// das zählt: vor einem Erneuern und nach einem 401. Jede Anfrage einzeln
    /// abzugleichen kostete einen Keychain-Zugriff auf dem Hauptthread, ohne
    /// einen Fall mehr abzudecken. Nach dem Abmelden ist `tokens` leer; dann
    /// wird nichts übernommen.
    private func adoptStoredTokens() {
        guard tokens != nil, let stored = KeychainStore.load(), stored != tokens else { return }
        tokens = stored
    }

    /// Erneuert den Token - höchstens eine Anfrage je Refresh-Token, egal wie
    /// viele Instanzen und Anfragen gleichzeitig danach verlangen.
    private func refreshed(from current: TokenSet) async throws -> TokenSet {
        guard let refreshToken = current.refreshToken else {
            if !isPassive { endSession(message: Self.expiredMessage) }
            throw AuthError.notAuthenticated
        }

        let task: Task<TokenSet, Error>
        let startedHere: Bool
        if let running = Self.runningRefresh, running.refreshToken == refreshToken {
            task = running.task
            startedHere = false
        } else {
            let oauth = self.oauth
            task = Task { try await oauth.refresh(using: refreshToken) }
            Self.runningRefresh = (refreshToken, task)
            startedHere = true
        }
        let generation = Self.sessionGeneration

        do {
            let result = try await task.value
            if startedHere, Self.runningRefresh?.refreshToken == refreshToken {
                Self.runningRefresh = nil
            }
            // Zwischendurch abgemeldet? Dann gehört das Ergebnis niemandem mehr.
            guard generation == Self.sessionGeneration else { throw AuthError.notAuthenticated }
            if startedHere { try KeychainStore.save(result) }
            tokens = result
            return result
        } catch let error as AuthError where error.endsSession {
            if startedHere, Self.runningRefresh?.refreshToken == refreshToken {
                Self.runningRefresh = nil
            }
            // Hat ein anderer Lauf schon erneuert, ist dieser Refresh-Token zu
            // Recht verbraucht - dann gilt dessen Ergebnis, nicht die Ablehnung.
            if generation == Self.sessionGeneration,
               let stored = KeychainStore.load(), stored.refreshToken != refreshToken {
                tokens = stored
                if stored.isExpired { return try await refreshed(from: stored) }
                return stored
            }
            if case .rejected = error { endSession(message: Self.expiredMessage) }
            throw error
        } catch {
            if startedHere, Self.runningRefresh?.refreshToken == refreshToken {
                Self.runningRefresh = nil
            }
            // Vorübergehend (Netz, Wartung): Die Sitzung bleibt bestehen.
            throw error
        }
    }

    /// Stud.IP hat eine Anfrage mit 401 abgewiesen. Gibt es einen anderen
    /// Token, mit dem sich ein zweiter Versuch lohnt?
    ///
    /// * Liegt inzwischen ein anderer vor - erneuert vom Hintergrundlauf oder
    ///   einer parallelen Anfrage -, gilt der.
    /// * Sonst wurde genau dieser Token zurückgezogen, obwohl er noch frisch
    ///   schien (etwa weil die Uhr des Geräts falsch geht): einmal erneuern.
    /// * Scheitert auch der zweite Versuch, ist die Sitzung vorbei.
    private func recoverAuthorization(rejected: String, isRetry: Bool) async throws -> String? {
        if isDemo { return nil }
        guard !isRetry else {
            endSession(message: Self.expiredMessage)
            return nil
        }
        adoptStoredTokens()
        guard let current = tokens else { return nil }
        if current.accessToken != rejected {
            return try await validAccessToken()
        }
        do {
            return try await refreshed(from: current).accessToken
        } catch let error as AuthError where error.endsSession {
            // `refreshed` hat die Sitzung bereits beendet.
            return nil
        }
    }
}
