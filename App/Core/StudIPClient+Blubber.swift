import Foundation

/// **Blubber** — Stud.IPs Unterhaltungen: Direktnachrichten, Kurs- und
/// Studiengruppenströme und der globale Blubber der ganzen Universität.
///
/// Die Weboberfläche zeigt das alles unter `dispatch.php/blubber` in *einer*
/// Liste: links die Fäden, rechts der gewählte Verlauf. StudGo bildet genau
/// das nach — Postfach → „Chats".
///
/// **Der Aufbau in Stud.IP, weil er nicht offensichtlich ist:** Ein Faden
/// (`blubber_threads`) trägt einen eigenen Text — den *Aufschlag* — und
/// darunter beliebig viele Beiträge (`blubber_comments`). Bei einem Kursfaden
/// ist der Aufschlag das, was jemand geschrieben hat, und die Beiträge sind
/// die Antworten darauf. Bei einer **Direktnachricht** und beim **globalen
/// Blubber** ist der Aufschlag dagegen *leer*: Dort steckt der ganze Verlauf
/// in den Beiträgen. Wer nur den Faden liest, sieht bei diesen beiden Sorten
/// nichts — und genau das war der Befund aus dem Testflug 1.3.0: „Noch keine
/// Beiträge", in jedem Chat.
extension StudIPClient {

    /// Der globale Blubber hat in Stud.IP eine feste Kennung — kein Zufall,
    /// sondern fest verdrahtet: `BlubberThread::findMyGlobalThreads()` nimmt
    /// den Faden über `blubber_threads.thread_id = 'global'` in die Auswahl
    /// auf, und `BlubberGlobalThread::isReadable()` gibt für jeden
    /// Angemeldeten `true`.
    ///
    /// In der Weboberfläche ist das der Strom unter
    /// `dispatch.php/blubber` — der, den man zuerst sieht. In StudGo fehlte
    /// er bis 1.3.0 vollständig, weil die Fadenliste des Postfachs alles mit
    /// `context-type = public` aussortiert.
    static let globalThreadID = "global"

    // MARK: - Fadenlisten

    /// Woher die Fäden kommen sollen. Stud.IP bedient alle Varianten mit
    /// derselben Ressource, nur unter verschiedenen Pfaden.
    enum BlubberScope {
        /// Alles, was die Person sehen darf — privat, Kurse, öffentlich.
        /// Das ist dieselbe Auswahl, die die Weboberfläche links anzeigt.
        case all
        /// **Nicht** „meine Fäden": Die Route heißt serverseitig
        /// `type = private` und sucht Fäden, in denen der Anfragende *und*
        /// `{id}` erwähnt sind. Mit der eigenen Kennung sind das die
        /// Selbstgespräche — brauchbar ist sie nur mit **fremder** Kennung,
        /// dann sind es die Direktnachrichten mit dieser Person.
        case direct(userID: String)
        /// Der öffentliche Strom der Installation.
        case publicStream
        /// Die Fäden einer Veranstaltung oder Studiengruppe.
        case course(id: String)
        /// Die Fäden einer Einrichtung.
        case institute(id: String)

        var path: String {
            switch self {
            case .all: return "/v1/blubber-threads"
            case .direct(let userID): return "/v1/users/\(userID)/blubber-threads"
            case .publicStream: return "/v1/studip/blubber-threads"
            case .course(let id): return "/v1/courses/\(id)/blubber-threads"
            case .institute(let id): return "/v1/institutes/\(id)/blubber-threads"
            }
        }
    }

