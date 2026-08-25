import AuthenticationServices
import Foundation
import UIKit

/// Authorization Code Flow mit PKCE gegen Stud.IP.
@MainActor
final class OAuthService: NSObject {
    /// Öffnet die Stud.IP-Anmeldung in einer `ASWebAuthenticationSession` und
    /// tauscht den zurückgelieferten Code gegen ein Token-Set.
    func authenticate() async throws -> TokenSet {
        let pkce = PKCE()
        let state = UUID().uuidString

        let callbackURL = try await presentLogin(pkce: pkce, state: state)
        let code = try extractCode(from: callbackURL, expectedState: state)
        return try await exchange(code: code, verifier: pkce.verifier)
    }

    func refresh(using refreshToken: String) async throws -> TokenSet {
        var form = [
            "grant_type": "refresh_token",
            "client_id": AppConfig.clientID,
            "refresh_token": refreshToken,
        ]
        form["client_secret"] = AppConfig.clientSecret
        return try await postToken(form)
    }

    // MARK: - Schritte

    private func presentLogin(pkce: PKCE, state: String) async throws -> URL {
        var components = URLComponents(url: AppConfig.authorizationEndpoint,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: AppConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.redirectURI),
            URLQueryItem(name: "scope", value: AppConfig.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw AuthError.invalidAuthorizationURL }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.cancelled)
                }
            }
            // **Der Handel:** Stud.IP der LUH meldet über Shibboleth an
            // (`login.uni-hannover.de`). Läuft die Anmeldung in der
            // gewöhnlichen Safari-Sitzung, ist man danach auf jeder Seite
            // angemeldet, die StudGo als Rückfallebene öffnet — Eintragen,
            // Profilbild, Dateiverwaltung. Eine eigene Sitzung
            // (`prefersEphemeral…`) lässt dagegen keinen Cookie zurück, dafür
            // verlangt jede dieser Seiten eine erneute Anmeldung.
            //
            // Welche der beiden Seiten schwerer wiegt, entscheidet nicht der
            // Code, sondern die Einstellung — siehe `Preferences`.
            session.prefersEphemeralWebBrowserSession = !Preferences.sharesWebSessionSetting
            session.presentationContextProvider = self
            session.start()
        }
    }

    private func extractCode(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw AuthError.server(error, value("error_description"))
        }
        guard value("state") == expectedState else { throw AuthError.stateMismatch }
        guard let code = value("code") else { throw AuthError.missingCode }
        return code
    }

    private func exchange(code: String, verifier: String) async throws -> TokenSet {
        var form = [
            "grant_type": "authorization_code",
            "client_id": AppConfig.clientID,
            "redirect_uri": AppConfig.redirectURI,
            "code": code,
            "code_verifier": verifier,
        ]
        form["client_secret"] = AppConfig.clientSecret
        return try await postToken(form)
    }

    private func postToken(_ form: [String: String]) async throws -> TokenSet {
        var request = URLRequest(url: AppConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form.formURLEncoded

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.malformedResponse }

        guard (200..<300).contains(http.statusCode) else {
            // Stud.IP liefert OAuth-Fehler als HTML-Fehlerseite statt als JSON aus.
            throw AuthError.server("HTTP \(http.statusCode)", StudIPErrorPage.message(from: data))
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthError.malformedResponse
        }
        return token.tokenSet
    }
}

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    // Die Protokoll-Anforderung ist nicht actor-isoliert; aufgerufen wird sie
    // von AuthenticationServices aber ausschließlich auf dem Main-Thread.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}

enum AuthError: LocalizedError {
    case cancelled
    case invalidAuthorizationURL
    case stateMismatch
    case missingCode
    case malformedResponse
    case notAuthenticated
    case server(String, String?)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Anmeldung abgebrochen."
        case .invalidAuthorizationURL:
            return "Die Anmelde-Adresse konnte nicht gebildet werden."
        case .stateMismatch:
            return "Die Antwort des Servers gehört nicht zu dieser Anmeldung."
        case .missingCode:
            return "Stud.IP hat keinen Autorisierungscode zurückgegeben."
        case .malformedResponse:
            return "Unerwartete Antwort des Anmeldeservers."
        case .notAuthenticated:
            return "Nicht angemeldet."
        case .server(let code, let detail):
            return [code, detail].compactMap { $0 }.joined(separator: " – ")
        }
    }
}

extension Dictionary where Key == String, Value == String {
    var formURLEncoded: Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
