import Foundation

/// Die Stud.IP-Bereiche jenseits von Stundenplan, Kursen und Postfach.
///
/// **Zur Seitenaufteilung:** Stud.IP prüft Anfrageparameter streng. Jede Route
/// führt in `$allowedPagingParameters` auf, was sie zulässt — steht dort nichts,
/// beantwortet der Server schon ein `page[limit]` mit
/// `400 Page parameter limit is not allowed`. Welche Route was erlaubt, steht
/// in docs/API-NOTES.md; die dortige Tabelle ist aus dem Stud.IP-Quelltext
/// erzeugt und nicht geraten.
extension StudIPClient {

    // MARK: - Blubber

    /// Woher die Fäden kommen sollen. Stud.IP bedient alle vier Varianten mit
    /// derselben Ressource, nur unter verschiedenen Pfaden.
    enum BlubberScope {
        /// Alles, was die Person sehen darf — privat, Kurse, öffentlich.
        case all
        /// Nur Direktnachrichten.
        case direct(userID: String)
        /// Der öffentliche Strom der Installation.
        case publicStream
        /// Die Fäden einer Veranstaltung.
        case course(id: String)

        var path: String {
            switch self {
            case .all: return "/v1/blubber-threads"
            case .direct(let userID): return "/v1/users/\(userID)/blubber-threads"
            case .publicStream: return "/v1/studip/blubber-threads"
            case .course(let id): return "/v1/courses/\(id)/blubber-threads"
            }
        }
    }

