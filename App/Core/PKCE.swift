// Auf Linux tritt swift-crypto an die Stelle von CryptoKit — gleiche API,
// gleiche Implementierung. Auf iOS bleibt es bei CryptoKit.
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
// Liefert auf Apple-Systemen SecRandomCopyBytes. Bisher kam es
// stillschweigend über CryptoKit mit; ausdrücklich ist es ehrlicher.
#if canImport(Security)
import Security
#endif

/// Proof Key for Code Exchange (RFC 7636), Methode S256.
struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 48)
        // TODO: Der Rückgabewert von SecRandomCopyBytes wird verworfen.
        // Schlägt der Aufruf fehl, bestünde der Verifier aus 48 Nullbytes —
        // der PKCE-Schutz wäre dann wirkungslos, ohne dass es auffiele.
        // Wie darauf zu reagieren ist (Abbruch der Anmeldung? Wiederholung?),
        // ist eine Entscheidung, die hier bewusst offen bleibt.
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        #else
        // Ausserhalb von Apple: der Zufallsgenerator des Systems über die
        // Standardbibliothek. Dieser Zweig läuft nur in den Tests.
        var generator = SystemRandomNumberGenerator()
        bytes = (0..<bytes.count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        #endif
        verifier = Data(bytes).base64URLEncoded

        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
