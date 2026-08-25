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

    /// Die Fäden fürs Postfach — mit Rückfallebene.
    ///
    /// **Warum das nicht ein Aufruf ist:** `/v1/blubber-threads` fasst in
    /// `BlubberThread::findMyGlobalThreads()` fünf Unterabfragen zusammen und
    /// wirft in `Schemas/BlubberThread::getContextRelationship()` einen
    /// `InternalServerError`, sobald ein Faden auf eine gelöschte
    /// Veranstaltung zeigt — was am Semesterende regelmäßig vorkommt. Ein
    /// einziger verwaister Faden nimmt dann die **ganze** Liste mit, und im
    /// Postfach stand plötzlich null statt zwei Unterhaltungen.
    ///
    /// Deshalb: Kommt von der Sammelroute nichts (oder ein Fehler), werden die
    /// Fäden der belegten Veranstaltungen einzeln geholt. Jede dieser Routen
    /// betrifft nur einen Kurs — ein kaputter Datensatz kostet dann höchstens
    /// diesen einen.
    func personalBlubberThreads(for userID: String, limit: Int = 80) async throws -> [BlubberThread] {
        var collected: [String: BlubberThread] = [:]
        var firstFailure: Error?

        do {
            for thread in try await blubberThreads(.all, limit: limit)
            where thread.context != .publicStream {
                collected[thread.id] = thread
            }
        } catch {
            firstFailure = error
        }

        if collected.isEmpty {
            for thread in await courseThreadsFallback(for: userID) {
                collected[thread.id] = thread
            }
        }

        if collected.isEmpty, let firstFailure { throw firstFailure }
        return collected.values
            .sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }
    }

    /// Die Blubber-Fäden der belegten Veranstaltungen, einzeln geholt.
    ///
    /// Bewusst auf eine Handvoll Kurse begrenzt und fehlertolerant: Das hier
    /// ist die Rückfallebene, kein Ersatz für die Sammelroute. Wer 40
    /// Veranstaltungen belegt hat, soll nicht 40 Anfragen auslösen.
    private func courseThreadsFallback(for userID: String, courseLimit: Int = 12) async -> [BlubberThread] {
        guard let courses = try? await self.courses(for: userID) else { return [] }

        // Nacheinander statt in einer Task-Gruppe: Der Client trägt zwei
        // Closures (Tokenbeschaffung, 401-Meldung), die nicht `Sendable` sind.
        // Für eine Rückfallebene, die nur greift, wenn ohnehin nichts kam, ist
        // die Nebenläufigkeit den Umbau nicht wert.
        var found: [BlubberThread] = []
        for course in courses.prefix(courseLimit) {
            guard !Task.isCancelled else { break }
            found += (try? await blubberThreads(.course(id: course.id), limit: 20)) ?? []
        }
        return found
    }

    /// Ein Ausschnitt aus einem Blubber-Verlauf, älteste zuerst gesetzt.
    struct BlubberPage {
        let comments: [BlubberComment]
        /// Liegen noch ältere Beiträge dahinter?
        let hasOlder: Bool
    }

    /// Die Beiträge eines Fadens — **die neuesten zuerst geholt**, für die
    /// Anzeige dann in Lesereihenfolge gedreht.
    ///
    /// `CommentsByThreadIndex` sortiert ohne Zutun `ORDER BY mkdate` und
    /// schneidet mit `LIMIT/OFFSET` vorne ab: Eine Anfrage ohne `sort` liefert
    /// also die **ältesten** Beiträge eines Fadens. In einer laufenden
    /// Unterhaltung stand damit der Anfang von vor Monaten im Bild und die
    /// letzte Antwort nirgends — der Verlauf wirkte leer oder eingefroren.
    ///
    /// Diese eine Route lässt `sort` ausdrücklich zu
    /// (`$allowedSortFields = ['mkdate']`, sonst überall `[]`), deshalb holt
    /// `sort=-mkdate` den aktuellen Ausschnitt. `offset` blättert von dort aus
    /// weiter in die Vergangenheit.
    func blubberComments(threadID: String,
                         limit: Int = 60,
                         offset: Int = 0) async throws -> BlubberPage {
        // Einen mehr anfragen, als gezeigt wird: daran ist zu erkennen, ob
        // sich das Nachladen älterer Beiträge überhaupt lohnt.
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/blubber-threads/\(threadID)/comments",
            limit: limit + 1,
            offset: offset,
            include: ["author"],
            fallback: [],
            sort: "-mkdate")

        let newestFirst = document.resources
            .compactMap { BlubberComment($0, author: document.related("author", of: $0)) }
        let hasOlder = newestFirst.count > limit
        // `reversed()` einer Array liefert eine `ReversedCollection`, keine
        // Array — deshalb das `Array(...)` außen herum.
        return BlubberPage(comments: Array(newestFirst.prefix(limit).reversed()),
                           hasOlder: hasOlder)
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
        // `object` zeigt auf das, worum es geht — die Datei, den Forenbeitrag,
        // die Ankündigung. Ohne diese Beziehung bliebe ein Eintrag im Verlauf
        // eine Meldung, die sich nicht öffnen lässt.
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/users/\(userID)/activitystream",
            limit: limit,
            include: ["actor", "context", "object"],
            fallback: ["actor", "context"],
            extra: extra)
        return document.resources
            .compactMap {
                ActivityItem($0,
                             actor: document.related("actor", of: $0),
                             context: document.related("context", of: $0),
                             object: document.related("object", of: $0))
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
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return [] }
        var extra = [
            URLQueryItem(name: "filter[q]", value: query),
            URLQueryItem(name: "filter[fields]", value: field.rawValue),
        ]
        // **Kein `filter[semester]=all`.** Der Vorgabewert *innerhalb* von
        // `CoursesIndex::getContextFilters()` heißt zwar `'all'`, aber
        // `validateFilters()` läuft vorher und schlägt jeden mitgeschickten
        // Wert durch `Semester::find()`. Für "all" findet es nichts und
        // antwortet mit `400 Invalid "semester"` — die Veranstaltungssuche
        // lieferte deshalb *nie* ein Ergebnis, egal was man eingab. Der
        // Parameter darf nur mit einer echten Semester-ID auftauchen.
        if let semesterID, semesterID != "all" {
            extra.append(URLQueryItem(name: "filter[semester]", value: semesterID))
        }
        return try await fresh.get("/v1/courses", limit: limit, extra: extra)
            .resources.compactMap(Course.init)
    }

    // MARK: - Forum

    func forumCategories(of course: Course) async throws -> [ForumCategory] {
        try await listAllowingAbsence {
            try await get("/v1/courses/\(course.id)/forum-categories", limit: 100)
                .resources.compactMap(ForumCategory.init)
                .sorted { $0.position < $1.position }
        }
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

    /// Die Wikiseiten einer Veranstaltung.
    ///
    /// **Ein leeres Wiki ist ein 404.** `WikiIndex` wirft eine
    /// `RecordNotFoundException`, sobald `WikiPage::findBySQL` für den Kurs
    /// nichts findet — es gibt keine leere Liste. Ungefiltert erschien in der
    /// App deshalb „Nicht gefunden — vielleicht wurde der Eintrag entfernt",
    /// wo in Wahrheit nur nie jemand eine Seite angelegt hat.
    func wikiPages(of course: Course, limit: Int = 100) async throws -> [WikiPage] {
        let pages = try await listAllowingAbsence {
            try await get("/v1/courses/\(course.id)/wiki-pages", limit: limit)
                .resources.compactMap(WikiPage.init)
        }
        // Die Startseite heißt in Stud.IP immer „WikiWikiWeb" und gehört
        // nach oben, alles Weitere alphabetisch.
        return pages.sorted {
            if $0.isStartPage != $1.isStartPage { return $0.isStartPage }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
    ///
    /// Zwei Eigenheiten, die man in `Routes\Studygroups\Proposals` nachliest
    /// und der Antwort sonst nicht ansieht: Die Auswahl wird **gemischt**
    /// (`shuffle`) und dann abgeschnitten — zweimal Laden ergibt zwei
    /// verschiedene Listen. Und die Vorschläge sind ausdrücklich Gruppen, in
    /// denen man **nicht** Mitglied ist (`NOT EXISTS … seminar_user`); die
    /// eigenen Studiengruppen stehen hier nie.
    func studygroupProposals(limit: Int = 12) async throws -> [Course] {
        try await listAllowingAbsence {
            try await fresh.get("/v1/studygroup-proposals", limit: limit)
                .resources.compactMap(Course.init)
        }
    }

    /// Die **eigenen** Studiengruppen — aus den belegten Veranstaltungen
    /// herausgefiltert.
    ///
    /// Eine eigene Route dafür gibt es nicht (siehe `StudygroupKinds`), also
    /// wird die ohnehin vorhandene Veranstaltungsliste nach den Arten
    /// durchsucht, die zur Studiengruppen-Klasse gehören. Ohne
    /// Semesterfilter, weil Studiengruppen oft semesterübergreifend laufen.
    func studygroups(for userID: String, kinds: StudygroupKinds) async throws -> [Course] {
        guard kinds.isKnown else { return [] }
        return try await courses(for: userID)
            .filter { kinds.contains($0.typeID) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Studiengruppen im ganzen Stud.IP durchsuchen.
    ///
    /// `filter[category]` ist die Klassen-ID (`SEM_CLASS`) — damit liefert die
    /// gewöhnliche Veranstaltungssuche ausschließlich Studiengruppen.
    func searchStudygroups(_ term: String,
                           classID: String,
                           limit: Int = 60) async throws -> [Course] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return [] }
        return try await fresh.get("/v1/courses", limit: limit, extra: [
            URLQueryItem(name: "filter[q]", value: query),
            URLQueryItem(name: "filter[fields]", value: "all"),
            URLQueryItem(name: "filter[category]", value: classID),
        ]).resources.compactMap(Course.init)
    }

    /// Beitreten läuft wie bei jeder Veranstaltung über die Weboberfläche —
    /// die JSON:API kennt kein Ein- und Austragen.
    static func studygroupURL(courseID: String) -> URL {
        courseURL(courseID: courseID)
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
