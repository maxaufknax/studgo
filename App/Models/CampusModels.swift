import Foundation

/// Modelle für die Bereiche, die über Stundenplan, Kurse und Postfach
/// hinausgehen: Blubber, Aktivitätenstrom, Kontakte, Forum, Wiki und
/// Einrichtungen. Attributnamen stammen aus den Stud.IP-6.0-Schemas
/// (`lib/classes/JsonApi/Schemas`), siehe docs/API-NOTES.md.

// MARK: - Blubber

/// Ein Blubber-Faden. Stud.IP kennt vier Zusammenhänge, die dieselbe
/// Ressource liefern: privat (Direktnachricht), Veranstaltung, Einrichtung
/// und öffentlich. `context-type` unterscheidet sie — davon hängt ab, ob ein
/// Faden ins Postfach gehört oder in den Campus-Bereich.
struct BlubberThread: Identifiable, Equatable, Hashable {
    enum Context: String {
        case privateChat = "private"
        case course
        case institute
        case publicStream = "public"
        case unknown

        var label: String {
            switch self {
            case .privateChat: return "Direktnachricht"
            case .course: return "Veranstaltung"
            case .institute: return "Einrichtung"
            case .publicStream: return "Öffentlich"
            case .unknown: return "Faden"
            }
        }

        var symbol: String {
            switch self {
            case .privateChat: return "bubble.left.and.bubble.right.fill"
            case .course: return "books.vertical.fill"
            case .institute: return "building.columns.fill"
            case .publicStream: return "globe.europe.africa.fill"
            case .unknown: return "bubble.left"
            }
        }
    }

    let id: String
    /// Von Stud.IP fertig gebauter Anzeigename — bei Direktnachrichten die
    /// Gegenseite, bei Veranstaltungsfäden der Kursname.
    let name: String
    let context: Context
    /// Zusatzzeile, die Stud.IP je nach Zusammenhang selbst rendert.
    let contextInfo: String?
    let content: String
    let isCommentable: Bool
    let isWritable: Bool
    let isFollowed: Bool
    let latestActivity: Date?
    let visitedAt: Date?
    let createdAt: Date?
    let authorName: String?
    let authorID: String?
    /// Ungelesene Kommentare — steht im `meta` des Beziehungs-Links,
    /// nicht bei den Attributen.
    let unseenComments: Int
    /// Auf welche Veranstaltung bzw. Einrichtung sich der Faden bezieht.
    let contextID: String?

    init?(_ resource: Resource, author: Resource? = nil) {
        guard resource.type == "blubber-threads" else { return nil }
        id = resource.id
        // `content-html` ist die von Stud.IP selbst gerenderte Fassung
        // (`formatReady()` im Schema) — Smilies, Erwähnungen und Verweise
        // stecken dort schon als HTML drin. Nur `blubber-threads` und
        // `blubber-comments` liefern das mit; überall sonst gibt es nur den
        // Rohtext. Wo es da ist, ist es die bessere Quelle.
        content = resource.string("content-html")?.nilIfEmpty
            ?? resource.string("content") ?? ""
        context = Context(rawValue: resource.string("context-type") ?? "") ?? .unknown
        contextInfo = resource.string("context-info").map(StudipMarkup.plain)?.nilIfEmpty
        isCommentable = resource.bool("is-commentable")
        isWritable = resource.bool("is-writable")
        isFollowed = resource.bool("is-followed")
        latestActivity = resource.date("latest-activity")
        visitedAt = resource.date("visited-at")
        createdAt = resource.date("mkdate")
        authorName = author.flatMap { $0.string("formatted-name") ?? $0.string("username") }
        authorID = author?.id ?? resource.relatedID("author")
        unseenComments = resource.relationshipLinkMeta("comments", "unseen-comments") ?? 0
        contextID = resource.relatedID("context")

        // `name` ist bei privaten Fäden gelegentlich leer — dann trägt der
        // Anfangsbeitrag die Überschrift, sonst stünde dort nichts.
        let given = resource.string("name")?.nilIfEmpty
        name = given ?? StudipMarkup.plain(from: content).firstLine.nilIfEmpty ?? "Ohne Titel"
    }

