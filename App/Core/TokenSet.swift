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
