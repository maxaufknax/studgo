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
    /// `course-type` ist im Stud.IP-Schema ein `(int)` — die ID einer
    /// Veranstaltungsart, die je Installation anders belegt ist. Den Klartext
    /// dazu ("Vorlesung", "Seminar") liefert `/v1/sem-types`; als String
    /// gelesen war das Feld immer `nil` und die Art nie sichtbar.
    let typeID: Int?
    let location: String?
    let description: String?
    let miscellaneous: String?

    init?(_ resource: Resource) {
        guard resource.type == "courses" else { return nil }
        id = resource.id
        title = resource.string("title") ?? "Ohne Titel"
        subtitle = resource.string("subtitle")?.nilIfEmpty
        courseNumber = resource.string("course-number")?.nilIfEmpty
        typeID = resource.int("course-type")
        location = resource.string("location")?.nilIfEmpty
        description = resource.string("description")?.nilIfEmpty
        miscellaneous = resource.string("miscellaneous")?.nilIfEmpty
    }

    /// Kürzt den Titel um eine vorangestellte Veranstaltungsnummer — Stud.IP
    /// trägt sie an manchen Stellen doppelt.
    var shortTitle: String {
        guard let courseNumber, title.hasPrefix(courseNumber) else { return title }
        return title.dropFirst(courseNumber.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–:"))
            .nilIfEmpty ?? title
    }
}

/// Klartext zu den Veranstaltungsarten aus `/v1/sem-types`.
struct SemType: Identifiable, Equatable {
    let id: String
    let name: String
    /// Zu welcher Veranstaltungsklasse die Art gehört — daran hängt, ob es
    /// sich um eine Studiengruppe handelt.
    let classID: String?

    init?(_ resource: Resource) {
        guard resource.type == "sem-types" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? ""
        classID = resource.relatedID("sem-class") ?? resource.relatedID("class")
    }
}

/// Was in dieser Stud.IP-Installation eine Studiengruppe ist.
///
/// Studiengruppen sind **keine eigene Ressource**: Es sind gewöhnliche
/// Veranstaltungen, die zu einer Veranstaltungsklasse mit `studygroup_mode`
/// gehören. Dieses Kennzeichen steht aber in **keinem** Schema — weder
/// `courses` noch `sem-classes` geben es heraus (`Schemas/SemClass.php` führt
/// nur `name`, `bereiche`, `visible` und Ähnliches auf). Aus der Antwort
/// allein ist eine Studiengruppe also nicht zu erkennen.
///
/// Der Umweg, der trotzdem trägt: `/v1/studygroup-proposals` filtert
/// serverseitig `status IN (:studygroup_types)`. Was von dort kommt, **ist**
/// per Konstruktion eine Studiengruppe. Über deren `course-type` und die
/// Klassenzuordnung aus `/v1/sem-types` (die ihre `sem-class`-Beziehung immer
/// mitliefert) ergibt sich der Rest: alle Arten derselben Klasse und die
/// Klassen-ID für `filter[category]` der Suche.
struct StudygroupKinds: Equatable {
    /// Alle Veranstaltungsarten, die zur Studiengruppen-Klasse gehören.
    let typeIDs: Set<Int>
    /// Die Klasse selbst — Filterwert für die Suche.
    let classID: String?

    static let unknown = StudygroupKinds(typeIDs: [], classID: nil)

    var isKnown: Bool { !typeIDs.isEmpty }

    /// Leitet die Zuordnung aus einer Handvoll bekannter Studiengruppen und
    /// der vollständigen Artenliste ab.
    init(proposals: [Course], semTypes: [SemType]) {
        let seeded = Set(proposals.compactMap(\.typeID))
        guard !seeded.isEmpty else {
            self = .unknown
            return
        }
        // Die Klasse einer belegten Art gilt für alle ihre Geschwister.
        let classes = Set(semTypes
            .filter { Int($0.id).map(seeded.contains) ?? false }
            .compactMap(\.classID))
        let siblings = semTypes
            .filter { $0.classID.map(classes.contains) ?? false }
            .compactMap { Int($0.id) }
        typeIDs = seeded.union(siblings)
        classID = classes.sorted().first
    }

