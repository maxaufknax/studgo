import Foundation

/// Beantwortet die Anfragen des `StudIPClient`, ohne dass ein Netz beteiligt
/// ist — der Kern des Demo-Modus.
///
/// **Der Aufbau in einem Satz:** Was Stud.IP unter einer Route herausgäbe,
/// baut diese Datei aus `DemoData` als JSON:API-Dokument zusammen, mit
/// denselben Typnamen und denselben Attributschlüsseln. Alles danach —
/// `JSONAPIDocument`, die Modelle, `ICSParser`, `EventMerge`, `SchedulePlan`,
/// `StudipMarkup` — läuft unverändert.
///
/// **Warum nicht einfach fertige Modelle einsetzen?** Weil die Demo dann
/// genau die Schicht überspränge, in der die Fehler dieser App sitzen: das
/// Lesen der Stud.IP-Antworten. So durchläuft sie stattdessen jede Zeile
/// davon und ist damit zugleich ein Prüfstand, der auf Linux läuft
/// (`DemoServerTests`).
///
/// **Schreiben:** Was die App schreibt — Nachricht, Blubber-Beitrag,
/// Forumsantwort, Datei, Kontakt, Buchung —, nimmt `DemoStore` entgegen und
/// gibt es beim nächsten Lesen zurück. Nichts davon überlebt den Neustart der
/// App, und nichts verlässt das Gerät.
enum DemoServer {

    // MARK: - Einstieg

    /// Die Antwort auf eine Anfrage an `jsonapi.php`.
    ///
    /// - Parameter body: Der Rumpf schreibender Aufrufe, schon als
    ///   JSON-Objekt — `StudIPClient.send` hat ihn ohnehin in dieser Form.
    static func respond(to url: URL,
                        method: String = "GET",
                        body: [String: Any]? = nil) throws -> Data {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = components?.path ?? url.path
        if path.hasPrefix("/jsonapi.php") { path.removeFirst("/jsonapi.php".count) }
        return try route(path: path,
                         query: components?.queryItems ?? [],
                         method: method.uppercased(),
                         body: body)
    }

    /// Der ICS-Strom als Text — `StudIPClient.text` erwartet keine JSON-Daten.
    static func calendarFeed() -> String { icsFeed() }

    /// Der Inhalt einer Demo-Datei. Erzeugt ein winziges, gültiges PDF, damit
    /// die Vorschau in der App wirklich etwas anzeigt.
    static func fileContent(id: String) -> Data {
        let file = DemoData.folders.flatMap(\.files).first { $0.id == id }
        let name = DemoStore.shared.fileName(id: id) ?? file?.name ?? "Datei"
        return pdf(title: name, lines: [
            "Dies ist eine Beispieldatei aus dem Demo-Modus von StudGo.",
            "",
            "Sie wurde auf dem Gerät erzeugt und stammt nicht aus Stud.IP.",
            "Im angemeldeten Betrieb steht hier die echte Datei der",
            "Veranstaltung.",
        ])
    }

    // MARK: - Wegweiser

