import Foundation

struct TokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    /// Ein paar Sekunden Sicherheitsabstand, damit ein Request nicht
    /// unterwegs in den Ablauf läuft.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }

    init(accessToken: String, refreshToken: String?, expiresIn: TimeInterval, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = Date().addingTimeInterval(expiresIn)
        self.scope = scope
    }
}

/// Rohantwort des Token-Endpunkts.
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }

    var tokenSet: TokenSet {
        TokenSet(accessToken: accessToken,
                 refreshToken: refreshToken,
                 expiresIn: expiresIn ?? 3600,
                 scope: scope)
    }
}

/// Fehler rund um Anmeldung und Token.
///
/// Liegt hier und nicht bei `OAuthService`, weil die Unterscheidung, die
/// diese Aufzählung trägt, auch der Client braucht - und der lässt sich unter
/// Linux prüfen, der Anmeldedienst nicht.
enum AuthError: LocalizedError {
    case cancelled
    case invalidAuthorizationURL
    case stateMismatch
    case missingCode
    case malformedResponse
    case notAuthenticated
    /// Der Token-Endpunkt hat geantwortet, aber nicht mit Tokens: Wartung,
    /// Überlast, ein Fehler auf Serverseite. **Vorübergehend** - die Sitzung
    /// bleibt bestehen.
    case server(String, String?)
    /// Der Token-Endpunkt hat den Refresh-Token oder den Code **ausdrücklich
    /// abgelehnt**: 400 (`invalid_grant`) oder 401 (`invalid_client`) nach
    /// RFC 6749, Abschnitt 5.2. Nur das beendet eine Sitzung.
    case rejected(Int, String?)

    /// Ordnet die Antwort des Token-Endpunkts ein.
    ///
    /// **Der Fehler, den das behebt (Fassung 1.8.2):** Bis 1.8.1 galt jede
    /// Antwort ausser 2xx als „Sitzung vorbei". Antwortete Stud.IP beim
    /// Erneuern mit 503 - Wartung, Überlast am Semesterstart -, meldete
    /// `AuthStore.restore()` die Person beim App-Start ab. Abgemeldet werden
    /// darf aber nur, wenn der Server den Token wirklich zurückweist; alles
    /// andere ist ein Funkloch auf der anderen Seite.
    static func tokenEndpointFailure(status: Int, detail: String?) -> AuthError {
        status == 400 || status == 401
            ? .rejected(status, detail)
            : .server("HTTP \(status)", detail)
    }

    /// Ist die Sitzung damit zu Ende? Nur dann darf die App von sich aus
    /// abmelden.
    var endsSession: Bool {
        switch self {
        case .rejected, .notAuthenticated: return true
        default: return false
        }
    }

    /// Stud.IP kann gerade nicht, die Sitzung ist aber in Ordnung - der
    /// gespeicherte Stand ist dann mehr wert als eine Fehlermeldung.
    var isTransient: Bool {
        switch self {
        case .server, .malformedResponse: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "Anmeldung abgebrochen.")
        case .invalidAuthorizationURL:
            return String(localized: "Die Anmelde-Adresse konnte nicht gebildet werden.")
        case .stateMismatch:
            return String(localized: "Die Antwort des Servers gehört nicht zu dieser Anmeldung.")
        case .missingCode:
            return String(localized: "Stud.IP hat keinen Autorisierungscode zurückgegeben.")
        case .malformedResponse:
            return String(localized: "Unerwartete Antwort des Anmeldeservers.")
        case .notAuthenticated:
            return String(localized: "Nicht angemeldet.")
        case .server(let code, let detail):
            let lead = String(localized: "Stud.IP antwortet gerade nicht (\(code)). Du bleibst angemeldet.")
            return [lead, detail].compactMap { $0 }.joined(separator: " ")
        case .rejected(let status, let detail):
            let lead = String(localized: "Stud.IP hat die Anmeldung abgelehnt (HTTP \(status)).")
            return [lead, detail].compactMap { $0 }.joined(separator: " ")
        }
    }
}
