import Foundation
import Observation

/// Hält den Anmeldezustand der App und erneuert Tokens bei Bedarf.
@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(StudIPUser)
        /// Angemeldet, aber das Profil ist gerade nicht erreichbar — etwa
        /// beim ersten Start ohne Netz. Kein Grund, die Sitzung wegzuwerfen.
        case unavailable(String)
    }

    private(set) var state: State = .loading
    private(set) var errorMessage: String?
    private(set) var isWorking = false

    /// Zahl der ungelesenen Nachrichten für das Kennzeichen am Tab. Wird von
    /// den Ansichten gemeldet, die das Postfach ohnehin laden — ein eigener
    /// Abruf nur für die Ziffer wäre eine Anfrage zu viel.
    private(set) var unreadCount = 0

    /// Klartext zu `course-type`. Einmal geholt, dann für die ganze Laufzeit
    /// gültig — die Veranstaltungsarten ändern sich nicht im Semester.
    private(set) var semTypes: [String: String] = [:]

    private let oauth = OAuthService()
    private var tokens: TokenSet?
    /// Verhindert, dass mehrere parallele Requests gleichzeitig refreshen.
    private var refreshTask: Task<TokenSet, Error>?

    /// Liest bevorzugt aus dem Zwischenspeicher — für den ersten Aufbau
    /// einer Ansicht.
    var client: StudIPClient {
        StudIPClient(
            tokenProvider: { [weak self] in
                guard let self else { throw AuthError.notAuthenticated }
                return try await self.validAccessToken()
            },
            onUnauthorized: { [weak self] in
                // Kein `await`: Die Closure entsteht im MainActor-Kontext
                // dieser Klasse und ist damit selbst schon isoliert — ein
                // Sprung findet gar nicht statt.
                self?.sessionExpired()
            }
        )
    }

    /// Fragt in jedem Fall den Server — für „nach unten ziehen" und nach
    /// jedem schreibenden Aufruf.
    var freshClient: StudIPClient { client.fresh }

    func noteUnread(_ count: Int) {
        unreadCount = count
    }

    func courseTypeName(_ id: Int?) -> String? {
        guard let id else { return nil }
        return semTypes[String(id)]?.nilIfEmpty
    }

    /// Beim App-Start: gespeichertes Token laden und den Nutzer holen.
    func restore() async {
        guard let stored = KeychainStore.load() else {
            state = .signedOut
            return
        }
        tokens = stored
        do {
            state = .signedIn(try await client.currentUser())
        } catch let error as APIError where error.isUnauthorized {
            // Nur hier ist die Sitzung wirklich hinüber.
            discardSession()
        } catch is AuthError {
            // Refresh-Token abgelaufen oder zurückgezogen.
            discardSession()
        } catch {
            // Netzproblem: Sitzung behalten, sonst wirft ein Funkloch den
            // Nutzer aus der App und er müsste sich neu anmelden.
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

    /// Nach `.unavailable` erneut versuchen, ohne sich neu anzumelden.
    func retryProfile() async {
        guard case .unavailable = state else { return }
        state = .loading
        await restore()
    }

    /// Lädt die Veranstaltungsarten nach. Fehlschlag ist folgenlos — dann
    /// bleibt bei den Kursen eben die Art unbeschriftet.
    func loadSemTypes() async {
        guard semTypes.isEmpty else { return }
        guard let types = try? await client.semTypes() else { return }
        semTypes = Dictionary(types.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Sitzung

    private func discardSession() {
        KeychainStore.clear()
        ResponseCache.clear()
        tokens = nil
        refreshTask = nil
        semTypes = [:]
        unreadCount = 0
        state = .signedOut
    }

    /// Der Server hat ein 401 geschickt, obwohl der Token frisch schien —
    /// er wurde also serverseitig zurückgezogen. Ohne diesen Schritt bliebe
    /// die App in jedem Tab mit derselben Fehlermeldung stehen, ohne dass
    /// der Weg zurück zur Anmeldung erkennbar wäre.
    private func sessionExpired() {
        guard case .signedIn = state else { return }
        discardSession()
        errorMessage = "Die Sitzung ist abgelaufen. Bitte melde dich erneut an."
    }

    // MARK: - Token-Lebenszyklus

    private func validAccessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notAuthenticated }
        guard current.isExpired else { return current.accessToken }

        if let running = refreshTask {
            return try await running.value.accessToken
        }
        guard let refreshToken = current.refreshToken else { throw AuthError.notAuthenticated }

        let task = Task { try await oauth.refresh(using: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }

        let refreshed = try await task.value
        try KeychainStore.save(refreshed)
        tokens = refreshed
        return refreshed.accessToken
    }
}