    /// Blubber-Fäden samt Verfasser.
    ///
    /// `filter[search]` gibt es hier wirklich (anders als bei `/v1/users`,
    /// wo der Filter drei Zeichen verlangt).
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
    ///
    /// Der **globale Blubber** wird ausdrücklich dazugeholt: Er trägt
    /// `context-type = public` und fiele sonst durch dieselbe Sieb-Bedingung,
    /// die den öffentlichen Strom draußen hält.
    func personalBlubberThreads(for userID: String, limit: Int = 80) async throws -> [BlubberThread] {
        var collected: [String: BlubberThread] = [:]
        var firstFailure: Error?

        do {
            for thread in try await blubberThreads(.all, limit: limit)
            where thread.isGlobal || thread.context != .publicStream {
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

    /// Den globalen Blubber als Faden — für die feste Zeile ganz oben in der
    /// Chatliste. Fehlschläge sind hier kein Grund, die Liste zu verlieren.
    func globalBlubberThread() async -> BlubberThread? {
        try? await blubberThread(id: Self.globalThreadID)
    }

    // MARK: - Ein einzelner Faden

    /// Einen Faden über die **Show**-Route holen — samt Verfasser und dem
    /// Anfangsbeitrag.
    ///
    /// `GET /v1/blubber-threads/{id}` verträgt **kein** `page[...]`
    /// (`$allowedPagingParameters` ist dort leer) — deshalb ohne `limit`.
    func blubberThread(id: String) async throws -> BlubberThread? {
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/blubber-threads/\(id)",
            limit: nil,
            include: ["author"],
            fallback: [])
        guard let resource = document.first else { return nil }
        return BlubberThread(resource, author: document.related("author", of: resource))
    }

    // MARK: - Der Verlauf

    /// Ein Faden mit allem, was zu seiner Anzeige gehört.
    struct BlubberConversation {
        /// Der Faden, wie ihn die Einzelroute liefert — mit gesichertem
        /// Aufschlag. `nil`, wenn auch die Einzelroute nichts hergab.
        var thread: BlubberThread?
        /// Der Verlauf, **älteste zuerst** (Lesereihenfolge).
        var comments: [BlubberComment]
        /// Liegen noch ältere Beiträge dahinter?
        var hasOlder: Bool
        /// Was auf dem Weg hierher passiert ist — Route für Route.
        ///
        /// **Warum das mitgeführt wird:** Ein leerer Verlauf sieht in der App
        /// aus wie ein leerer Verlauf, egal ob der Faden wirklich keiner hat,
        /// die Rechte fehlen oder eine Route mit 500 antwortete. Im Testflug
        /// war genau das die Sackgasse: „Noch keine Beiträge", und niemand
        /// konnte sagen, woran es lag. Die Liste steht in der Ansicht unter
        /// „Warum ist hier nichts?" — sichtbar nur, wenn wirklich nichts kam.
        var trail: [String]
    }

    /// Der vollständige Verlauf eines Fadens — über **drei** Wege, in dieser
    /// Reihenfolge.
    ///
    /// 1. `GET /v1/blubber-threads/{id}/comments?sort=-mkdate` — der
    ///    Regelweg. Diese Route ist die einzige der ganzen API, die
    ///    Sortierung zulässt (`$allowedSortFields = ['mkdate']`); ohne `sort`
    ///    schneidet sie mit `LIMIT/OFFSET` **vorne** ab und liefert damit den
    ///    Anfang eines Fadens statt seines Endes.
    /// 2. Dieselbe Route **ohne** `sort`. Antwortet eine Fassung auf das
    ///    `sort` mit 400, steht der Verlauf so wenigstens da — ältestezuerst,
    ///    also gleich in Lesereihenfolge.
    /// 3. `GET /v1/blubber-threads/{id}?include=comments` — die Beiträge als
    ///    *eingeschlossene* Ressourcen der Show-Route.
    ///
    /// **Warum Weg 3 überhaupt:** Er läuft serverseitig durch völlig anderen
    /// Code. `CommentsByThreadIndex` baut eine eigene SQL-Abfrage mit
    /// `LIMIT`/`OFFSET` und Sortierung zusammen; die Show-Route reicht
    /// dagegen schlicht die `has_many`-Beziehung `$thread->comments` an den
    /// Serialisierer. Was auch immer den ersten beiden Wegen im Weg steht —
    /// Rechteprüfung, Seitenparameter, ein Datensatz, der sich nicht
    /// sortieren lässt —, Weg 3 ist davon nicht betroffen. Er holt dafür
    /// *alle* Beiträge auf einmal, taugt also nicht als Regelweg für einen
    /// Faden mit tausend Beiträgen; als Rettungsanker ist er richtig.
    func blubberConversation(id: String,
                             limit: Int = 60,
                             offset: Int = 0) async throws -> BlubberConversation {
        var trail: [String] = []

        // Der Faden selbst zuerst: Bei einem Kursfaden steht danach schon der
        // Aufschlag im Bild, während der Verlauf noch lädt.
        var thread: BlubberThread?
        do {
            thread = try await blubberThread(id: id)
            trail.append("Faden: geladen")
        } catch {
            trail.append("Faden: \(Self.reason(error))")
        }

        // Weg 1 und 2 — die Kommentarroute.
        for sorted in [true, false] {
            do {
                let page = try await blubberComments(threadID: id,
                                                     limit: limit,
                                                     offset: offset,
                                                     sorted: sorted)
                let label = sorted ? "Beiträge (sort=-mkdate)" : "Beiträge (unsortiert)"
                if !page.comments.isEmpty {
                    trail.append("\(label): \(page.comments.count)")
                    return BlubberConversation(thread: thread,
                                               comments: page.comments,
                                               hasOlder: page.hasOlder,
                                               trail: trail)
                }
                trail.append("\(label): keine")
                // Kam eine gültige, leere Antwort *ohne* Sortierung, ist der
                // Faden mit einiger Sicherheit wirklich leer — der zweite
                // Anlauf mit demselben Ergebnis bringt nichts Neues.
                if !sorted { break }
            } catch {
                trail.append("Beiträge (\(sorted ? "sortiert" : "unsortiert")): \(Self.reason(error))")
            }
        }

        // Weg 3 — die Beiträge über die Show-Route.
        do {
            let included = try await blubberCommentsViaThread(id: id)
            trail.append("Beiträge über den Faden: \(included.count)")
            if !included.isEmpty {
                // Blättern gibt es auf diesem Weg nicht: Es kam ohnehin alles.
                return BlubberConversation(thread: thread,
                                           comments: included,
                                           hasOlder: false,
                                           trail: trail)
            }
        } catch {
            trail.append("Beiträge über den Faden: \(Self.reason(error))")
        }

        return BlubberConversation(thread: thread, comments: [], hasOlder: false, trail: trail)
    }

    /// Ein Ausschnitt aus einem Blubber-Verlauf, älteste zuerst gesetzt.
    struct BlubberPage {
        let comments: [BlubberComment]
        /// Liegen noch ältere Beiträge dahinter?
        let hasOlder: Bool
    }

    /// Die Beiträge eines Fadens über `…/comments` — die neuesten zuerst
    /// geholt, für die Anzeige dann in Lesereihenfolge gedreht.
    func blubberComments(threadID: String,
                         limit: Int = 60,
                         offset: Int = 0,
                         sorted: Bool = true) async throws -> BlubberPage {
        // Einen mehr anfragen, als gezeigt wird: daran ist zu erkennen, ob
        // sich das Nachladen älterer Beiträge überhaupt lohnt.
        let document = try await documentAllowingMissingIncludes(
            path: "/v1/blubber-threads/\(threadID)/comments",
            limit: limit + 1,
            offset: offset,
            include: ["author"],
            fallback: [],
            sort: sorted ? "-mkdate" : nil)

        let parsed = document.resources
            .compactMap { BlubberComment($0, author: document.related("author", of: $0)) }

        if sorted {
            // `reversed()` liefert eine `ReversedCollection`, kein Array.
            return BlubberPage(comments: Array(parsed.prefix(limit).reversed()),
                               hasOlder: parsed.count > limit)
        }
        return BlubberPage(comments: Array(parsed.prefix(limit)), hasOlder: false)
    }

    /// Die Beiträge, wie die **Show**-Route sie als eingeschlossene
    /// Ressourcen mitgibt.
    ///
    /// Drei Anläufe, weil `include` je nach Fassung und Rechtelage
    /// unterschiedlich weit trägt: erst mit den Verfassern der Beiträge
    /// (verschachtelter Pfad `comments.author`), dann ohne, zuletzt gar
    /// nicht — dann bleibt die Beziehung ohne Daten und es kommt nichts,
    /// aber der Aufruf scheitert wenigstens nicht.
    private func blubberCommentsViaThread(id: String) async throws -> [BlubberComment] {
        let path = "/v1/blubber-threads/\(id)"
        var lastError: Error?

        for include in [["author", "comments.author"], ["comments.author"], ["comments"]] {
            do {
                let document = try await get(path, include: include)
                let comments = document.included.values
                    .filter { $0.type == "blubber-comments" }
                    .compactMap { BlubberComment($0, author: document.related("author", of: $0)) }
                    .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                if !comments.isEmpty { return comments }
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        return []
    }

    // MARK: - Schreiben

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

    /// Einen neuen Faden aufmachen. Ohne `courseID` landet er im
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

    // MARK: - Diagnose

    /// Eine kurze, für Menschen lesbare Ursache — für die Spur in
    /// `BlubberConversation.trail`. Absichtlich knapp: Die Zeile steht in der
    /// App unter einem aufklappbaren Hinweis, nicht in einem Protokoll.
    static func reason(_ error: Error) -> String {
        guard let api = error as? APIError else { return error.localizedDescription }
        switch api {
        case .http(let code, let detail):
            return detail.map { "HTTP \(code) — \($0)" } ?? "HTTP \(code)"
        case .decoding(let text): return "unlesbar (\(text))"
        case .jsonAPI(let messages): return messages.first ?? "Fehlermeldung ohne Text"
        case .offline: return "keine Verbindung"
        }
    }
}
