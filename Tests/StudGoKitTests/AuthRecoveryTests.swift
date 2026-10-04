import Foundation
// URLProtocol und HTTPURLResponse sitzen auf Linux in einem eigenen Modul.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import StudGoKit

/// Wann eine Sitzung wirklich vorbei ist - und wann Stud.IP nur gerade nicht
/// kann.
///
/// Der Anlass ist der Fehler, den 1.8.2 behebt: Bis 1.8.1 meldete die App
/// beim Start ab, sobald das Erneuern des Tokens mit *irgendeinem* Fehler
/// endete - auch mit 503, also genau dann, wenn Stud.IP am Semesterstart
/// überlastet ist. Und ein 401 beendete die Sitzung sofort, obwohl der
/// Hintergrundlauf den Token nur gerade erneuert hatte.
@Suite("Anmeldung: Ablehnung oder Störung")
struct AuthErrorTests {

    @Test("400 und 401 vom Token-Endpunkt beenden die Sitzung")
    func ablehnung() {
        for status in [400, 401] {
            let error = AuthError.tokenEndpointFailure(status: status, detail: nil)
            #expect(error.endsSession)
            #expect(!error.isTransient)
            #expect(!error.isServerUnavailable)
        }
    }

    @Test("Wartung und Überlast am Token-Endpunkt sind vorübergehend")
    func stoerung() {
        for status in [429, 500, 502, 503, 504] {
            let error = AuthError.tokenEndpointFailure(status: status, detail: "Wartung")
            #expect(!error.endsSession, "HTTP \(status) darf nicht abmelden")
            #expect(error.isTransient)
            #expect(error.isServerUnavailable)
        }
    }

    @Test("Eine unlesbare Antwort des Token-Endpunkts meldet nicht ab")
    func unlesbar() {
        #expect(!AuthError.malformedResponse.endsSession)
        #expect(AuthError.malformedResponse.isServerUnavailable)
    }

    @Test("Ohne Token gibt es keine Sitzung mehr")
    func ohneToken() {
        #expect(AuthError.notAuthenticated.endsSession)
    }

    @Test("Überlast der JSON:API gilt als Funkloch, ein 500 nicht")
    func apiFehler() {
        for code in [429, 502, 503, 504] {
            #expect(APIError.http(code, nil).isServerUnavailable)
        }
        for code in [400, 401, 403, 404, 500] {
            #expect(!APIError.http(code, nil).isServerUnavailable)
        }
        #expect(!URLError(.timedOut).isServerUnavailable)
        #expect(URLError(.timedOut).isConnectivityFailure)
    }
}

/// Der Weg einer Anfrage nach einem 401 - mit einer Attrappe statt Stud.IP.
///
/// `.serialized`: Die Attrappe ist ein gemeinsamer Zustand, parallele Tests
/// gössen sich gegenseitig die Antworten aus.
@Suite("Anmeldung: zweiter Versuch und gespeicherter Stand", .serialized)
struct AuthRecoveryTests {

    /// Antwortet nach Vorgabe des laufenden Tests und merkt sich die Token,
    /// die ankamen.
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var respond: (URLRequest) -> (status: Int, body: Data) = { _ in (500, Data()) }
        nonisolated(unsafe) static var tokens: [String] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
            Self.tokens.append(String(header.dropFirst("Bearer ".count)))
            let (status, body) = Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/vnd.api+json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// Was der `AuthStore` gefragt wurde - als Aktor, weil der Rückruf aus
    /// einem beliebigen Executor kommt.
    actor Calls {
        private(set) var list: [(token: String, isRetry: Bool)] = []
        func note(_ token: String, _ isRetry: Bool) { list.append((token, isRetry)) }
    }

    static let profile = Data(#"{"data":{"type":"users","id":"u1","attributes":{"username":"probe"}}}"#.utf8)

    static func client(token: String = "alt",
                       calls: Calls,
                       replacement: String? = "neu") -> StudIPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        var client = StudIPClient(
            tokenProvider: { token },
            onUnauthorized: { rejected, isRetry in
                await calls.note(rejected, isRetry)
                return isRetry ? nil : replacement
            })
        client.transport = URLSession(configuration: configuration)
        client.revalidates = true
        StubProtocol.tokens = []
        return client
    }

    @Test("Ein abgewiesener Token wird genau einmal durch den neuen ersetzt")
    func zweiterVersuch() async throws {
        let calls = Calls()
        let client = Self.client(calls: calls)
        StubProtocol.respond = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer neu"
                ? (200, Self.profile) : (401, Data())
        }

        let document = try await client.get("/v1/users/probe-retry")

        #expect(document.first?.id == "u1")
        #expect(StubProtocol.tokens == ["alt", "neu"])
        let list = await calls.list
        #expect(list.count == 1)
        #expect(list.first?.token == "alt")
        #expect(list.first?.isRetry == false)
    }

    @Test("Wird auch der neue Token abgewiesen, erfährt es der AuthStore - und es bleibt beim 401")
    func auchErsatzAbgewiesen() async {
        let calls = Calls()
        let client = Self.client(calls: calls)
        StubProtocol.respond = { _ in (401, Data()) }

        await #expect(throws: APIError.self) {
            _ = try await client.get("/v1/users/probe-dead")
        }
        #expect(StubProtocol.tokens == ["alt", "neu"])
        let list = await calls.list
        #expect(list.map(\.isRetry) == [false, true])
        #expect(list.last?.token == "neu")
    }

    @Test("Ohne anderen Token gibt es keinen zweiten Versuch")
    func ohneErsatz() async {
        let calls = Calls()
        let client = Self.client(calls: calls, replacement: nil)
        StubProtocol.respond = { _ in (401, Data()) }

        await #expect(throws: APIError.self) {
            _ = try await client.get("/v1/users/probe-none")
        }
        #expect(StubProtocol.tokens == ["alt"])
    }

    @Test("Bei Überlast zählt der gespeicherte Stand")
    func ueberlast() async throws {
        let calls = Calls()
        let client = Self.client(calls: calls)
        StubProtocol.respond = { _ in (200, Self.profile) }
        _ = try await client.get("/v1/users/probe-503")

        StubProtocol.respond = { _ in (503, Data("<html>Wartung</html>".utf8)) }
        let document = try await client.get("/v1/users/probe-503")
        #expect(document.first?.id == "u1")
    }

    @Test("Ein 500 bleibt ein Fehler, auch wenn ein alter Stand vorliegt")
    func serverfehler() async throws {
        let calls = Calls()
        let client = Self.client(calls: calls)
        StubProtocol.respond = { _ in (200, Self.profile) }
        _ = try await client.get("/v1/users/probe-500")

        StubProtocol.respond = { _ in (500, Data()) }
        await #expect(throws: APIError.self) {
            _ = try await client.get("/v1/users/probe-500")
        }
    }

    @Test("Hakt das Erneuern des Tokens, gilt der gespeicherte Stand - eine Ablehnung nicht")
    func erneuernHakt() async throws {
        let calls = Calls()
        var client = Self.client(calls: calls)
        StubProtocol.respond = { _ in (200, Self.profile) }
        _ = try await client.get("/v1/users/probe-refresh")

        client = StudIPClient(tokenProvider: { throw AuthError.server("HTTP 503", nil) })
        client.revalidates = true
        let document = try await client.get("/v1/users/probe-refresh")
        #expect(document.first?.id == "u1")

        client = StudIPClient(tokenProvider: { throw AuthError.rejected(400, nil) })
        client.revalidates = true
        await #expect(throws: AuthError.self) {
            _ = try await client.get("/v1/users/probe-refresh")
        }
    }
}