    private init(typeIDs: Set<Int>, classID: String?) {
        self.typeIDs = typeIDs
        self.classID = classID
    }

    func contains(_ typeID: Int?) -> Bool {
        guard let typeID else { return false }
        return typeIDs.contains(typeID)
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
    /// Bei `seminar-cycle-dates` zeigt `owner` auf die Veranstaltung. Damit
    /// bekommt der Block im Stundenplan dieselbe Farbe wie der Kurs in der
    /// Kursliste — und lässt sich von dort aus öffnen.
    let courseID: String?

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
        let owner = resource.relatedReference("owner")
        courseID = owner?.type == "courses" ? owner?.id : nil
        // `locations` ist eine Liste von Raumnamen; mehr als der erste passt
        // in eine Listenzeile ohnehin nicht.
        location = (resource.attributes["locations"] as? [String])?
            .first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Stud.IP zählt 1 = Montag … 7 = Sonntag, ältere Bestände schreiben für
    /// Sonntag eine 0. Alles Weitere rechnet mit dieser einen Lesart.
    var normalizedWeekday: Int {
        weekday == 0 ? 7 : min(max(weekday, 1), 7)
    }

    var weekdayName: String {
        TimetableView.fullName(normalizedWeekday)
    }

    var timeRange: String { "\(start) – \(end)" }

    /// Seed für die Kursfarbe — bevorzugt die Veranstaltung, damit derselbe
    /// Kurs überall gleich eingefärbt ist.
    var tintSeed: String { courseID ?? title }

    /// "14:15" → 855. Das Wochenraster rechnet in Minuten ab Mitternacht.
    static func minutes(_ clock: String) -> Int {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    var startMinutes: Int { Self.minutes(start) }
    var endMinutes: Int { max(Self.minutes(end), startMinutes + 30) }
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
    /// Der von Stud.IP fertig formulierte Turnus ("wöchentlich", "einmalig").
    /// Beide Terminarten liefern ihn im Attribut `recurrence`.
    let recurrence: String?
    let isCancelled: Bool
    /// Persönlicher Kalendereintrag statt Veranstaltungstermin.
    let isPersonal: Bool
    /// Nur gesetzt, wenn `owner` wirklich auf eine Veranstaltung zeigt: bei
    /// `calendar-events` ist der Besitzer oft die eigene Person, und ein
    /// Nutzer-Kürzel als Kursbezug wäre schlicht falsch.
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
        recurrence = resource.string("recurrence")?.nilIfEmpty
        // Nur `course-events` kennen ausgefallene Termine.
        isCancelled = resource.bool("is-cancelled")
        let owner = resource.relatedReference("owner")
        isPersonal = resource.type == "calendar-events" && owner?.type != "courses"
        courseID = owner?.type == "courses" ? owner?.id : nil
    }

    /// Bei `course-events` steht im Titel der Veranstaltungsname und im
    /// Beschreibungsfeld das Thema der Sitzung. In der Terminliste einer
    /// Veranstaltung ist deshalb das Thema die eigentliche Information.
    var topic: String? { description.map(StudipMarkup.plain)?.nilIfEmpty }

    /// Macht aus einem wiederkehrenden Stundenplaneintrag die konkrete
    /// Sitzung eines Tages.
    ///
    /// Nötig, weil `/v1/users/{id}/events` nur den **persönlichen** Kalender
    /// liefert (die Route filtert auf `range_id = user`); Veranstaltungstermine
    /// hängen am Kurs. Ohne diese Ableitung bliebe der Startbildschirm für die
    /// meisten Studierenden leer, obwohl der Stundenplan voll ist.
    init(entry: ScheduleEntry, on day: Date) {
        id = "plan-\(entry.id)-\(Int(day.timeIntervalSince1970))"
        title = entry.title
        description = entry.description
        start = day.addingTimeInterval(TimeInterval(entry.startMinutes * 60))
        end = day.addingTimeInterval(TimeInterval(entry.endMinutes * 60))
        location = entry.location
        category = nil
        recurrence = entry.isCourse ? "wöchentlich" : nil
        // Ob eine Sitzung ausfällt, weiß nur `/v1/courses/{id}/events` —
        // das wäre eine Anfrage je Veranstaltung.
        isCancelled = false
        isPersonal = !entry.isCourse
        courseID = entry.courseID
    }

    /// Ein Termin aus dem ICS-Strom (`GET /users/{id}/events.ics`).
    ///
    /// Das ist die einzige Quelle, die **echte** Sitzungen der belegten
    /// Veranstaltungen mit Datum liefert — samt Raum, Thema und Ausfällen,
    /// und zwar bis weit ins kommende Semester. Siehe `ICSParser`.
    init(ics event: ICSParser.Event, courseID: String?) {
        id = event.uid
        // Stud.IP hängt bei abgesagten Sitzungen „(fällt aus)" an den Titel
        // (`prepareCourseDate`). Als Text gehört das nicht in die Zeile — die
        // Ansicht zeigt Ausfälle durchgestrichen und mit eigenem Kennzeichen.
        let cancelledMarks = ["(fällt aus)", "(cancelled)"]
        let mark = cancelledMarks.first { event.summary.localizedCaseInsensitiveContains($0) }
        isCancelled = mark != nil
        var name = event.summary
        if let mark, let range = name.range(of: mark, options: .caseInsensitive) {
            name.removeSubrange(range)
        }
        title = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Termin"

        description = event.description
        start = event.start
        end = event.end
        location = event.location
        category = event.categories
        recurrence = nil
        isPersonal = !event.isCourseDate
        self.courseID = courseID
    }

    /// Aus dem Stundenplan abgeleitet statt vom Server geholt — die
    /// Detailansicht sagt das dazu, damit niemand einen Ausfall vermisst.
    var isDerived: Bool { id.hasPrefix("plan-") }

    var tintSeed: String { courseID ?? title }

    var isOver: Bool { end < Date() }
}

struct Message: Identifiable, Equatable {
    let id: String
    let subject: String
    let body: String
    let sentAt: Date?
    let isRead: Bool
    let senderName: String?
    let senderID: String?
    /// Im Postausgang stünde als Absender die eigene Person — dort trägt
    /// erst die Empfängerliste eine Information.
    let recipientNames: [String]
    let isUrgent: Bool