    /// Faden mit ungelesenen Kommentaren oder neuer als der letzte Besuch.
    var hasNews: Bool {
        if unseenComments > 0 { return true }
        guard let latestActivity, let visitedAt else { return false }
        return latestActivity > visitedAt
    }

    var preview: String { StudipMarkup.plain(from: content) }

    /// Farbschlüssel: Fäden derselben Veranstaltung bekommen deren Farbe.
    var tintSeed: String { contextID ?? id }
}

/// Ein Beitrag innerhalb eines Blubber-Fadens.
struct BlubberComment: Identifiable, Equatable {
    let id: String
    let content: String
    let createdAt: Date?
    let authorName: String?
    let authorID: String?

    init?(_ resource: Resource, author: Resource? = nil) {
        guard resource.type == "blubber-comments" else { return nil }
        id = resource.id
        // Wie beim Faden: die gerenderte Fassung, wenn Stud.IP sie mitgibt.
        content = resource.string("content-html")?.nilIfEmpty
            ?? resource.string("content") ?? ""
        createdAt = resource.date("mkdate")
        authorName = author.flatMap { $0.string("formatted-name") ?? $0.string("username") }
        authorID = author?.id ?? resource.relatedID("author")
    }

    var text: String { StudipMarkup.plain(from: content) }

    var initials: String {
        let parts = (authorName ?? "?").split(separator: " ")
            .prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }
}

// MARK: - Aktivitätenstrom

/// Ein Eintrag aus `/v1/users/{id}/activitystream` — Stud.IPs eigener
/// Nachrichtenstrom über alles, was in den belegten Veranstaltungen passiert.
struct ActivityItem: Identifiable, Equatable {
    let id: String
    let title: String
    let content: String
    /// Der unbearbeitete Text — die Detailansicht setzt ihn mit Auszeichnung.
    let rawTitle: String
    let rawContent: String
    let verb: String
    /// `documents`, `forum`, `news`, `wiki`, `schedule`, `participants`, …
    /// abgeleitet aus dem Provider-Klassennamen.
    let activityType: String?
    let createdAt: Date?
    let actorName: String?
    let actorID: String?
    /// Zeigt auf die Veranstaltung, in der die Aktivität stattfand.
    let courseID: String?
    let courseName: String?

    /// Worauf sich die Meldung bezieht — Datei, Forenbeitrag, Ankündigung,
    /// Wikiseite oder Veranstaltung. Erst damit lässt sich ein Eintrag
    /// überhaupt öffnen.
    let objectType: String?
    let objectID: String?
    /// Anzeigename des Ziels, sofern Stud.IP ihn mitgeliefert hat.
    let objectName: String?

    init?(_ resource: Resource,
          actor: Resource? = nil,
          context: Resource? = nil,
          object: Resource? = nil) {
        guard resource.type == "activities" else { return nil }
        id = resource.id
        // `title` ist ein fertig formulierter Satz ("… hat eine Datei im Kurs
        // \"…\" hochgeladen"), `content` der eigentliche Inhalt. Beide werden
        // **roh** behalten: Was davon Auszeichnung ist, entscheidet erst die
        // Anzeige — in der Liste eine Zeile, in der Detailansicht alles.
        rawTitle = resource.string("title") ?? ""
        title = StudipMarkup.plain(from: rawTitle).nilIfEmpty ?? "Aktivität"
        rawContent = resource.string("content") ?? ""
        content = StudipMarkup.plain(from: rawContent)
        verb = resource.string("verb") ?? ""
        activityType = resource.string("activity-type")?.nilIfEmpty
        createdAt = resource.date("mkdate")
        actorName = actor.flatMap { $0.string("formatted-name") ?? $0.string("username") }
        actorID = actor?.id ?? resource.relatedID("actor")
        let reference = resource.relatedReference("context")
        courseID = reference?.type == "courses" ? reference?.id : nil
        courseName = context?.type == "courses" ? context?.string("title") : nil
        let target = resource.relatedReference("object")
        objectType = target?.type ?? object?.type
        objectID = target?.id ?? object?.id
        objectName = object.flatMap {
            $0.string("name") ?? $0.string("title") ?? $0.string("subject")
        }?.nilIfEmpty
    }

