import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import StudGoKit

/// PKCE nach RFC 7636 ist der einzige Schutz des Anmeldevorgangs gegen einen
/// abgefangenen Autorisierungscode. Fehler darin fallen im Betrieb nicht auf —
/// die Anmeldung funktioniert auch mit einem schwachen Verifier.
@Suite("PKCE")
struct PKCETests {
    @Test("Verifier hält sich an die Längenvorgabe des RFC")
    func verifierLaenge() {
        let pkce = PKCE()
        // RFC 7636 §4.1: 43 bis 128 Zeichen. 48 Zufallsbytes ergeben 64.
        #expect(pkce.verifier.count >= 43)
        #expect(pkce.verifier.count <= 128)
    }

    @Test("Verifier und Challenge benutzen nur base64url ohne Auffüllung")
    func zeichenvorrat() {
        let erlaubt = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pkce = PKCE()
        for wert in [pkce.verifier, pkce.challenge] {
            #expect(wert.unicodeScalars.allSatisfy(erlaubt.contains),
                    "Unerlaubtes Zeichen in \(wert)")
            #expect(!wert.contains("="))
            #expect(!wert.contains("+"))
            #expect(!wert.contains("/"))
        }
    }

    @Test("Die Challenge ist wirklich SHA256 des Verifiers")
    func challengeIstS256() {
        // Prüfvektor aus RFC 7636, Anhang B — derselbe Weg, andere Eingabe:
        // Data(verifier).base64URLEncoded muss die Challenge ergeben.
        let pkce = PKCE()
        let erwartet = Data(SHA256.hash(data: Data(pkce.verifier.utf8))).base64URLEncoded
        #expect(pkce.challenge == erwartet)
    }

    @Test("Prüfvektor aus RFC 7636 Anhang B")
    func rfcPruefvektor() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Zwei Anmeldungen teilen sich keinen Verifier")
    func jedesMalNeu() {
        let verifier = Set((0..<20).map { _ in PKCE().verifier })
        #expect(verifier.count == 20)
    }
}

/// Die Web-Rückfallebenen: wo die API nicht hinreicht, schickt StudGo in die
/// Weboberfläche. Ein Tippfehler im Pfad ergibt eine Fehlerseite statt der
/// erwarteten Ansicht — sichtbar erst beim Antippen.
@Suite("Web-Links")
struct WebLinksTests {
    @Test("Alle Links zeigen auf das Stud.IP der LUH")
    func gleicheHerkunft() {
        for url in [WebLinks.studipHome, WebLinks.myCourses, WebLinks.profile,
                    WebLinks.course("c1"), WebLinks.courseFiles("c1"), WebLinks.enrolment("c1")] {
            #expect(url.host() == "studip.uni-hannover.de", "Falscher Host: \(url)")
            #expect(url.scheme == "https")
        }
    }

    @Test("Veranstaltungskennungen landen in der Adresse")
    func kennungImLink() {
        let id = "a1b2c3d4e5"
        #expect(WebLinks.course(id).absoluteString.contains(id))
        #expect(WebLinks.courseFiles(id).absoluteString.contains(id))
        #expect(WebLinks.enrolment(id).absoluteString.contains(id))
    }

    @Test("Externe Ziele bleiben extern")
    func externeZiele() {
        #expect(WebLinks.qis.host()?.hasSuffix("uni-hannover.de") == true)
        #expect(WebLinks.campusMap.host() == "standortfinder.uni-hannover.de")
        #expect(WebLinks.accountManager.host() == "login.uni-hannover.de")
    }

    @Test("Die Raumsuche zieht die Gebäudenummer heraus")
    func raumsuche() {
        // „1101 - E001" ist die Schreibweise der LUH; gesucht wird nach 1101.
        let url = WebLinks.campusMap(searching: "1101 - E001")
        #expect(url.absoluteString.contains("1101"))
    }
}

/// Die OAuth-Endpunkte müssen stimmen — verifiziert gegen Stud.IP 6.0.4.
@Suite("Konfiguration")
struct AppConfigTests {
    @Test("Endpunkte hängen alle an der Basisadresse")
    func endpunkte() {
        #expect(AppConfig.apiRoot.absoluteString == "https://studip.uni-hannover.de/jsonapi.php")
        #expect(AppConfig.authorizationEndpoint.absoluteString
                == "https://studip.uni-hannover.de/dispatch.php/api/oauth2/authorize")
        #expect(AppConfig.tokenEndpoint.absoluteString
                == "https://studip.uni-hannover.de/dispatch.php/api/oauth2/token")
    }

    @Test("Rückleitung passt zum angemeldeten Schema")
    func rueckleitung() {
        // Muss wortgleich zu CFBundleURLSchemes in project.yml sein, sonst
        // kommt die Anmeldung nie in der App an.
        #expect(AppConfig.callbackScheme == "studgo")
        #expect(AppConfig.redirectURI.hasPrefix(AppConfig.callbackScheme + "://"))
        #expect(AppConfig.scope == "api")
    }
}

/// Stud.IP antwortet am OAuth-Endpunkt mit einer HTML-Fehlerseite statt JSON.
@Suite("Fehlerseiten")
struct StudIPErrorPageTests {
    @Test("Die Meldung wird aus der messagebox herausgelesen")
    func meldung() {
        let html = """
        <html><body><div class="messagebox messagebox_error">
        <div class="messagebox_details"><ul>
        <li>Sie sind in dieser Veranstaltung nicht angemeldet.</li>
        </ul></div></div></body></html>
        """
        #expect(StudIPErrorPage.message(from: Data(html.utf8))
                == "Sie sind in dieser Veranstaltung nicht angemeldet.")
    }

    @Test("Mehrere Punkte werden zeilenweise zusammengefasst")
    func mehrereMeldungen() {
        let html = """
        <div class="messagebox_details"><ul>
        <li>Erster Grund</li><li>Zweiter Grund</li>
        </ul></div>
        """
        #expect(StudIPErrorPage.message(from: Data(html.utf8)) == "Erster Grund\nZweiter Grund")
    }

    @Test("Ohne messagebox gibt es nichts zu melden")
    func ohneMessagebox() {
        #expect(StudIPErrorPage.message(from: Data("<html><body>Nichts</body></html>".utf8)) == nil)
        #expect(StudIPErrorPage.message(from: Data()) == nil)
    }
}