    init?(_ resource: Resource, sender: Resource? = nil, recipients: [Resource] = []) {
        guard resource.type == "messages" else { return nil }
        id = resource.id
        subject = resource.string("subject")?.nilIfEmpty ?? "(kein Betreff)"
        body = resource.string("message") ?? ""
        sentAt = resource.date("mkdate")
        isRead = resource.bool("is-read")
        senderName = sender.flatMap { $0.string("formatted-name") ?? $0.string("username") }
        senderID = sender?.id ?? resource.relatedID("sender")
        recipientNames = recipients.compactMap {
            ($0.string("formatted-name") ?? $0.string("username"))?.nilIfEmpty
        }
        isUrgent = (resource.string("priority") ?? "").lowercased() == "high"
    }

    /// Wer in der Liste zu zeigen ist — je nach Fach die Gegenseite.
    func counterpart(outgoing: Bool) -> String? {
        guard outgoing else { return senderName }
        guard let first = recipientNames.first else { return nil }
        return recipientNames.count > 1
            ? "\(first) +\(recipientNames.count - 1)"
            : first
    }

    var preview: String { StudipMarkup.plain(from: body) }
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

    /// Eine Zeile für die Liste — ohne Auszeichnungszeichen.
    var preview: String { StudipMarkup.plain(from: content) }
}

struct Semester: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date?
    let end: Date?
    let lectureStart: Date?
    let lectureEnd: Date?
    let isCurrent: Bool