    /// Symbol passend zur Art der Aktivität.
    var symbol: String {
        switch activityType {
        case "documents": return "doc.fill"
        case "forum": return "text.bubble.fill"
        case "news": return "megaphone.fill"
        case "wiki": return "book.closed.fill"
        case "schedule": return "calendar"
        case "participants": return "person.2.fill"
        case "message": return "envelope.fill"
        default: return "sparkles"
        }
    }

    var kindLabel: String {
        switch activityType {
        case "documents": return "Datei"
        case "forum": return "Forum"
        case "news": return "Ankündigung"
        case "wiki": return "Wiki"
        case "schedule": return "Termin"
        case "participants": return "Teilnahme"
        case "message": return "Nachricht"
        default: return "Neu"
        }
    }

    var tintSeed: String { courseID ?? activityType ?? id }
}

// MARK: - Forum

struct ForumCategory: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let position: Int

    init?(_ resource: Resource) {
        guard resource.type == "forum-categories" else { return nil }
        id = resource.id
        title = resource.string("title")?.nilIfEmpty ?? "Bereich"
        position = resource.int("position") ?? 0
    }
}

struct ForumEntry: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let content: String

    init?(_ resource: Resource) {
        guard resource.type == "forum-entries" else { return nil }
        id = resource.id
        title = resource.string("title")?.nilIfEmpty ?? "Beitrag"
        content = resource.string("content") ?? ""
    }

    var text: String { StudipMarkup.plain(from: content) }
}

// MARK: - Wiki

struct WikiPage: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let content: String
    let changedAt: Date?
    let version: Int

    init?(_ resource: Resource) {
        guard resource.type == "wiki-pages" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? "WikiWikiWeb"
        content = resource.string("content") ?? ""
        changedAt = resource.date("chdate")
        version = resource.int("version") ?? 1
    }

    var text: String { StudipMarkup.plain(from: content) }

    /// Die Startseite eines Stud.IP-Wikis heißt immer so.
    var isStartPage: Bool { name == "WikiWikiWeb" }
}

// MARK: - Einrichtung

struct Institute: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let street: String?
    /// Im Schema heißt das Feld `city`, gefüllt wird es aber aus `plz`.
    let city: String?
    let phone: String?
    let fax: String?
    let homepage: String?
    let typeName: String?
    let isFaculty: Bool

    init?(_ resource: Resource) {
        guard resource.type == "institutes" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? "Einrichtung"
        street = resource.string("street")?.nilIfEmpty
        city = resource.string("city")?.nilIfEmpty
        phone = resource.string("phone")?.nilIfEmpty
        fax = resource.string("fax")?.nilIfEmpty
        homepage = resource.string("url")?.nilIfEmpty
        typeName = resource.string("inst-type-name")?.nilIfEmpty
        isFaculty = resource.bool("is-faculty")
    }

    var address: String? {
        [street, city].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
    }
}

// MARK: - Eigene Mitgliedschaft

/// Die eigene Mitgliedschaft in einer Veranstaltung.
///
/// Aus `/v1/users/{id}/course-memberships`. Über `PATCH
/// /v1/course-memberships/{id}` lassen sich genau zwei Dinge ändern:
/// die **Farbgruppe** (0–9) und die **Sichtbarkeit** in der
/// Teilnehmendenliste. Ein- oder Austragen kann die JSON:API nicht —
/// siehe `StudIPClient.enrolmentURL(for:)`.
struct CourseMembership: Identifiable, Equatable {
    let id: String
    let permission: String
    let group: Int
    let isVisible: Bool
    let courseID: String?