    /// Blubber-Fäden samt Verfasser.
    ///
    /// `filter[search]` gibt es hier wirklich (anders als bei `/v1/users`,
    /// wo der Filter `filter[search]` heißt und drei Zeichen verlangt).
    func blubberThreads(_ scope: BlubberScope,
                        search: String? = nil,
                        limit: Int = 60) async throws -> [BlubberThread] {
        var extra: [URLQueryItem] = []
        if let search, !search.isEmpty {
            extra.append(URLQueryItem(name: "filter[search]", value: search))
        }
        let document = try await documentAllowingMissingIncludes(path: scope.path,
                                                                 limit: limit,
                                                                 include: ["author"],
                                                                 fallback: [],
                                                                 extra: extra)
        return document.resources
            .compactMap { BlubberThread($0, author: document.related("author", of: $0)) }
            .sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }
    }

    /// Die Beiträge eines Fadens, älteste zuerst — so liest sich ein Verlauf.
    func blubberComments(threadID: String, limit: Int = 200) async throws -> [BlubberComment] {
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/blubber-threads/\(threadID)/comments",
            limit: limit,
            include: ["author"],
            fallback: [])
        return document.resources
            .compactMap { BlubberComment($0, author: document.related("author", of: $0)) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Einen Beitrag in einen bestehenden Faden schreiben.
    func postBlubberComment(threadID: String, content: String) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "blubber-comments",
                "attributes": ["content": content],
            ],
        ]
        _ = try await send("POST", "/v1/blubber-threads/\(threadID)/comments", body: payload)
    }

    /// Einen neuen Faden aufmachen. Ohne `contextID` landet er im
    /// öffentlichen Strom, mit Veranstaltungs-ID in deren Bereich.
    func createBlubberThread(content: String, courseID: String? = nil) async throws {
        var attributes: [String: Any] = ["content": content]
        var relationships: [String: Any] = [:]
        if let courseID {
            attributes["context-type"] = "course"
            relationships["context"] = ["data": ["type": "courses", "id": courseID]]
        }
        var data: [String: Any] = ["type": "blubber-threads", "attributes": attributes]
        if !relationships.isEmpty { data["relationships"] = relationships }
        _ = try await send("POST", "/v1/blubber-threads", body: ["data": data])
    }

    // MARK: - Aktivitätenstrom

    /// Was in den belegten Veranstaltungen zuletzt passiert ist.
    ///
    /// Die Route nimmt `filter[start]`/`filter[end]` als Unix-Sekunden. Ohne
    /// Zeitraum liefert Stud.IP den jüngsten Ausschnitt.
    func activityStream(for userID: String,
                        since: Date? = nil,
                        limit: Int = 60) async throws -> [ActivityItem] {
        var extra: [URLQueryItem] = []
        if let since {
            extra.append(URLQueryItem(name: "filter[start]",
                                      value: String(Int(since.timeIntervalSince1970))))
        }
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/users/\(userID)/activitystream",
            limit: limit,
            include: ["actor", "context"],
            fallback: [],
            extra: extra)
        return document.resources
            .compactMap {
                ActivityItem($0,
                             actor: document.related("actor", of: $0),
                             context: document.related("context", of: $0))
            }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: - Kontakte

    func contacts(for userID: String) async throws -> [Contact] {
        try await get("/v1/users/\(userID)/contacts", limit: 300)
            .resources.compactMap(Contact.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Eigene Mitgliedschaften

    /// Rolle, Farbgruppe und Sichtbarkeit in allen belegten Veranstaltungen.
    func courseMemberships(for userID: String) async throws -> [CourseMembership] {
        try await get("/v1/users/\(userID)/course-memberships", limit: 300)
            .resources.compactMap(CourseMembership.init)
    }

    /// Sichtbarkeit in der Teilnehmendenliste einer Veranstaltung umstellen.
    ///
    /// Mehr lässt die JSON:API bei der eigenen Mitgliedschaft nicht zu —
    /// Ein- und Austragen führen ausschließlich über die Weboberfläche.
    func setMembershipVisibility(_ membershipID: String, visible: Bool) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "course-memberships",
                "id": membershipID,
                "attributes": ["visible": visible ? "yes" : "no"],
            ],
        ]
        _ = try await send("PATCH", "/v1/course-memberships/\(membershipID)", body: payload)
    }

    // MARK: - Veranstaltungssuche

    /// Worin gesucht wird. Stud.IP prüft den Wert serverseitig gegen eine
    /// feste Liste und antwortet sonst mit 400.
    enum CourseSearchField: String, CaseIterable, Identifiable {
        case all
        case titleLecturerNumber = "title_lecturer_number"
        case title
        case lecturer
        case number

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "Überall"
            case .titleLecturerNumber: return "Titel, Lehrende, Nummer"
            case .title: return "Titel"
            case .lecturer: return "Lehrende"
            case .number: return "Nummer"
            }
        }
    }

    /// Das gesamte Vorlesungsverzeichnis durchsuchen — auch Veranstaltungen,
    /// in denen man nicht eingetragen ist.
    ///
    /// Der Suchbegriff braucht **mindestens drei Zeichen**, sonst antwortet
    /// Stud.IP mit `400 Search term too short`.
    func searchCourses(_ term: String,
                       field: CourseSearchField = .all,
                       semesterID: String? = nil,
                       limit: Int = 60) async throws -> [Course] {
        guard term.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return [] }
        var extra = [
            URLQueryItem(name: "filter[q]", value: term),
            URLQueryItem(name: "filter[fields]", value: field.rawValue),
        ]
        // "all" ist der serverseitige Standard und meint *alle* Semester.
        extra.append(URLQueryItem(name: "filter[semester]", value: semesterID ?? "all"))
        return try await fresh.get("/v1/courses", limit: limit, extra: extra)
            .resources.compactMap(Course.init)
    }

    // MARK: - Forum

    func forumCategories(of course: Course) async throws -> [ForumCategory] {
        try await get("/v1/courses/\(course.id)/forum-categories", limit: 100)
            .resources.compactMap(ForumCategory.init)
            .sorted { $0.position < $1.position }
    }

    func forumEntries(in category: ForumCategory, limit: Int = 100) async throws -> [ForumEntry] {
        try await get("/v1/forum-categories/\(category.id)/entries", limit: limit)
            .resources.compactMap(ForumEntry.init)
    }

    /// Die Antworten auf einen Beitrag.
    func forumEntries(under entry: ForumEntry, limit: Int = 200) async throws -> [ForumEntry] {
        try await get("/v1/forum-entries/\(entry.id)/entries", limit: limit)
            .resources.compactMap(ForumEntry.init)
    }

    /// Auf einen Forenbeitrag antworten.
    func replyToForumEntry(_ entryID: String, title: String, content: String) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "forum-entries",
                "attributes": ["title": title, "content": content],
            ],
        ]
        _ = try await send("POST", "/v1/forum-entries/\(entryID)/entries", body: payload)
    }

    // MARK: - Wiki

    func wikiPages(of course: Course, limit: Int = 100) async throws -> [WikiPage] {
        try await get("/v1/courses/\(course.id)/wiki-pages", limit: limit)
            .resources.compactMap(WikiPage.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Einrichtungen

    func institute(id: String) async throws -> Institute {
        let document = try await get("/v1/institutes/\(id)")
        guard let resource = document.first, let institute = Institute(resource) else {
            throw APIError.decoding("Einrichtung konnte nicht gelesen werden")
        }
        return institute
    }

    /// Zu welchen Einrichtungen die Person gehört.
    func instituteMemberships(for userID: String) async throws -> [Institute] {
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/users/\(userID)/institute-memberships",
            limit: 100,
            include: ["institute"],
            fallback: [])
        return document.resources
            .compactMap { document.related("institute", of: $0) }
            .compactMap(Institute.init)
    }

    // MARK: - Ankündigungen kommentieren

    func newsComments(_ newsID: String) async throws -> [Resource] {
        try await get("/v1/news/\(newsID)/comments", limit: 100).resources
    }

    // MARK: - Kontakte verwalten

    /// Person ins eigene Adressbuch aufnehmen.
    ///
    /// Läuft über die **Beziehung**, nicht über eine Ressource:
    /// `POST /v1/users/{id}/relationships/contacts` mit einer Liste von
    /// Ressourcenkennungen. Der Server antwortet mit `204` ohne Inhalt.
    func addContact(_ contactID: String, for userID: String) async throws {
        _ = try await send("POST", "/v1/users/\(userID)/relationships/contacts",
                           body: ["data": [["type": "users", "id": contactID]]])
    }

    /// Person aus dem Adressbuch entfernen.
    func removeContact(_ contactID: String, for userID: String) async throws {
        _ = try await send("DELETE", "/v1/users/\(userID)/relationships/contacts",
                           body: ["data": [["type": "users", "id": contactID]]])
    }

    // MARK: - Studiengruppen

    /// Vorgeschlagene Studiengruppen.
    ///
    /// Stud.IP sucht sie danach aus, in welchen Gruppen Leute aus den eigenen
    /// Veranstaltungen sind. Die Route nimmt **nur `page[limit]`**, kein
    /// `page[offset]` — ein Offset quittiert sie mit 400.
    func studygroupProposals(limit: Int = 12) async throws -> [Course] {
        try await get("/v1/studygroup-proposals", limit: limit)
            .resources.compactMap(Course.init)
    }

    // MARK: - Sprechstunden

    /// Sprechstundenblöcke einer Person, Veranstaltung oder Einrichtung.
    ///
    /// `filter[current]` und `filter[expired]` sind `0`/`1`. Ohne Filter
    /// liefert Stud.IP beides; hier zählen nur die laufenden.
    func consultationBlocks(userID: String, includeExpired: Bool = false) async throws -> [ConsultationBlock] {
        let extra = [
            URLQueryItem(name: "filter[current]", value: "1"),
            URLQueryItem(name: "filter[expired]", value: includeExpired ? "1" : "0"),
        ]
        return try await get("/v1/users/\(userID)/consultations", limit: 100, extra: extra)
            .resources.compactMap(ConsultationBlock.init)
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    func consultationSlots(blockID: String) async throws -> [ConsultationSlot] {
        try await get("/v1/consultation-blocks/\(blockID)/slots", limit: 200)
            .resources.compactMap(ConsultationSlot.init)
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// Einen Sprechstundentermin buchen.
    ///
    /// Stud.IP verlangt die Person **als Beziehung**, nicht als Attribut, und
    /// prüft sie gegen `canBookSlotForUser`. Ist der Termin inzwischen vergeben,
    /// antwortet der Server mit `409`.
    func bookConsultation(slotID: String, userID: String, reason: String) async throws {
        let payload: [String: Any] = [
            "data": [
                "type": "consultation-bookings",
                "attributes": ["reason": reason],
                "relationships": [
                    "user": ["data": ["type": "users", "id": userID]],
                    "slot": ["data": ["type": "consultation-slots", "id": slotID]],
                ],
            ],
        ]
        _ = try await send("POST", "/v1/consultation-slots/\(slotID)/bookings", body: payload)
    }

    func cancelConsultation(bookingID: String) async throws {
        _ = try await send("DELETE", "/v1/consultation-bookings/\(bookingID)", body: [:])
    }

    // MARK: - Wege in die Weboberfläche

    /// Die JSON:API kennt **kein** Ein- oder Austragen: `authorize()` in
    /// `Routes\Courses\Rel\Memberships` gibt für alles außer GET hart `false`
    /// zurück, und `PATCH /v1/course-memberships/{id}` ändert nur Farbgruppe
    /// und Sichtbarkeit. Anmelden führt deshalb über die Weboberfläche —
    /// dorthin zeigt diese Adresse.
    static func enrolmentURL(courseID: String) -> URL {
        AppConfig.baseURL
            .appendingPathComponent("dispatch.php/course/enrolment/apply")
            .appendingPathComponent(courseID)
    }

    /// Übersicht „Meine Veranstaltungen" — dort wird ausgetragen.
    static var myCoursesURL: URL {
        AppConfig.baseURL.appendingPathComponent("dispatch.php/my_courses")
    }

    /// Eine Veranstaltung in der Weboberfläche öffnen.
    static func courseURL(courseID: String) -> URL {
        var components = URLComponents(url: AppConfig.baseURL.appendingPathComponent("seminar_main.php"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "auswahl", value: courseID)]
        return components.url!
    }
}
