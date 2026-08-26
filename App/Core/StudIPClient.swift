import Foundation
// URLSession sitzt auf Linux in einem eigenen Modul. Auf iOS ist der
// Block wirkungslos — dort gibt es FoundationNetworking nicht.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Zugriff auf die Stud.IP JSON:API. Der Token kommt bei jedem Aufruf frisch
/// vom `AuthStore`, damit ein abgelaufener Access-Token transparent erneuert wird.
struct StudIPClient {
    let tokenProvider: () async throws -> String

    /// Wird gerufen, wenn der Server 401 meldet. Der `AuthStore` beendet
    /// daraufhin die Sitzung — ohne das bliebe die App in jedem Tab mit
    /// "Sitzung abgelaufen" stehen, ohne Weg zurück zur Anmeldung.
    var onUnauthorized: (() async -> Void)? = nil

    /// Steuert, ob eine gespeicherte Antwort genügt. Beim ersten Aufbau einer
    /// Ansicht ja — dann steht der letzte Stand sofort da. Beim Herunterziehen
    /// nein: dort erwartet man, dass wirklich der Server gefragt wird.
    var revalidates = false

    var fresh: StudIPClient {
        var copy = self
        copy.revalidates = true
        return copy
    }

    /// Eigene Sitzung mit knappem Zeitlimit: die Standardgrenze von 60
    /// Sekunden fühlt sich bei schlechtem Empfang wie ein Hänger an.
    /// Der eingebaute URL-Cache bleibt aus — zwischengespeichert wird in
    /// `ResponseCache`, wo die App die Regeln selbst in der Hand hat.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    // MARK: - Profil

    func currentUser() async throws -> StudIPUser {
        let document = try await get("/v1/users/me")
        guard let resource = document.first, let user = StudIPUser(resource) else {
            throw APIError.decoding("Profil konnte nicht gelesen werden")
        }
        return user
    }

    func user(id: String) async throws -> StudIPUser {
        let document = try await get("/v1/users/\(id)")
        guard let resource = document.first, let user = StudIPUser(resource) else {
            throw APIError.decoding("Person konnte nicht gelesen werden")
        }
        return user
    }

    // MARK: - Veranstaltungen

    /// Ohne Semesterangabe liefert Stud.IP **alle** je belegten
    /// Veranstaltungen — über mehrere Studienjahre wird das schnell
    /// unübersichtlich. `filter[semester]` grenzt serverseitig ein.
    func courses(for userID: String, semester: String? = nil) async throws -> [Course] {
        var extra: [URLQueryItem] = []
        if let semester {
            extra.append(URLQueryItem(name: "filter[semester]", value: semester))
        }
        return try await get("/v1/users/\(userID)/courses", limit: 300, extra: extra)
            .resources.compactMap(Course.init)
    }

    func course(id: String) async throws -> Course {
        let document = try await get("/v1/courses/\(id)")
        guard let resource = document.first, let course = Course(resource) else {
            throw APIError.decoding("Veranstaltung konnte nicht gelesen werden")
        }
        return course
    }

    /// Klartext zu `course-type`. Die Zuordnung ist je Stud.IP-Installation
    /// anders belegt, sie muss also vom Server kommen.
    func semTypes() async throws -> [SemType] {
        try await get("/v1/sem-types", limit: 200).resources.compactMap(SemType.init)
    }

    /// Die Teilnehmendenliste. Bei einer Veranstaltung, in der man nicht
    /// eingetragen ist — etwa einer vorgeschlagenen Studiengruppe — gibt
    /// Stud.IP sie nicht heraus; das ist kein Fehler, sondern die Rechtelage.
    func participants(of course: Course) async throws -> [Participant] {
        try await listAllowingAbsence { try await participantList(of: course) }
    }

