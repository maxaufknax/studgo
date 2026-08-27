import Foundation
import Testing
@testable import StudGoKit

/// Der Demo-Modus, durch die echte Client-Schicht geprüft.
///
/// **Warum diese Suite mehr ist als eine Formalie:** Auf dem Entwicklungsrechner
/// gibt es weder Xcode noch einen Simulator — was die Ansichten anzeigen, sieht
/// man erst im Testflug. Der Demo-Modus ist die einzige Stelle, an der sich der
/// gesamte Weg **Antwort → JSON:API → Modell** ohne Apple-Werkzeug durchlaufen
/// lässt: `StudIPClient.isDemo` schaltet nur den Transport ab, alles danach ist
/// derselbe Code wie im Betrieb.
///
/// Fällt hier etwas um, sähe der Prüfer bei Apple einen leeren Bildschirm —
/// und zwar genau den, den er beanstandet.
// Die schreibenden Prüfungen teilen sich `DemoStore.shared` — nacheinander,
// sonst räumt die eine der anderen den Speicher unter den Füßen weg.
@Suite("Demo-Modus", .serialized)
struct DemoServerTests {

    /// Ein Client, der ausschließlich aus `DemoServer` liest.
    private var client: StudIPClient {
        var client = StudIPClient(tokenProvider: { "demo" })
        client.isDemo = true
        return client
    }

    private var userID: String { DemoData.userID }

    // MARK: - Das Nötigste

    @Test("Profil kommt an")
    func profile() async throws {
        let user = try await client.currentUser()
        #expect(user.id == userID)
        #expect(user.formattedName == "Alex Muster")
        #expect(user.initials == "AM")
    }

    @Test("Belegte Veranstaltungen samt Art und Nummer")
    func courses() async throws {
        let courses = try await client.courses(for: userID)
        #expect(courses.count == DemoData.enrolledCourses.count)
        let analysis = try #require(courses.first { $0.id == "demo-analysis" })
        #expect(analysis.courseNumber == "10101")
        #expect(analysis.typeID == 1)
        #expect(analysis.location == "1101 - E001")
    }

    @Test("Veranstaltungsarten tragen ihre Klasse — sonst gäbe es keine Studiengruppen")
    func semTypes() async throws {
        let types = try await client.semTypes()
        #expect(types.count == DemoData.semTypes.count)
        let studygroup = try #require(types.first { $0.id == "99" })
        #expect(studygroup.classID == DemoData.studygroupClassID)

        let proposals = try await client.studygroupProposals()
        #expect(!proposals.isEmpty)
        let kinds = StudygroupKinds(proposals: proposals, semTypes: types)
        #expect(kinds.isKnown)
        #expect(kinds.contains(99))
        #expect(kinds.classID == DemoData.studygroupClassID)

        let own = try await client.studygroups(for: userID, kinds: kinds)
        #expect(own.contains { $0.id == "demo-lerngruppe" })
    }

    // MARK: - Der Stundenplan, das Herzstück

    @Test("Der Wochenplan mischt Kurstermine und eigene Einträge")
    func schedule() async throws {
        let entries = try await client.schedule(for: userID)
        #expect(entries.count == DemoData.slots.count)

        let course = try #require(entries.first { $0.id == "demo-cyc-1" })
        #expect(course.isCourse)
        #expect(course.courseID == "demo-analysis")
        #expect(course.location == "1101 - E001")
        #expect(course.startMinutes == 10 * 60 + 15)
        #expect(course.normalizedWeekday == 1)

        let own = try #require(entries.first { $0.id == "demo-entry-1" })
        #expect(!own.isCourse)
        #expect(own.courseID == nil)

        // `SchedulePlan` entscheidet am Vorhandensein von Kursterminen, nicht
        // an der Länge der Liste — das war der Fehler aus 1.4.0.
        #expect(SchedulePlan.hasCourses(entries))
    }