    private static func route(path: String,
                              query: [URLQueryItem],
                              method: String,
                              body: [String: Any]?) throws -> Data {
        let parts = path.split(separator: "/").map(String.init)
        // parts[0] == "v1"
        guard parts.count >= 2, parts[0] == "v1" else { throw notFound(path) }
        let segments = Array(parts.dropFirst())
        let store = DemoStore.shared

        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        switch (segments.first ?? "", method) {

        // MARK: Personen
        case ("users", "GET"):
            return try users(segments: segments, query: query)

        case ("users", "POST"), ("users", "DELETE"):
            // /v1/users/{id}/relationships/contacts
            guard segments.count == 4, segments[2] == "relationships", segments[3] == "contacts"
            else { throw notFound(path) }
            let ids = ((body?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
            for id in ids {
                if method == "POST" { store.addContact(id) } else { store.removeContact(id) }
            }
            return Data()

        // MARK: Veranstaltungen
        case ("courses", "GET"):
            return try coursesRoute(segments: segments, query: query)

        // MARK: Semester und Arten
        case ("semesters", "GET"):
            return try document(DemoData.semesters.map(semesterResource))

        case ("sem-types", "GET"):
            return try document(DemoData.semTypes.map { type in
                resource("sem-types", type.id, ["name": type.name],
                         ["sem-class": one("sem-classes", type.classID)])
            })

        case ("studygroup-proposals", "GET"):
            let proposals = DemoData.courses.filter { !$0.enrolled && $0.typeID == 99 }
            return try document(proposals.map(courseResource))

        // MARK: Postfach
        case ("messages", "POST"):
            let attributes = ((body?["data"] as? [String: Any])?["attributes"] as? [String: Any]) ?? [:]
            let relationships = ((body?["data"] as? [String: Any])?["relationships"] as? [String: Any]) ?? [:]
            let recipients = (((relationships["recipients"] as? [String: Any])?["data"] as? [[String: Any]]) ?? [])
                .compactMap { $0["id"] as? String }
            store.sendMessage(subject: attributes["subject"] as? String ?? "",
                              body: attributes["message"] as? String ?? "",
                              recipients: recipients)
            return Data()

        case ("messages", "PATCH"):
            guard segments.count == 2 else { throw notFound(path) }
            let attributes = ((body?["data"] as? [String: Any])?["attributes"] as? [String: Any]) ?? [:]
            store.markMessage(segments[1], read: attributes["is-read"] as? Bool ?? true)
            return Data()

        // MARK: Ankündigungen
        case ("studip", "GET"):
            guard segments.count == 2 else { throw notFound(path) }
            switch segments[1] {
            case "news":
                return try newsDocument(DemoData.news.filter { $0.courseID == nil })
            case "blubber-threads":
                return try threadDocument(DemoData.threads.filter { $0.contextType == "public" })
            default:
                throw notFound(path)
            }

        case ("news", "GET"):
            // /v1/news/{id}/comments — in der Demo kommentiert niemand.
            return try document([[String: Any]]())

        // MARK: Blubber
        case ("blubber-threads", "GET"):
            return try blubberRoute(segments: segments, query: query)

        case ("blubber-threads", "POST"):
            let data = (body?["data"] as? [String: Any]) ?? [:]
            let attributes = (data["attributes"] as? [String: Any]) ?? [:]
            if segments.count == 3, segments[2] == "comments" {
                store.addComment(threadID: segments[1],
                                 content: attributes["content"] as? String ?? "")
            } else {
                let context = ((data["relationships"] as? [String: Any])?["context"] as? [String: Any])
                let contextID = ((context?["data"] as? [String: Any])?["id"] as? String)
                store.addThread(content: attributes["content"] as? String ?? "",
                                courseID: contextID)
            }
            return Data()

        // MARK: Forum
        case ("forum-categories", "GET"):
            guard segments.count == 3, segments[2] == "entries" else { throw notFound(path) }
            return try forumDocument(parentID: segments[1])

        case ("forum-entries", "GET"):
            guard segments.count == 3, segments[2] == "entries" else { throw notFound(path) }
            return try forumDocument(parentID: segments[1])

        case ("forum-entries", "POST"):
            guard segments.count == 3 else { throw notFound(path) }
            let attributes = ((body?["data"] as? [String: Any])?["attributes"] as? [String: Any]) ?? [:]
            store.addForumEntry(parentID: segments[1],
                                title: attributes["title"] as? String ?? "",
                                content: attributes["content"] as? String ?? "")
            return Data()

        // MARK: Einrichtungen
        case ("institutes", "GET"):
            guard segments.count >= 2 else { throw notFound(path) }
            if segments.count == 3, segments[2] == "blubber-threads" {
                return try threadDocument([])
            }
            return try document(instituteResource())

        // MARK: Dateien
        case ("folders", "GET"):
            guard segments.count == 3 else { throw notFound(path) }
            switch segments[2] {
            case "folders":
                return try document(subfolders(of: segments[1]).map(folderResource))
            case "file-refs":
                return try document(files(in: segments[1]).map(fileResource))
            default:
                throw notFound(path)
            }

        case ("folders", "POST"):
            guard segments.count == 3, segments[2] == "folders" else { throw notFound(path) }
            let attributes = ((body?["data"] as? [String: Any])?["attributes"] as? [String: Any]) ?? [:]
            store.addFolder(parentID: segments[1],
                            name: attributes["name"] as? String ?? "Neuer Ordner",
                            description: attributes["description"] as? String)
            return Data()

        case ("file-refs", "PATCH"):
            guard segments.count == 2 else { throw notFound(path) }
            let attributes = ((body?["data"] as? [String: Any])?["attributes"] as? [String: Any]) ?? [:]
            if let name = attributes["name"] as? String { store.renameFile(segments[1], to: name) }
            return Data()

        case ("file-refs", "DELETE"):
            guard segments.count == 2 else { throw notFound(path) }
            store.deleteFile(segments[1])
            return Data()

        case ("terms-of-use", "GET"):
            return try document(DemoData.termsOfUse.map { term in
                resource("terms-of-use", term.id,
                         ["name": term.name,
                          "description": term.description,
                          "is-default": term.isDefault])
            })

        // MARK: Sprechstunden
        case ("consultation-blocks", "GET"):
            guard segments.count == 3, segments[2] == "slots" else { throw notFound(path) }
            return try document(slots(inBlock: segments[1]))

        case ("consultation-slots", "POST"):
            guard segments.count == 3, segments[2] == "bookings" else { throw notFound(path) }
            store.book(slotID: segments[1])
            return Data()

        case ("consultation-bookings", "DELETE"):
            guard segments.count == 2 else { throw notFound(path) }
            store.cancelBooking(id: segments[1])
            return Data()

        // MARK: Eigene Mitgliedschaft
        case ("course-memberships", "PATCH"):
            guard segments.count == 2 else { throw notFound(path) }
            let attributes = ((body?["data"] as? [String: Any])?["attributes"] as? [String: Any]) ?? [:]
            store.setVisibility(membershipID: segments[1],
                                visible: (attributes["visible"] as? String ?? "yes") != "no")
            return Data()

        default:
            _ = value("filter[q]")
            throw notFound(path)
        }
    }

    // MARK: - /v1/users/…

    private static func users(segments: [String], query: [URLQueryItem]) throws -> Data {
        let store = DemoStore.shared
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        // /v1/users — Personensuche
        guard segments.count >= 2 else {
            let term = (value("filter[search]") ?? "").folded
            let found = DemoData.people.filter {
                term.isEmpty || $0.name.folded.contains(term) || $0.username.folded.contains(term)
            }
            return try document(found.map(userResource))
        }

        let id = segments[1] == "me" ? DemoData.userID : segments[1]

        guard segments.count >= 3 else {
            guard let person = DemoData.person(id) else { throw notFound(segments.joined(separator: "/")) }
            return try document(userResource(person))
        }

        switch segments[2] {
        case "courses":
            return try document(DemoData.enrolledCourses.map(courseResource))

        case "schedule":
            return try document(DemoData.slots.map(scheduleResource))

        case "events":
            let start = value("filter[timestamp]").flatMap { Double($0) }.map(Date.init(timeIntervalSince1970:))
                ?? DemoData.today
            let window = start.addingTimeInterval(14 * 24 * 3600)
            let inside = DemoData.appointments.filter { appointment in
                let day = DemoData.days(appointment.dayOffset)
                let begin = DemoData.at(appointment.start, on: day)
                return begin >= start && begin < window
            }
            return try document(inside.map(appointmentResource))

        case "inbox", "outbox":
            let outgoing = segments[2] == "outbox"
            let list = store.messages(outgoing: outgoing)
            let people = Set(list.flatMap { [$0.senderID] + $0.recipientIDs })
            return try document(list.map(messageResource),
                                included: people.compactMap(DemoData.person).map(userResource))

        case "news":
            return try newsDocument(DemoData.news.filter { $0.courseID != nil })

        case "activitystream":
            return try activityDocument()

        case "contacts":
            let ids = store.contactIDs()
            return try document(DemoData.people.filter { ids.contains($0.id) }.map(userResource))

        case "course-memberships":
            return try document(DemoData.enrolledCourses.map { membershipResource($0, person: DemoData.me) })

        case "institute-memberships":
            let membership = resource("institute-memberships", "demo-im-1",
                                      ["permission": "autor"],
                                      ["institute": one("institutes", DemoData.institute.id)])
            return try document([membership], included: [instituteResource()])

        case "consultations":
            let blocks = DemoData.consultationBlocks.filter { $0.ownerID == id || id == DemoData.userID }
            return try document(blocks.map(blockResource))

        case "blubber-threads":
            // Serverseitig „Fäden mit dieser Person" — in der Demo der
            // Direktfaden, sofern es einen gibt.
            let threads = DemoData.threads.filter { $0.contextType == "private" }
            return try threadDocument(id == DemoData.userID ? [] : threads)

        default:
            throw notFound(segments.joined(separator: "/"))
        }
    }

    // MARK: - /v1/courses/…

    private static func coursesRoute(segments: [String], query: [URLQueryItem]) throws -> Data {
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        // /v1/courses — Veranstaltungssuche
        guard segments.count >= 2 else {
            let term = (value("filter[q]") ?? "").folded
            let category = value("filter[category]")
            var found = DemoData.courses.filter {
                term.isEmpty || $0.title.folded.contains(term) || ($0.number ?? "").contains(term)
            }
            if let category, category == DemoData.studygroupClassID {
                found = found.filter { $0.typeID == 99 }
            }
            return try document(found.map(courseResource))
        }

        let id = segments[1]
        guard let course = DemoData.course(id) else {
            throw notFound(segments.joined(separator: "/"))
        }

        guard segments.count >= 3 else { return try document(courseResource(course)) }

        switch segments[2] {
        case "events":
            return try document(courseEvents(course).map { $0 })

        case "memberships":
            let staff = DemoData.people.filter { $0.role != "autor" || $0.id == DemoData.userID }
            let members = staff + DemoData.people.filter { $0.role == "autor" && $0.id != DemoData.userID }
            return try document(members.map { membershipResource(course, person: $0) },
                                included: members.map(userResource))

        case "news":
            return try newsDocument(DemoData.news.filter { $0.courseID == id })

        case "folders":
            return try document(DemoData.folders
                .filter { $0.courseID == id && $0.parentID == nil }
                .map(folderResource))

        case "forum-categories":
            return try document(DemoData.forumCategories.filter { $0.courseID == id }.map { category in
                resource("forum-categories", category.id,
                         ["title": category.title, "position": category.position])
            })

        case "wiki-pages":
            let pages = DemoData.wikiPages.filter { $0.courseID == id }
            // Ein leeres Wiki ist in Stud.IP ein 404, keine leere Liste —
            // `listAllowingAbsence` fängt das ab. Genau dieser Weg gehört
            // mitgeprüft.
            guard !pages.isEmpty else { throw APIError.http(404, "Wiki nicht gefunden") }
            return try document(pages.map { page in
                resource("wiki-pages", page.id,
                         ["name": page.name,
                          "content": page.content,
                          "chdate": DemoData.stamp(DemoData.days(-page.daysAgo)),
                          "version": page.version])
            })

        case "blubber-threads":
            return try threadDocument(DemoData.threads.filter { $0.contextID == id }
                + DemoStore.shared.extraThreads(courseID: id))

        default:
            throw notFound(segments.joined(separator: "/"))
        }
    }

    // MARK: - /v1/blubber-threads/…

    private static func blubberRoute(segments: [String], query: [URLQueryItem]) throws -> Data {
        let store = DemoStore.shared

        guard segments.count >= 2 else {
            // Alle sichtbaren Fäden — genau das, was die Weboberfläche links zeigt.
            return try threadDocument(DemoData.threads + store.extraThreads(courseID: nil))
        }

        let id = segments[1]
        guard let thread = (DemoData.threads + store.extraThreads(courseID: nil)).first(where: { $0.id == id })
        else { throw notFound(segments.joined(separator: "/")) }

        if segments.count == 3, segments[2] == "comments" {
            let sorted = query.first { $0.name == "sort" }?.value == "-mkdate"
            var list = store.comments(threadID: id)
            if sorted { list.reverse() }
            return try document(list.map(commentResource),
                                included: DemoData.people.map(userResource))
        }

        // Show-Route: Der Faden selbst, mit den Beiträgen als eingeschlossene
        // Ressourcen — Weg 3 aus `blubberConversation`.
        let include = (query.first { $0.name == "include" }?.value ?? "")
        let comments = include.contains("comments") ? store.comments(threadID: id) : []
        return try document(threadResource(thread),
                            included: comments.map(commentResource) + DemoData.people.map(userResource))
    }

    // MARK: - Ressourcen

    private static func userResource(_ person: DemoData.DemoPerson) -> [String: Any] {
        resource("users", person.id, [
            "username": person.username,
            "formatted-name": person.name,
            "given-name": person.given,
            "family-name": person.family,
            "email": person.email,
        ])
    }

    private static func courseResource(_ course: DemoData.DemoCourse) -> [String: Any] {
        var attributes: [String: Any] = [
            "title": course.title,
            "course-type": course.typeID,
            "description": course.description,
        ]
        if let subtitle = course.subtitle { attributes["subtitle"] = subtitle }
        if let number = course.number { attributes["course-number"] = number }
        if let room = course.room { attributes["location"] = room }
        return resource("courses", course.id, attributes)
    }

    private static func semesterResource(_ semester: DemoData.DemoSemester) -> [String: Any] {
        resource("semesters", semester.id, [
            "title": semester.title,
            "description": semester.title,
            "start": DemoData.stamp(semester.start),
            "end": DemoData.stamp(semester.end),
            "start-of-lectures": DemoData.stamp(semester.lectureStart),
            "end-of-lectures": DemoData.stamp(semester.lectureEnd),
            "is-current": semester.isCurrent,
        ])
    }

    private static func scheduleResource(_ slot: DemoData.DemoSlot) -> [String: Any] {
        var attributes: [String: Any] = [
            "title": slot.title,
            "weekday": slot.weekday,
            "start": slot.start,
            "end": slot.end,
        ]
        if let note = slot.note { attributes["description"] = note }
        if let room = slot.room { attributes["locations"] = [room] }
        guard let courseID = slot.courseID else {
            return resource("schedule-entries", slot.id, attributes,
                            ["owner": one("users", DemoData.userID)])
        }
        return resource("seminar-cycle-dates", slot.id, attributes,
                        ["owner": one("courses", courseID)])
    }

    private static func appointmentResource(_ appointment: DemoData.DemoAppointment) -> [String: Any] {
        let day = DemoData.days(appointment.dayOffset)
        var attributes: [String: Any] = [
            "title": appointment.title,
            "start": DemoData.stamp(DemoData.at(appointment.start, on: day)),
            "end": DemoData.stamp(DemoData.at(appointment.end, on: day)),
        ]
        if let description = appointment.description { attributes["description"] = description }
        if let location = appointment.location { attributes["location"] = location }
        return resource("calendar-events", appointment.id, attributes,
                        ["owner": one("users", DemoData.userID)])
    }

    /// Die datierten Sitzungen einer Veranstaltung — dieselben, die auch im
    /// ICS-Strom stehen.
    private static func courseEvents(_ course: DemoData.DemoCourse) -> [[String: Any]] {
        var events: [[String: Any]] = []
        for slot in DemoData.slots where slot.courseID == course.id {
            for week in 0..<6 {
                let day = DemoData.day(weekday: slot.weekday, weekOffset: week)
                guard day >= DemoData.days(-7) else { continue }
                let cancelled = slot.id == DemoData.cancelledSlotID && week == DemoData.cancelledWeekOffset
                var attributes: [String: Any] = [
                    "title": slot.title,
                    "start": DemoData.stamp(DemoData.at(slot.start, on: day)),
                    "end": DemoData.stamp(DemoData.at(slot.end, on: day)),
                    "is-cancelled": cancelled,
                    "recurrence": "wöchentlich",
                ]
                if let room = slot.room { attributes["location"] = room }
                if !slot.topics.isEmpty {
                    attributes["description"] = slot.topics[week % slot.topics.count]
                }
                events.append(resource("course-events", "\(slot.id)-w\(week)", attributes,
                                       ["owner": one("courses", course.id)]))
            }
        }
        return events
    }

    private static func messageResource(_ message: DemoStore.StoredMessage) -> [String: Any] {
        resource("messages", message.id, [
            "subject": message.subject,
            "message": message.body,
            "mkdate": DemoData.stamp(message.sentAt),
            "is-read": message.isRead,
            "priority": "normal",
        ], [
            "sender": one("users", message.senderID),
            "recipients": many(message.recipientIDs.map { ("users", $0) }),
        ])
    }

    private static func newsDocument(_ items: [DemoData.DemoNews]) throws -> Data {
        let resources = items.map { item -> [String: Any] in
            resource("news", item.id, [
                "title": item.title,
                "content": item.content,
                "mkdate": DemoData.stamp(DemoData.days(-item.daysAgo)),
                "publication-start": DemoData.stamp(DemoData.days(-item.daysAgo)),
            ], ["author": one("users", item.authorID)])
        }
        return try document(resources, included: DemoData.people.map(userResource))
    }

    private static func activityDocument() throws -> Data {
        let resources = DemoData.activities.map { activity -> [String: Any] in
            resource("activities", activity.id, [
                "title": activity.title,
                "content": activity.content,
                "verb": activity.verb,
                "activity-type": activity.type,
                "mkdate": DemoData.stamp(Date().addingTimeInterval(-Double(activity.hoursAgo) * 3600)),
            ], [
                "actor": one("users", activity.actorID),
                "context": one("courses", activity.courseID),
                "object": one(activity.objectType, activity.objectID),
            ])
        }
        var included = DemoData.people.map(userResource)
        included += DemoData.enrolledCourses.map(courseResource)
        included += DemoData.folders.flatMap(\.files).map { file in
            resource("file-refs", file.id, ["name": file.name])
        }
        included += DemoData.news.map { item in
            resource("news", item.id, ["title": item.title])
        }
        included += DemoData.wikiPages.map { page in
            resource("wiki-pages", page.id, ["name": page.name])
        }
        included += DemoData.forumEntries.map { entry in
            resource("forum-entries", entry.id, ["title": entry.title])
        }
        return try document(resources, included: included)
    }

    private static func threadResource(_ thread: DemoData.DemoThread) -> [String: Any] {
        let store = DemoStore.shared
        let latest = store.comments(threadID: thread.id).last?.createdAt
            ?? Date().addingTimeInterval(-Double(thread.hoursAgo) * 3600)
        var attributes: [String: Any] = [
            "content": thread.content,
            "context-type": thread.contextType,
            "is-commentable": true,
            "is-writable": true,
            "is-followed": false,
            "latest-activity": DemoData.stamp(latest),
            "visited-at": DemoData.stamp(latest.addingTimeInterval(-60)),
            "mkdate": DemoData.stamp(Date().addingTimeInterval(-Double(thread.hoursAgo) * 3600)),
        ]
        if let name = thread.name { attributes["name"] = name }
        if let contextID = thread.contextID, let course = DemoData.course(contextID) {
            attributes["name"] = course.title
            attributes["context-info"] = course.title
        }
        var relationships: [String: Any] = ["author": one("users", thread.authorID)]
        if let contextID = thread.contextID {
            relationships["context"] = one("courses", contextID)
        }
        // Die Zahl ungelesener Beiträge hängt in Stud.IP am Beziehungs-Link,
        // nicht bei den Attributen — genau diese Verschachtelung soll die
        // Demo mit abbilden.
        relationships["comments"] = [
            "links": ["related": ["meta": ["unseen-comments": store.unseen(threadID: thread.id)]]],
        ]
        return resource("blubber-threads", thread.id, attributes, relationships)
    }

    private static func threadDocument(_ threads: [DemoData.DemoThread]) throws -> Data {
        try document(threads.map(threadResource),
                     included: DemoData.people.map(userResource)
                        + DemoData.enrolledCourses.map(courseResource))
    }

    private static func commentResource(_ comment: DemoStore.StoredComment) -> [String: Any] {
        resource("blubber-comments", comment.id, [
            "content": comment.content,
            "mkdate": DemoData.stamp(comment.createdAt),
        ], ["author": one("users", comment.authorID)])
    }

    private static func forumDocument(parentID: String) throws -> Data {
        let entries = DemoData.forumEntries.filter { $0.parentID == parentID }
            .map { entry -> [String: Any] in
                resource("forum-entries", entry.id, [
                    "title": entry.title,
                    "content": entry.content,
                    "mkdate": DemoData.stamp(Date().addingTimeInterval(-Double(entry.hoursAgo) * 3600)),
                ])
            }
        return try document(entries + DemoStore.shared.extraForumEntries(parentID: parentID))
    }

    private static func instituteResource() -> [String: Any] {
        resource("institutes", DemoData.institute.id, [
            "name": DemoData.institute.name,
            "street": DemoData.institute.street,
            "city": DemoData.institute.city,
            "phone": DemoData.institute.phone,
            "url": DemoData.institute.url,
            "inst-type-name": DemoData.institute.type,
            "is-faculty": true,
        ])
    }

    private static func membershipResource(_ course: DemoData.DemoCourse,
                                           person: DemoData.DemoPerson) -> [String: Any] {
        let id = "demo-cm-\(course.id)-\(person.id)"
        return resource("course-memberships", id, [
            "permission": person.role,
            "group": 0,
            "visible": DemoStore.shared.isVisible(membershipID: id) ? "yes" : "no",
            "label": person.role == "tutor" ? "Übungsleitung" : "",
        ], [
            "course": one("courses", course.id),
            "user": one("users", person.id),
        ])
    }

    private static func folderResource(_ folder: DemoData.DemoFolder) -> [String: Any] {
        var attributes: [String: Any] = [
            "name": folder.name,
            "is-empty": files(in: folder.id).isEmpty && subfolders(of: folder.id).isEmpty,
            "is-readable": true,
            "is-writable": true,
            "folder-type": "StandardFolder",
        ]
        if let description = folder.description { attributes["description"] = description }
        return resource("folders", folder.id, attributes)
    }

    private static func fileResource(_ file: DemoData.DemoFile) -> [String: Any] {
        resource("file-refs", file.id, [
            "name": DemoStore.shared.fileName(id: file.id) ?? file.name,
            "mime-type": file.mime,
            "filesize": file.size,
            "chdate": DemoData.stamp(DemoData.days(file.dayOffset)),
            "is-downloadable": true,
        ])
    }

    private static func subfolders(of parentID: String) -> [DemoData.DemoFolder] {
        DemoData.folders.filter { $0.parentID == parentID } + DemoStore.shared.extraFolders(parentID: parentID)
    }

    private static func files(in folderID: String) -> [DemoData.DemoFile] {
        let store = DemoStore.shared
        let fixed = DemoData.folders.first { $0.id == folderID }?.files ?? []
        return (fixed + store.extraFiles(folderID: folderID))
            .filter { !store.isDeleted(fileID: $0.id) }
    }

    private static func blockResource(_ block: DemoData.DemoBlock) -> [String: Any] {
        let day = DemoData.days(block.dayOffset)
        return resource("consultation-blocks", block.id, [
            "start": DemoData.stamp(DemoData.at(block.start, on: day)),
            "end": DemoData.stamp(DemoData.at(block.end, on: day)),
            "room": block.room,
            "note": block.note,
            "size": 1,
            "require-reason": true,
        ], ["range": one("users", block.ownerID)])
    }

    /// Vier Viertelstunden je Block; zwei davon sind schon vergeben.
    private static func slots(inBlock blockID: String) -> [[String: Any]] {
        guard let block = DemoData.consultationBlocks.first(where: { $0.id == blockID }) else { return [] }
        let day = DemoData.days(block.dayOffset)
        let begin = DemoData.at(block.start, on: day)
        return (0..<4).map { index in
            let start = begin.addingTimeInterval(Double(index) * 900)
            let id = "\(blockID)-slot-\(index)"
            let taken = index == 1 || DemoStore.shared.isBooked(slotID: id)
            return resource("consultation-slots", id, [
                "start_time": DemoData.stamp(start),
                "end_time": DemoData.stamp(start.addingTimeInterval(900)),
                "is-bookable": !taken,
                "is-locked": false,
                "note": "",
            ])
        }
    }

    // MARK: - ICS

    /// Der Strom, den Stud.IP unter `GET /users/{id}/events.ics` ausliefert —
    /// jede Sitzung als eigenes `VEVENT`, ohne Wiederholungsregel.
    ///
    /// Die Eigenheiten des echten Exports werden mitgenommen: Kennungen der
    /// Form `Stud.IP-SEM-…` für Veranstaltungstermine (daran erkennt
    /// `ICSParser`, was aus dem persönlichen Kalender stammt) und
    /// „(fällt aus)" im `SUMMARY` einer abgesagten Sitzung.
    private static func icsFeed(weeks: Int = 8) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Stud.IP//StudGo Demo//DE",
            "CALSCALE:GREGORIAN",
        ]

        for slot in DemoData.slots {
            for week in 0..<weeks {
                let day = DemoData.day(weekday: slot.weekday, weekOffset: week)
                guard day >= DemoData.today else { continue }
                let cancelled = slot.id == DemoData.cancelledSlotID && week == DemoData.cancelledWeekOffset
                let isCourse = slot.courseID != nil
                let uid = isCourse
                    ? "Stud.IP-SEM-\(slot.id)-\(week)@studip.uni-hannover.de"
                    : "Stud.IP-\(slot.id)-\(week)@studip.uni-hannover.de"
                var summary = slot.title
                if cancelled { summary += " (fällt aus)" }
                lines += [
                    "BEGIN:VEVENT",
                    "UID:\(uid)",
                    "DTSTART;TZID=Europe/Berlin:\(icsStamp(DemoData.at(slot.start, on: day)))",
                    "DTEND;TZID=Europe/Berlin:\(icsStamp(DemoData.at(slot.end, on: day)))",
                    "SUMMARY:\(escapeICS(summary))",
                ]
                if !slot.topics.isEmpty {
                    lines.append("DESCRIPTION:\(escapeICS(slot.topics[week % slot.topics.count]))")
                } else if let note = slot.note {
                    lines.append("DESCRIPTION:\(escapeICS(note))")
                }
                if let room = slot.room { lines.append("LOCATION:\(escapeICS(room))") }
                lines.append("CATEGORIES:\(isCourse ? "Veranstaltung" : "Privater Termin")")
                lines.append("END:VEVENT")
            }
        }

        for appointment in DemoData.appointments {
            let day = DemoData.days(appointment.dayOffset)
            lines += [
                "BEGIN:VEVENT",
                "UID:Stud.IP-\(appointment.id)@studip.uni-hannover.de",
                "DTSTART;TZID=Europe/Berlin:\(icsStamp(DemoData.at(appointment.start, on: day)))",
                "DTEND;TZID=Europe/Berlin:\(icsStamp(DemoData.at(appointment.end, on: day)))",
                "SUMMARY:\(escapeICS(appointment.title))",
            ]
            if let description = appointment.description {
                lines.append("DESCRIPTION:\(escapeICS(description))")
            }
            if let location = appointment.location {
                lines.append("LOCATION:\(escapeICS(location))")
            }
            lines.append("CATEGORIES:Privater Termin")
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private static func icsStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private static func escapeICS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Bausteine

    private static func resource(_ type: String,
                                 _ id: String,
                                 _ attributes: [String: Any],
                                 _ relationships: [String: Any] = [:]) -> [String: Any] {
        var out: [String: Any] = ["type": type, "id": id, "attributes": attributes]
        if !relationships.isEmpty { out["relationships"] = relationships }
        return out
    }

    private static func one(_ type: String, _ id: String) -> [String: Any] {
        ["data": ["type": type, "id": id]]
    }

    private static func many(_ references: [(String, String)]) -> [String: Any] {
        ["data": references.map { ["type": $0.0, "id": $0.1] }]
    }

    private static func document(_ data: Any, included: [[String: Any]] = []) throws -> Data {
        var root: [String: Any] = ["data": data]
        if !included.isEmpty {
            // Doppelte Einschlüsse sind in JSON:API nicht erlaubt und würden
            // die Antwort unnötig aufblähen.
            var seen = Set<String>()
            var unique: [[String: Any]] = []
            for entry in included {
                let key = "\((entry["type"] as? String) ?? ""):\((entry["id"] as? String) ?? "")"
                if seen.insert(key).inserted { unique.append(entry) }
            }
            root["included"] = unique
        }
        if let list = data as? [[String: Any]] {
            root["meta"] = ["page": ["total": list.count]]
        }
        return try JSONSerialization.data(withJSONObject: root)
    }

    private static func notFound(_ path: String) -> APIError {
        .http(404, "Im Demo-Modus gibt es zu \(path) nichts.")
    }

    // MARK: - PDF

    /// Ein minimales, gültiges PDF mit ein paar Zeilen Text.
    ///
    /// Von Hand gebaut, weil es auf Linux keinen PDF-Erzeuger gibt und die
    /// Datei klein bleiben soll. Die `xref`-Tabelle braucht echte
    /// Byte-Abstände — deshalb werden die Objekte erst zusammengesetzt und
    /// dabei mitgezählt.
    static func pdf(title: String, lines: [String]) -> Data {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)")
        }

        var content = "BT\n/F1 16 Tf\n60 780 Td\n(\(escape(title))) Tj\n/F1 11 Tf\n"
        for line in lines {
            content += "0 -20 Td\n(\(escape(line))) Tj\n"
        }
        content += "ET\n"

        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
                + "/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream",
        ]

        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            out += String(format: "%010d 00000 n \n", offset)
        }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }
}

private extension String {
    /// Für die Suche: ohne Umlautunterschiede und Groß-/Kleinschreibung.
    var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