    private func participantList(of course: Course) async throws -> [Participant] {
        let document = try await get("/v1/courses/\(course.id)/memberships",
                                    limit: 500, include: ["user"])
        return document.resources
            .compactMap { Participant(membership: $0, user: document.related("user", of: $0)) }
            .sorted {
                $0.roleRank != $1.roleRank
                    ? $0.roleRank < $1.roleRank
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    // MARK: - Termine

    /// **Ohne `page[limit]`.** `/v1/users/{id}/schedule` ist in Stud.IP ein
    /// *Show*-Endpunkt (`UserScheduleShow`) und lässt in
    /// `$allowedPagingParameters` gar nichts zu. Jedes `page[...]` beantwortet
    /// der Server mit `400 Page parameter limit is not allowed` — und die
    /// Wochenansicht bleibt leer. Der Endpunkt liefert ohnehin immer den
    /// vollständigen Plan eines Semesters, eine Seitenaufteilung wäre sinnlos.
    ///
    /// `filter[timestamp]` wählt das Semester (Standard: das laufende).
    func schedule(for userID: String, semesterStart: Date? = nil) async throws -> [ScheduleEntry] {
        var extra: [URLQueryItem] = []
        if let semesterStart {
            extra.append(URLQueryItem(name: "filter[timestamp]",
                                      value: String(Int(semesterStart.timeIntervalSince1970))))
        }
        return try await get("/v1/users/\(userID)/schedule", extra: extra)
            .resources.compactMap(ScheduleEntry.init)
    }

    /// Der Endpunkt liefert immer nur **zwei Wochen** ab dem angefragten
    /// Zeitpunkt. Für eine brauchbare Terminliste werden deshalb mehrere
    /// Fenster hintereinander geholt und zusammengeführt.
    func events(for userID: String, weeks: Int = 6) async throws -> [CourseEvent] {
        let windows = max(1, Int(ceil(Double(weeks) / 2.0)))
        let midnight = Calendar.current.startOfDay(for: Date())

        // Nacheinander statt parallel: die Fenster überlappen sich an den
        // Rändern, und drei kurze Anfragen sind schneller als der Aufwand,
        // den Client dafür über Task-Grenzen hinweg teilbar zu machen.
        var collected: [String: CourseEvent] = [:]
        for index in 0..<windows {
            let start = midnight.addingTimeInterval(Double(index) * 14 * 24 * 3600)
            for event in try await events(for: userID, from: start) {
                collected[event.id] = event
            }
        }
        return collected.values.sorted { $0.start < $1.start }
    }

    private func events(for userID: String, from start: Date) async throws -> [CourseEvent] {
        let timestamp = String(Int(start.timeIntervalSince1970))
        return try await get("/v1/users/\(userID)/events", limit: 500,
                             extra: [URLQueryItem(name: "filter[timestamp]", value: timestamp)])
            .resources.compactMap(CourseEvent.init)
    }

    func events(for course: Course) async throws -> [CourseEvent] {
        try await listAllowingAbsence {
            try await get("/v1/courses/\(course.id)/events", limit: 500)
                .resources.compactMap(CourseEvent.init)
                .sorted { $0.start < $1.start }
        }
    }

    /// **Die** Terminquelle: alle echten Sitzungen ab heute.
    ///
    /// `GET /users/{id}/events.ics` ruft serverseitig
    /// `exportCalendarDates() + exportCourseDates() + exportCourseExDates()`
    /// auf und schreibt jede Sitzung als eigenes `VEVENT` — vom heutigen Tag
    /// bis 2036, ohne Wiederholungsregel, samt Raum, Thema und den
    /// ausgefallenen Terminen. Alles, was `/v1/users/{id}/events` **nicht**
    /// hergibt (das liefert nur den persönlichen Kalender, und den nur zwei
    /// Wochen weit).
    ///
    /// `courses` dient allein der Zuordnung: Der ICS-Strom nennt den
    /// Veranstaltungsnamen, nicht ihre Kennung. Ohne die Zuordnung hätte
    /// derselbe Kurs im Kalender eine andere Farbe als im Stundenplan und
    /// ließe sich von dort aus nicht öffnen.
    func calendarEvents(for userID: String, courses: [Course] = []) async throws -> [CourseEvent] {
        let feed = try await text("/v1/users/\(userID)/events.ics")
        let index = Self.courseIndex(courses)
        return ICSParser.events(in: feed)
            .map { CourseEvent(ics: $0, courseID: Self.matchCourse($0.summary, in: index)) }
            .sorted { $0.start < $1.start }
    }

    /// Titel → Kennung, für die Zuordnung der ICS-Termine.
    private static func courseIndex(_ courses: [Course]) -> [(key: String, id: String)] {
        courses.flatMap { course -> [(key: String, id: String)] in
            [course.title, course.shortTitle]
                .map(normalizedTitle)
                .filter { $0.count >= 6 }
                .map { (key: $0, id: course.id) }
        }
    }

    /// Vergleicht großzügig: Stud.IP setzt in den ICS-Titel
    /// `Course::getFullName()`, also je nach Einstellung mit oder ohne
    /// Veranstaltungsnummer und mit angehängtem Untertitel.
    private static func matchCourse(_ summary: String, in index: [(key: String, id: String)]) -> String? {
        guard !index.isEmpty else { return nil }
        let candidate = normalizedTitle(summary)
        guard !candidate.isEmpty else { return nil }
        // Der längste Treffer gewinnt: „Analysis I" darf nicht die Termine
        // von „Analysis II" einsammeln.
        return index
            .filter { candidate.contains($0.key) || $0.key.contains(candidate) }
            .max { $0.key.count < $1.key.count }?
            .id
    }

    private static func normalizedTitle(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    func semesters() async throws -> [Semester] {
        try await get("/v1/semesters", limit: 100).resources.compactMap(Semester.init)
    }

    // MARK: - Nachrichten

    func inbox(for userID: String) async throws -> [Message] {
        try await messages(at: "/v1/users/\(userID)/inbox", outgoing: false)
    }

    func outbox(for userID: String) async throws -> [Message] {
        try await messages(at: "/v1/users/\(userID)/outbox", outgoing: true)
    }

    private func messages(at path: String, outgoing: Bool) async throws -> [Message] {
        // Im Postausgang ist der Absender immer man selbst — dort zählt die
        // Empfängerliste, und die kommt nur mit `include` mit.
        let wanted = outgoing ? ["sender", "recipients"] : ["sender"]
        let document = try await documentAllowingMissingIncludes(path: path,
                                                                 limit: 100,
                                                                 include: wanted,
                                                                 fallback: [])
        return document.resources
            .compactMap {
                Message($0,
                        sender: document.related("sender", of: $0),
                        recipients: document.relatedList("recipients", of: $0))
            }
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
    }

    func markMessage(_ id: String, read: Bool) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "messages",
                "id": id,
                "attributes": ["is-read": read],
            ],
        ]
        _ = try await send("PATCH", "/v1/messages/\(id)", body: body)
    }