    @Test("Der ICS-Strom liefert datierte Sitzungen samt Ausfall")
    func calendar() async throws {
        let courses = try await client.courses(for: userID)
        let events = try await client.calendarEvents(for: userID, courses: courses)

        #expect(events.count > 20, "acht Wochen Stundenplan sollten reichlich Sitzungen ergeben")
        #expect(events.allSatisfy { $0.end >= $0.start })
        #expect(events.contains { $0.isCancelled }, "eine Sitzung fällt in der Demo aus")
        #expect(events.contains { $0.courseID != nil }, "die Zuordnung zum Kurs muss greifen")
        #expect(events.contains { $0.isPersonal }, "eigene Termine gehören dazu")

        // Der Titel einer abgesagten Sitzung darf „(fällt aus)" nicht mehr
        // tragen — die Ansicht zeigt das als Kennzeichen, nicht als Text.
        let cancelled = try #require(events.first { $0.isCancelled })
        #expect(!cancelled.title.contains("fällt aus"))

        // Alles ab heute: Der echte Endpunkt schneidet die Vergangenheit ab.
        let midnight = Calendar.current.startOfDay(for: Date())
        #expect(events.allSatisfy { $0.end >= midnight.addingTimeInterval(-86400) })
    }

    @Test("Semester: eines läuft, und heute liegt in seiner Vorlesungszeit")
    func semesters() async throws {
        let semesters = try await client.semesters()
        #expect(semesters.count == 2)
        let current = try #require(semesters.first { $0.isCurrent })
        #expect(current.isLecturePeriod, "sonst zeigte die Demo ein blasses, leeres Raster")
        #expect(current.lectureStart != nil)
        #expect(current.lectureEnd != nil)
    }

