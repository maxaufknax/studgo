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
    }

    private(set) var state: State = .loading
    private(set) var errorMessage: String?
    private(set) var isWorking = false

    private let oauth = OAuthService()
    private var tokens: TokenSet?
    /// Verhindert, dass mehrere parallele Requests gleichzeitig refreshen.
    private var refreshTask: Task<TokenSet, Error>?

    var client: StudIPClient { StudIPClient(tokenProvider: { [weak self] in
        guard let self else { throw AuthError.notAuthenticated }
        return try await self.validAccessToken()
    }) }

    /// Beim App-Start: gespeichertes Token laden und den Nutzer holen.
    func restore() async {
        guard let stored = KeychainStore.load() else {
            state = .signedOut
            return
        }
        tokens = stored
        do {
            state = .signedIn(try await client.currentUser())
        } catch {
            // Refresh-Token abgelaufen oder zurückgezogen — sauber neu anmelden.
            KeychainStore.clear()
            tokens = nil
            state = .signedOut
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
            state = .signedIn(try await client.currentUser())
        } catch AuthError.cancelled {
            // Bewusster Abbruch durch den Nutzer, keine Fehlermeldung.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        KeychainStore.clear()
        tokens = nil
        refreshTask = nil
        state = .signedOut
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
