import Foundation

/// Attributnamen stammen direkt aus den Stud.IP-6.0-Schemas
/// (lib/classes/JsonApi/Schemas), siehe docs/API-NOTES.md.

struct StudIPUser: Identifiable, Equatable {
    let id: String
    let username: String
    let formattedName: String
    let givenName: String?
    let familyName: String?
    let email: String?

    init?(_ resource: Resource) {
        guard resource.type == "users" else { return nil }
        id = resource.id
        username = resource.string("username") ?? ""
        formattedName = resource.string("formatted-name") ?? username
        givenName = resource.string("given-name")
        familyName = resource.string("family-name")
        email = resource.string("email")
    }

    var initials: String {
        let parts = [givenName, familyName].compactMap { $0?.first }.map(String.init)
        return parts.isEmpty ? String(formattedName.prefix(1)) : parts.joined()
    }
}

struct Course: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let courseNumber: String?
    let courseType: String?
    let location: String?
    let description: String?

    init?(_ resource: Resource) {
        guard resource.type == "courses" else { return nil }
        id = resource.id
        title = resource.string("title") ?? "Ohne Titel"
        subtitle = resource.string("subtitle")?.nilIfEmpty
        courseNumber = resource.string("course-number")?.nilIfEmpty
        courseType = resource.string("course-type")?.nilIfEmpty
        location = resource.string("location")?.nilIfEmpty
        description = resource.string("description")?.nilIfEmpty
    }
}

/// Ein Eintrag im persönlichen Stundenplan — wiederkehrend, daher Wochentag
/// plus Uhrzeit statt eines konkreten Datums.
///
/// `/v1/users/{id}/schedule` mischt **zwei** Ressourcentypen: selbst angelegte
/// `schedule-entries` und die Turnustermine belegter Veranstaltungen als
/// `seminar-cycle-dates`. Beide haben dieselben Kernattribute, nur die
/// Raumangabe gibt es ausschließlich beim Veranstaltungstermin.
struct ScheduleEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let weekday: Int
    let start: String
    let end: String
    let location: String?
    let isCourse: Bool

    init?(_ resource: Resource) {
        let courseCycle = resource.type == "seminar-cycle-dates"
        guard resource.type == "schedule-entries" || courseCycle else { return nil }
        id = resource.id
        title = resource.string("title") ?? "Termin"
        description = resource.string("description")?.nilIfEmpty
        weekday = resource.int("weekday") ?? 1
        start = resource.string("start") ?? "00:00"
        end = resource.string("end") ?? "00:00"
        isCourse = courseCycle
        // `locations` ist eine Liste von Raumnamen; mehr als der erste passt
        // in eine Listenzeile ohnehin nicht.
        location = (resource.attributes["locations"] as? [String])?
            .first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Die Tabelle beginnt bewusst bei 0 und endet doppelt auf Sonntag: so
    /// stimmt die Beschriftung sowohl für Stud.IPs 1 = Montag … 7 = Sonntag
    /// als auch für Datenbestände, die bei 0 = Sonntag zählen.
    var weekdayName: String {
        let names = ["Sonntag", "Montag", "Dienstag", "Mittwoch",
                     "Donnerstag", "Freitag", "Samstag", "Sonntag"]
        return names.indices.contains(weekday) ? names[weekday] : "Unbekannt"
    }

    var timeRange: String { "\(start) – \(end)" }
}

/// Ein konkreter Termin mit Datum.
///
/// Zwei Endpunkte liefern dasselbe fachliche Ding unter verschiedenen Typen:
/// `/v1/courses/{id}/events` gibt `course-events` (inklusive Ausfallterminen),
/// `/v1/users/{id}/events` gibt `calendar-events` aus dem persönlichen
/// Kalender. Beide teilen sich hier ein Modell.
struct CourseEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let start: Date
    let end: Date
    let location: String?
    let category: String?
    let isCancelled: Bool
    let courseID: String?

    init?(_ resource: Resource) {
        guard resource.type == "course-events" || resource.type == "calendar-events",
              let start = resource.date("start") else { return nil }
        id = resource.id
        title = resource.string("title")?.nilIfEmpty ?? "Termin"
        description = resource.string("description")?.nilIfEmpty
        self.start = start
        end = resource.date("end") ?? start
        location = resource.string("location")?.nilIfEmpty
        category = resource.string("categories")?.nilIfEmpty
        // Nur `course-events` kennen ausgefallene Termine.
        isCancelled = resource.bool("is-cancelled")
        courseID = resource.relatedID("owner")
    }
}