    init?(_ resource: Resource) {
        guard resource.type == "semesters" else { return nil }
        id = resource.id
        title = resource.string("title") ?? ""
        start = resource.date("start")
        end = resource.date("end")
        lectureStart = resource.date("start-of-lectures")
        lectureEnd = resource.date("end-of-lectures")
        isCurrent = resource.bool("is-current")
    }

    /// Läuft die Vorlesungszeit gerade?
    var isLecturePeriod: Bool {
        guard let lectureStart, let lectureEnd else { return false }
        return (lectureStart...lectureEnd).contains(Date())
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Grober Tag-Abbau. **Nur für Notfälle** — Stud.IP-Texte sind in aller
    /// Regel *keine* HTML-Dokumente, sondern eigene Auszeichnung (`**fett**`,
    /// `- Liste`, `[Text]url`); die bleibt hier stehen und landete früher
    /// wörtlich in der Anzeige. Für alles, was jemand liest, gehört
    /// `StudipMarkup` genommen.
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
    let isWritable: Bool
    /// `HomeworkFolder`, `StandardFolder`, … — nur für die Diagnose.
    let folderType: String?

    init?(_ resource: Resource) {
        guard resource.type == "folders" else { return nil }
        id = resource.id
        name = resource.string("name")?.nilIfEmpty ?? "Ordner"
        description = resource.string("description")?.nilIfEmpty
        isEmpty = resource.bool("is-empty")
        isReadable = resource.bool("is-readable")
        isWritable = resource.optionalBool("is-writable") ?? false
        folderType = resource.string("folder-type")?.nilIfEmpty
    }

    /// Die Beschreibung als lesbarer Text.
    ///
    /// Ordnerbeschreibungen aus dem Stud.IP-Assistenten sind **HTML** und
    /// tragen den `<!--HTML-->`-Marker. Als schlichtes `Text(...)` gesetzt
    /// stand in der Dateiliste wörtlich `<div><p>Verwenden Sie…` im Bild.
    var summary: String? { description.map(StudipMarkup.plain)?.nilIfEmpty }

    /// Darf hier hochgeladen werden? Stud.IP liefert das Attribut nur, wenn es
    /// den Ordnertyp auflösen kann — fehlt es, wird nicht angeboten, was
    /// hinterher am Server scheitert.
    var allowsUpload: Bool { isWritable }
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
        // Stud.IP liefert das Attribut nur mit, wenn es den Ordnertyp
        // auflösen kann. Fehlt es, wäre `false` die falsche Annahme — die
        // Datei ließe sich dann in der App nicht öffnen, obwohl der Server
        // sie herausgibt. Im Zweifel also erlauben und den Server entscheiden.
        isDownloadable = resource.optionalBool("is-downloadable") ?? true
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
    let userID: String?
    /// Die Funktionsbezeichnung der Veranstaltung, sofern gepflegt
    /// ("Übungsleitung"). Meist leer — dann trägt die Rolle.
    let label: String?
    let permission: String

    init?(membership: Resource, user: Resource?) {
        guard membership.type == "course-memberships" else { return nil }
        id = membership.id
        name = user?.string("formatted-name") ?? user?.string("username") ?? "Unbekannt"
        username = user?.string("username")
        userID = user?.id
        label = membership.string("label")?.nilIfEmpty
        permission = membership.string("permission")?.nilIfEmpty ?? "user"
    }

    /// `permission` ist die rohe Stud.IP-Stufe ("dozent", "tutor", "autor").
    /// Ungefiltert stand das so in der Teilnehmendenliste — hier der Klartext.
    var role: String {
        switch permission {
        case "dozent": return "Lehrende"
        case "tutor": return "Tutorinnen und Tutoren"
        case "autor": return "Studierende"
        case "user": return "Lesende"
        default: return "Weitere"
        }
    }

    /// Lehrende zuerst, Lesende zuletzt — alphabetisch wäre "Lehrende"
    /// hinter "Lesende" gelandet.
    var roleRank: Int {
        switch permission {
        case "dozent": return 0
        case "tutor": return 1
        case "autor": return 2
        case "user": return 3
        default: return 4
        }
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }
}
