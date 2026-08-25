import Foundation

/// Feste Verbindungsdaten zum Stud.IP der LUH.
///
/// Stud.IP bietet keine OAuth-Discovery-Metadaten, die Endpunkte sind daher
/// fest verdrahtet (verifiziert gegen Stud.IP 6.0.4, siehe docs/API-NOTES.md).
enum AppConfig {
    static let baseURL = URL(string: "https://studip.uni-hannover.de")!

    static var authorizationEndpoint: URL {
        baseURL.appendingPathComponent("dispatch.php/api/oauth2/authorize")
    }

    static var tokenEndpoint: URL {
        baseURL.appendingPathComponent("dispatch.php/api/oauth2/token")
    }

    static var apiRoot: URL {
        baseURL.appendingPathComponent("jsonapi.php")
    }

    /// SOGo-Weboberfläche der LUH. `webmail.uni-hannover.de` leitet dorthin
    /// weiter; die Zieladresse zu nehmen spart die Umleitung.
    /// Warum StudGo Mail nur verlinkt statt einzubauen: docs/SOGO-MAIL.md.
    static let webmailURL = URL(string: "https://kalender.uni-hannover.de/SOGo/")!

    static let callbackScheme = "studgo"
    static let redirectURI = "studgo://oauth/callback"
    static let scope = "api"

    static let clientID = infoValue("STUDIP_CLIENT_ID") ?? ""

    /// Bei Client 15 verlangt der Token-Endpunkt zwingend ein `client_secret`
    /// (confidential client). Sobald die ZQS den Client auf *public* umstellt,
    /// fällt dieser Wert ersatzlos weg — PKCE trägt den Flow dann allein.
    static let clientSecret = infoValue("STUDIP_CLIENT_SECRET")

    private static func infoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