struct Message: Identifiable, Equatable {
    let id: String
    let subject: String
    let body: String
    let sentAt: Date?
    let isRead: Bool
    let senderName: String?
    let senderID: String?

    init?(_ resource: Resource, sender: Resource? = nil) {
        guard resource.type == "messages" else { return nil }
        id = resource.id
        subject = resource.string("subject")?.nilIfEmpty ?? "(kein Betreff)"
        body = resource.string("message") ?? ""
        sentAt = resource.date("mkdate")
        isRead = resource.bool("is-read")
        senderName = sender.flatMap { $0.string("formatted-name") ?? $0.string("username") }
        senderID = sender?.id ?? resource.relatedID("sender")
    }
}

struct NewsItem: Identifiable, Equatable {
    let id: String
    let title: String
    let content: String
    let publishedAt: Date?
    let authorName: String?

    init?(_ resource: Resource, author: Resource? = nil) {
        guard resource.type == "news" else { return nil }
        id = resource.id
        title = resource.string("title")?.nilIfEmpty ?? "Ankündigung"
        content = resource.string("content") ?? ""
        publishedAt = resource.date("publication-start") ?? resource.date("mkdate")
        authorName = author.flatMap { $0.string("formatted-name") ?? $0.string("username") }
    }
}

struct Semester: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date?
    let end: Date?
    let isCurrent: Bool

    init?(_ resource: Resource) {
        guard resource.type == "semesters" else { return nil }
        id = resource.id
        title = resource.string("title") ?? ""
        start = resource.date("start")
        end = resource.date("end")
        isCurrent = resource.bool("is-current")
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Stud.IP liefert Beschreibungen und Nachrichten teils als HTML.
    var strippingHTML: String {
        replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct Folder: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String?
    let isEmpty: Bool
    let isReadable: Bool

    init?(_ resource: Resource) {
        guard resource.type == "folders" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? "Ordner"
        description = resource.string("description")?.nilIfEmpty
        isEmpty = resource.bool("is-empty")
        isReadable = resource.bool("is-readable")
    }
}

struct FileRef: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let mimeType: String?
    let size: Int?
    let changedAt: Date?
    let isDownloadable: Bool

    init?(_ resource: Resource) {
        guard resource.type == "file-refs" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? "Datei"
        mimeType = resource.string("mime-type")?.nilIfEmpty
        size = resource.int("filesize")
        changedAt = resource.date("chdate")
        isDownloadable = resource.bool("is-downloadable")
    }

    var formattedSize: String? {
        guard let size else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// SF-Symbol passend zum Dateityp — reine Optik, kein Verlass auf den MIME-Typ.
    var symbolName: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx", "odt", "rtf": return "doc.text"
        case "xls", "xlsx", "ods", "csv": return "tablecells"
        case "ppt", "pptx", "odp": return "rectangle.on.rectangle"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        default: return "doc"
        }
    }
}

/// Teilnehmende einer Veranstaltung. `label` liefert Stud.IP bereits fertig
/// übersetzt ("Studierende", "Lehrende", …).
struct Participant: Identifiable, Equatable {
    let id: String
    let name: String
    let username: String?
    let role: String?

    init?(membership: Resource, user: Resource?) {
        guard membership.type == "course-memberships" else { return nil }
        id = membership.id
        name = user?.string("formatted-name") ?? user?.string("username") ?? "Unbekannt"
        username = user?.string("username")
        role = membership.string("label")?.nilIfEmpty ?? membership.string("permission")?.nilIfEmpty
    }
}