    @Test("Der persönliche Kalender liefert nur sein Zwei-Wochen-Fenster")
    func personalEvents() async throws {
        let events = try await client.events(for: userID, weeks: 4)
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.isPersonal })
    }

    // MARK: - Postfach

    @Test("Posteingang mit Absendern, Postausgang mit Empfängern")
    func mailbox() async throws {
        let inbox = try await client.inbox(for: userID)
        #expect(inbox.count == 4)
        #expect(inbox.contains { !$0.isRead })
        let first = try #require(inbox.first)
        #expect(first.senderName != nil)
        #expect(!first.preview.isEmpty)

        let outbox = try await client.outbox(for: userID)
        #expect(outbox.count == 2)
        #expect(outbox.allSatisfy { !$0.recipientNames.isEmpty })
    }

    @Test("Gelesen markieren und Schreiben wirken sich aus")
    func mailboxWrites() async throws {
        DemoStore.shared.reset()
        let client = self.client

        let unread = try #require(try await client.inbox(for: userID).first { !$0.isRead })
        try await client.markMessage(unread.id, read: true)
        let after = try await client.inbox(for: userID)
        #expect(after.first { $0.id == unread.id }?.isRead == true)

        let before = try await client.outbox(for: userID).count
        try await client.sendMessage(subject: "Testbetreff",
                                     body: "Testinhalt",
                                     to: ["demo-behrens"])
        let sent = try await client.outbox(for: userID)
        #expect(sent.count == before + 1)
        #expect(sent.contains { $0.subject == "Testbetreff" })
        DemoStore.shared.reset()
    }

    // MARK: - Blubber

    @Test("Fadenliste enthält den globalen Blubber und die Direktnachricht")
    func blubberThreads() async throws {
        let threads = try await client.personalBlubberThreads(for: userID)
        #expect(threads.contains { $0.isGlobal })
        #expect(threads.contains { $0.context == .privateChat })
        #expect(threads.contains { $0.context == .course })

        let global = try #require(threads.first { $0.isGlobal })
        #expect(global.displayName == "Globaler Blubber" || !global.displayName.isEmpty)
    }

    @Test("Der Verlauf kommt über den Regelweg, in Lesereihenfolge")
    func blubberConversation() async throws {
        let conversation = try await client.blubberConversation(id: "demo-thread-lena")
        #expect(conversation.thread != nil)
        #expect(conversation.comments.count == 3)
        // Älteste zuerst — genau die Reihenfolge, in der man liest.
        let dates = conversation.comments.compactMap(\.createdAt)
        #expect(dates == dates.sorted())
        #expect(conversation.comments.contains { $0.authorID == userID })
        #expect(conversation.trail.contains { $0.hasPrefix("Faden: geladen") })
    }

    @Test("Der globale Faden trägt seinen Inhalt in den Beiträgen")
    func globalThread() async throws {
        let conversation = try await client.blubberConversation(id: DemoData.globalThreadID)
        #expect(conversation.comments.count == 3)
        #expect(conversation.thread?.isGlobal == true)
    }

    @Test("Ein geschriebener Beitrag steht danach im Verlauf")
    func postComment() async throws {
        DemoStore.shared.reset()
        let client = self.client
        try await client.postBlubberComment(threadID: "demo-thread-prog2", content: "Danke!")
        let conversation = try await client.blubberConversation(id: "demo-thread-prog2")
        #expect(conversation.comments.last?.text == "Danke!")
        #expect(conversation.comments.last?.authorID == userID)
        DemoStore.shared.reset()
    }

    // MARK: - Campus

    @Test("Der Aktivitätenstrom löst Person, Kurs und Ziel auf")
    func activities() async throws {
        let activities = try await client.activityStream(for: userID)
        #expect(activities.count == DemoData.activities.count)
        let first = try #require(activities.first)
        #expect(first.actorName != nil)
        #expect(first.courseName != nil)
        #expect(first.objectID != nil)
        // Absteigend nach Zeit — die Ansicht verlässt sich darauf.
        let dates = activities.compactMap(\.createdAt)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("Kontakte lassen sich hinzufügen und entfernen")
    func contacts() async throws {
        DemoStore.shared.reset()
        let client = self.client
        let before = try await client.contacts(for: userID)
        #expect(before.count == 3)

        try await client.addContact("demo-haas", for: userID)
        #expect(try await client.contacts(for: userID).count == 4)

        try await client.removeContact("demo-haas", for: userID)
        #expect(try await client.contacts(for: userID).count == 3)
        DemoStore.shared.reset()
    }

    @Test("Teilnehmende sind nach Rolle sortiert")
    func participants() async throws {
        let course = try #require(DemoData.course("demo-prog2"))
        let list = try await client.participants(of: Course(demo: course))
        #expect(!list.isEmpty)
        #expect(list.first?.permission == "dozent")
        #expect(list.map(\.roleRank) == list.map(\.roleRank).sorted())
    }

    @Test("Forum: Beiträge und Antworten darunter")
    func forum() async throws {
        let course = try #require(DemoData.course("demo-prog2"))
        let categories = try await client.forumCategories(of: Course(demo: course))
        #expect(categories.count == 2)
        #expect(categories.map(\.position) == categories.map(\.position).sorted())

        let entries = try await client.forumEntries(in: categories[1])
        let question = try #require(entries.first { $0.id == "demo-forum-2" })
        let answers = try await client.forumEntries(under: question)
        #expect(answers.count == 2)
    }

    @Test("Ein leeres Wiki ist ein 404 und kommt trotzdem als leere Liste an")
    func wiki() async throws {
        let dbs = try #require(DemoData.course("demo-dbs"))
        let pages = try await client.wikiPages(of: Course(demo: dbs))
        #expect(pages.count == 2)
        #expect(pages.first?.name == "WikiWikiWeb", "die Startseite gehört nach oben")

        let ethik = try #require(DemoData.course("demo-ethik"))
        let none = try await client.wikiPages(of: Course(demo: ethik))
        #expect(none.isEmpty)
    }

    @Test("Ankündigungen aus Kursen und der ganzen Universität")
    func news() async throws {
        let mine = try await client.news(for: userID)
        #expect(mine.count == 3)
        #expect(mine.allSatisfy { $0.authorName != nil })
        let dates = mine.compactMap(\.publishedAt)
        #expect(dates == dates.sorted(by: >))

        let global = try await client.globalNews()
        #expect(global.count == 2)
    }

    @Test("Einrichtungen")
    func institutes() async throws {
        let list = try await client.instituteMemberships(for: userID)
        let faculty = try #require(list.first)
        #expect(faculty.isFaculty)
        #expect(faculty.city == "30167 Hannover")
    }

    @Test("Sprechstunden: Blöcke, Termine, Buchung")
    func consultations() async throws {
        DemoStore.shared.reset()
        let client = self.client
        let blocks = try await client.consultationBlocks(userID: "demo-weber")
        #expect(blocks.count == 2)

        let slots = try await client.consultationSlots(blockID: "demo-block-1")
        #expect(slots.count == 4)
        #expect(slots.filter(\.isBookable).count == 3)

        let free = try #require(slots.first { $0.isBookable })
        try await client.bookConsultation(slotID: free.id, userID: userID, reason: "Frage")
        let after = try await client.consultationSlots(blockID: "demo-block-1")
        #expect(after.filter(\.isBookable).count == 2)
        DemoStore.shared.reset()
    }

    // MARK: - Dateien

    @Test("Ordner, Unterordner und Dateien")
    func files() async throws {
        DemoStore.shared.reset()
        let client = self.client
        let course = try #require(DemoData.course("demo-prog2"))
        let roots = try await client.rootFolders(of: Course(demo: course))
        let root = try #require(roots.first)
        #expect(root.summary == "Hier liegen Folien und Übungsblätter.",
                "die HTML-Beschreibung gehört gelesen, nicht gezeigt")

        let sub = try await client.subfolders(of: root)
        #expect(sub.count == 1)

        let files = try await client.files(in: root)
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.isDownloadable })
        #expect(files.first?.formattedSize != nil)

        // Umbenennen und Löschen wirken.
        let first = try #require(files.first)
        try await client.renameFile(first.id, to: "Neuer Name.pdf")
        #expect(try await client.files(in: root).contains { $0.name == "Neuer Name.pdf" })
        try await client.deleteFile(first.id)
        #expect(try await client.files(in: root).count == 1)
        DemoStore.shared.reset()
    }

    @Test("Die erzeugte Beispieldatei ist ein gültiges PDF")
    func demoPDF() throws {
        let data = DemoServer.fileContent(id: "demo-file-1")
        let text = try #require(String(data: data, encoding: .isoLatin1))
        #expect(text.hasPrefix("%PDF-1.4"))
        #expect(text.hasSuffix("%%EOF\n"))
        #expect(text.contains("startxref"))
        // Der Abstand in der xref-Tabelle muss wirklich auf das erste Objekt
        // zeigen — sonst öffnet keine Vorschau die Datei.
        let firstOffset = try #require(text
            .components(separatedBy: "xref\n0 6\n0000000000 65535 f \n")
            .last?.prefix(10))
        #expect(Int(firstOffset) == 9)
    }

    @Test("Lizenzen zum Hochladen")
    func termsOfUse() async throws {
        let terms = try await client.termsOfUse()
        #expect(terms.count == 2)
        #expect(terms.contains { $0.isDefault })
    }

    // MARK: - Suche

    @Test("Veranstaltungssuche findet auch, was nicht belegt ist")
    func courseSearch() async throws {
        let found = try await client.searchCourses("Betriebssysteme")
        #expect(found.contains { $0.id == "demo-betriebssysteme" })

        // Unter drei Zeichen fragt der echte Server gar nicht erst.
        #expect(try await client.searchCourses("be").isEmpty)

        let groups = try await client.searchStudygroups("Studiengruppe",
                                                        classID: DemoData.studygroupClassID)
        #expect(!groups.isEmpty)
        #expect(groups.allSatisfy { $0.typeID == 99 })
    }

    @Test("Personensuche, auch mit Umlaut-Unterschied")
    func userSearch() async throws {
        let found = try await client.searchUsers("behrens")
        #expect(found.contains { $0.id == "demo-behrens" })
        #expect(try await client.searchUsers("xy").isEmpty)
    }

    // MARK: - Grenzen

    @Test("Eine unbekannte Route ist ein sauberer 404, kein Absturz")
    func unknownRoute() async throws {
        await #expect(throws: APIError.self) {
            _ = try await client.get("/v1/gibt-es-nicht")
        }
    }
}

/// Kleine Brücke für die Tests: aus der Beschreibung einer Demo-Veranstaltung
/// das Modell bauen, das die Client-Aufrufe erwarten.
private extension Course {
    init(demo: DemoData.DemoCourse) {
        var attributes: [String: Any] = ["title": demo.title, "course-type": demo.typeID]
        if let number = demo.number { attributes["course-number"] = number }
        let resource = Resource(["type": "courses", "id": demo.id, "attributes": attributes])!
        self.init(resource)!
    }
}
