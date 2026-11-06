// Auf Linux tritt swift-crypto an die Stelle von CryptoKit - gleiche API,
// gleiche Implementierung. Auf iOS bleibt es bei CryptoKit.
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Proof Key for Code Exchange (RFC 7636), Methode S256.
struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        // `SystemRandomNumberGenerator` statt `SecRandomCopyBytes`: Dessen
        // Rückgabewert landete bis 1.8 im Nichts - schlug der Aufruf aus
        // irgendeinem Grund fehl, bestand der Verifier aus 48 Nullbytes,
        // und der PKCE-Schutz wäre wirkungslos gewesen, ohne dass es auffiele.
        // Der Generator der Standardbibliothek kann nicht still scheitern:
        // Er liest auf Apple-Systemen aus `arc4random_buf` und bricht bei
        // einem Versagen der Quelle ab, statt einen schwachen Verifier zu
        // liefern. Auf Linux füllt ihn `/dev/urandom`.
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: 48)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
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