    /// Verschickt eine Nachricht. Stud.IP erwartet die Empfänger als
    /// `recipients`-Beziehung, der Betreff darf nicht leer sein.
    func sendMessage(subject: String, body text: String, to recipients: [String]) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "messages",
                "attributes": [
                    "subject": subject,
                    "message": text,
                ],
                "relationships": [
                    "recipients": [
                        "data": recipients.map { ["type": "users", "id": $0] },
                    ],
                ],
            ],
        ]
        _ = try await send("POST", "/v1/messages", body: payload)
    }

    // MARK: - Ankündigungen

    func news(for userID: String) async throws -> [NewsItem] {
        try await news(at: "/v1/users/\(userID)/news")
    }

    func news(for course: Course) async throws -> [NewsItem] {
        try await listAllowingAbsence { try await news(at: "/v1/courses/\(course.id)/news") }
    }

    func globalNews() async throws -> [NewsItem] {
        try await news(at: "/v1/studip/news")
    }

    private func news(at path: String) async throws -> [NewsItem] {
        let document = try await documentAllowingMissingIncludes(path: path,
                                                                 limit: 100,
                                                                 include: ["author"],
                                                                 fallback: [])
        return document.resources
            .compactMap { NewsItem($0, author: document.related("author", of: $0)) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    // MARK: - Dateien

    func rootFolders(of course: Course) async throws -> [Folder] {
        try await get("/v1/courses/\(course.id)/folders", limit: 200)
            .resources.compactMap(Folder.init)
    }

    func subfolders(of folder: Folder) async throws -> [Folder] {
        try await get("/v1/folders/\(folder.id)/folders", limit: 200)
            .resources.compactMap(Folder.init)
    }

    func files(in folder: Folder) async throws -> [FileRef] {
        try await get("/v1/folders/\(folder.id)/file-refs", limit: 500)
            .resources.compactMap(FileRef.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lädt eine Datei in einen temporären Ordner und gibt den lokalen Pfad
    /// zurück — von dort aus übernehmen QuickLook und das Teilen-Menü.
    func download(_ file: FileRef) async throws -> URL {
        var request = URLRequest(url: URL(string: AppConfig.apiRoot.absoluteString
                                          + "/v1/file-refs/\(file.id)/content")!)
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")

        let (temporaryURL, response) = try await Self.session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw APIError.http(http.statusCode, nil)
        }

        // Der Download landet unter einem Zufallsnamen — für die Vorschau und
        // das Teilen zählt aber der echte Dateiname samt Endung.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudGo-Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(file.name.sanitizedFileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    // MARK: - Personensuche (für Empfänger beim Verfassen)

    func searchUsers(_ term: String) async throws -> [StudIPUser] {
        guard term.count >= 3 else { return [] }
        return try await fresh.get("/v1/users", limit: 25,
                                   extra: [URLQueryItem(name: "filter[search]", value: term)])
            .resources.compactMap(StudIPUser.init)
    }

    // MARK: - Transport

    func url(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(string: AppConfig.apiRoot.absoluteString + path)!
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    /// Nicht `private`: `StudIPClient+Campus.swift` setzt darauf auf, und
    /// `private` gilt in Swift nur innerhalb derselben Datei.
    func get(_ path: String,
             limit: Int? = nil,
             offset: Int? = nil,
             include: [String] = [],
             sort: String? = nil,
             extra: [URLQueryItem] = []) async throws -> JSONAPIDocument {
        var query = extra
        if let limit { query.append(URLQueryItem(name: "page[limit]", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "page[offset]", value: String(offset))) }
        if !include.isEmpty {
            query.append(URLQueryItem(name: "include", value: include.joined(separator: ",")))
        }
        // `sort` verbieten fast alle Routen (`$allowedSortFields = []`); wo es
        // erlaubt ist, steht es in docs/API-NOTES.md.
        if let sort { query.append(URLQueryItem(name: "sort", value: sort)) }

        let address = url(path: path, query: query)
        let key = address.absoluteString

        // Der Zwischenspeicher wird **vor** dem Token gefragt: sonst liefe ein
        // abgelaufener Access-Token ohne Netz in einen Fehler, obwohl die
        // Antwort längst auf der Platte liegt.
        if !revalidates, let hit = ResponseCache.load(for: key), hit.age < ResponseCache.maxAge,
           let document = try? JSONAPIDocument(data: hit.data) {
            return document
        }

        do {
            var request = URLRequest(url: address)
            request.httpMethod = "GET"
            request.setValue("Bearer \(try await tokenProvider())",
                             forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")

            let data = try await perform(request)
            ResponseCache.store(data, for: key)
            guard !data.isEmpty else { return JSONAPIDocument.empty }
            return try JSONAPIDocument(data: data)
        } catch {
            // Ohne Verbindung zählt jeder gespeicherte Stand, auch ein alter.
            if error.isConnectivityFailure {
                if let hit = ResponseCache.load(for: key),
                   let document = try? JSONAPIDocument(data: hit.data) {
                    return document
                }
                throw APIError.offline
            }
            throw error
        }
    }

    /// Rohtext einer Route, die **kein** JSON:API spricht.
    ///
    /// Es gibt genau eine solche in StudGo: `GET /users/{id}/events.ics`
    /// (`NonJsonApiController`, `Content-Type: text/calendar`). Der übliche
    /// Weg über `JSONAPIDocument` scheitert daran mit „Antwort ist kein
    /// JSON-Objekt" — deshalb ein eigener Zugang, der aber denselben
    /// Zwischenspeicher und dieselbe Fehlerbehandlung benutzt.
    func text(_ path: String, extra: [URLQueryItem] = []) async throws -> String {
        let address = url(path: path, query: extra)
        let key = address.absoluteString

        if !revalidates, let hit = ResponseCache.load(for: key), hit.age < ResponseCache.maxAge,
           let cached = String(data: hit.data, encoding: .utf8) {
            return cached
        }

        do {
            var request = URLRequest(url: address)
            request.httpMethod = "GET"
            request.setValue("Bearer \(try await tokenProvider())",
                             forHTTPHeaderField: "Authorization")
            request.setValue("text/calendar", forHTTPHeaderField: "Accept")

            let data = try await perform(request)
            ResponseCache.store(data, for: key)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            if error.isConnectivityFailure {
                if let hit = ResponseCache.load(for: key),
                   let cached = String(data: hit.data, encoding: .utf8) {
                    return cached
                }
                throw APIError.offline
            }
            throw error
        }
    }

    /// Manche Beziehungen sind je nach Rechtelage nicht mitlieferbar; Stud.IP
    /// beantwortet ein unerlaubtes `include` dann mit 400. Das darf nicht die
    /// ganze Liste kosten — im Zweifel eben ohne die Zusatzdaten.
    func documentAllowingMissingIncludes(path: String,
                                         limit: Int,
                                         offset: Int? = nil,
                                         include: [String],
                                         fallback: [String],
                                         sort: String? = nil,
                                         extra: [URLQueryItem] = []) async throws -> JSONAPIDocument {
        do {
            return try await get(path, limit: limit, offset: offset,
                                 include: include, sort: sort, extra: extra)
        } catch let error as APIError {
            guard case .http(400, _) = error else { throw error }
            return try await get(path, limit: limit, offset: offset,
                                 include: fallback, sort: sort, extra: extra)
        }
    }

    /// Für Listen, die es auch schlicht **nicht geben** kann.
    ///
    /// Stud.IP unterscheidet dort nicht zwischen „leer" und „fehlt": Das Wiki
    /// einer Veranstaltung ohne einzige Seite beantwortet `WikiIndex` mit
    /// `RecordNotFoundException`, also **404**. Als Fehler gezeigt hieß das in
    /// der App „Nicht gefunden — vielleicht wurde der Eintrag entfernt", wo
    /// schlicht „kein Wiki angelegt" richtig ist. Fehlende Rechte (403) gehören
    /// genauso hierher: Bei einer fremden Studiengruppe ist die
    /// Teilnehmendenliste einfach nicht einsehbar.
    func listAllowingAbsence<T>(_ operation: () async throws -> [T]) async throws -> [T] {
        do {
            return try await operation()
        } catch let error as APIError {
            if case .http(404, _) = error { return [] }
            if case .http(403, _) = error { return [] }
            throw error
        }
    }

    @discardableResult
    func send(_ method: String, _ path: String, body: [String: Any]) async throws -> JSONAPIDocument {
        var request = URLRequest(url: url(path: path, query: []))
        request.httpMethod = method
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let data = try await perform(request)
            // 204 und leere Antworten sind bei PATCH/POST gültig.
            guard !data.isEmpty else { return JSONAPIDocument.empty }
            return try JSONAPIDocument(data: data)
        } catch {
            throw error.isConnectivityFailure ? APIError.offline : error
        }
    }

    /// Nicht `private`: `StudIPClient+Files.swift` schickt einen
    /// Multipart-Body und braucht dieselbe Fehlerbehandlung samt
    /// 401-Meldung. `private` gilt in Swift nur innerhalb einer Datei.
    func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { await onUnauthorized?() }
            throw error(status: http.statusCode, body: data)
        }
        return data
    }

    /// Die JSON:API meldet Fehler strukturiert im Body; am OAuth-nahen Rand
    /// antwortet Stud.IP dagegen mit einer HTML-Fehlerseite.
    private func error(status: Int, body: Data) -> APIError {
        if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let errors = root["errors"] as? [[String: Any]] {
            let details = errors.compactMap { ($0["detail"] as? String) ?? ($0["title"] as? String) }
            return .http(status, details.isEmpty ? nil : details.joined(separator: "\n"))
        }
        return .http(status, StudIPErrorPage.message(from: body))
    }
}

extension Error {
    /// Unterscheidet „kein Netz" von einem echten Fehler des Servers. Nur im
    /// ersten Fall lohnt der Griff zum Zwischenspeicher.
    var isConnectivityFailure: Bool {
        guard let urlError = self as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

private extension String {
    /// Stud.IP-Dateinamen können Zeichen enthalten, die im Dateisystem stören.
    var sanitizedFileName: String {
        let cleaned = components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Datei" : cleaned
    }
}

extension JSONAPIDocument {
    /// Für Antworten ohne Body (etwa nach einem PATCH).
    static var empty: JSONAPIDocument {
        // swiftlint:disable:next force_try
        try! JSONAPIDocument(data: Data("{\"data\":[]}".utf8))
    }
}