    init?(_ resource: Resource) {
        guard resource.type == "course-memberships" else { return nil }
        id = resource.id
        permission = resource.string("permission")?.nilIfEmpty ?? "autor"
        group = resource.int("group") ?? 0
        isVisible = (resource.string("visible") ?? "yes") != "no"
        courseID = resource.relatedID("course")
    }

    var roleLabel: String {
        switch permission {
        case "dozent": return "Lehrende:r"
        case "tutor": return "Tutor:in"
        case "autor": return "Teilnehmend"
        case "user": return "Lesend"
        default: return permission
        }
    }
}

// MARK: - Kontakte

/// Eine Person aus dem eigenen Adressbuch (`/v1/users/{id}/contacts`).
struct Contact: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let username: String?
    let email: String?

    init?(_ resource: Resource) {
        guard resource.type == "users" else { return nil }
        id = resource.id
        name = resource.string("formatted-name")?.nilIfEmpty
            ?? resource.string("username")?.nilIfEmpty ?? "Unbekannt"
        username = resource.string("username")?.nilIfEmpty
        email = resource.string("email")?.nilIfEmpty
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }
}

extension String {
    /// Erste nichtleere Zeile — für Vorschauen, wo ein Absatz zu viel wäre.
    var firstLine: String {
        split(separator: "\n").first.map(String.init) ?? self
    }
}

// MARK: - Sprechstunden

/// Ein Sprechstundenblock — der Rahmen, in dem einzelne Termine liegen.
struct ConsultationBlock: Identifiable, Equatable, Hashable {
    let id: String
    let start: Date?
    let end: Date?
    let room: String?
    let note: String?
    /// Wie viele Personen sich einen Termin teilen dürfen.
    let size: Int
    let requiresReason: Bool

    init?(_ resource: Resource) {
        guard resource.type == "consultation-blocks" else { return nil }
        id = resource.id
        start = resource.date("start")
        end = resource.date("end")
        room = resource.string("room")?.strippingHTML.nilIfEmpty
        note = resource.string("note")?.strippingHTML.nilIfEmpty
        size = resource.int("size") ?? 1
        requiresReason = resource.bool("require-reason")
    }

    var dayLabel: String {
        guard let start else { return "Sprechstunde" }
        return Format.dayShort(start)
    }
}

/// Ein einzelner buchbarer Termin innerhalb eines Blocks.
///
/// Achtung: Die Zeitattribute heißen hier `start_time`/`end_time` mit
/// **Unterstrich** — anders als überall sonst in der Stud.IP-API, wo
/// Bindestriche stehen. Wer `start-time` liest, bekommt nichts.
struct ConsultationSlot: Identifiable, Equatable, Hashable {
    let id: String
    let start: Date?
    let end: Date?
    let note: String?
    let isBookable: Bool
    let isLocked: Bool

    init?(_ resource: Resource) {
        guard resource.type == "consultation-slots" else { return nil }
        id = resource.id
        start = resource.date("start_time")
        end = resource.date("end_time")
        note = resource.string("note")?.strippingHTML.nilIfEmpty
        isBookable = resource.bool("is-bookable")
        isLocked = resource.bool("is-locked")
    }

    var timeLabel: String {
        guard let start else { return "—" }
        guard let end else { return start.formatted(date: .omitted, time: .shortened) }
        return Format.timeRange(start, end)
    }

    var isPast: Bool {
        guard let start else { return false }
        return start < Date()
    }

    var statusLabel: String {
        if isPast { return "vorbei" }
        if isBookable { return "frei" }
        return isLocked ? "gesperrt" : "belegt"
    }
}
