import Foundation

/// Modelle für die Courseware — Stud.IPs Modul für Lerninhalte in
/// Veranstaltungen. Attributnamen stammen aus den Schemas
/// `lib/classes/JsonApi/Schemas/Courseware` (Stud.IP 6.0), siehe
/// docs/API-NOTES.md.
///
/// Courseware ist dreistufig aufgebaut:
/// **Kapitel** (`courseware-structural-elements`) enthalten
/// **Abschnitte** (`courseware-containers`) und weitere Kapitel; Abschnitte
/// enthalten **Blöcke** (`courseware-blocks`). Blöcke sind getypt — Text,
/// Video, PDF, Verweis — und tragen ihre Inhalte im Attribut `payload`, das
/// je Blocktyp anders aussieht.

/// Ein Kapitel der Courseware.
struct CoursewareChapter: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    /// Beschreibung aus dem Kapitel-`payload` — Stud.IP nennt es dort
    /// `description`.
    let summary: String?
    /// Darf die angemeldete Person dieses Kapitel sehen? Serveraussage
    /// (`can-visit`), nicht geschätzt.
    let canVisit: Bool
    let position: Int

    init?(_ resource: Resource) {
        guard resource.type == "courseware-structural-elements" else { return nil }
        id = resource.id
        title = resource.string("title")?.nilIfEmpty ?? "Kapitel"
        let payload = resource.attributes["payload"] as? [String: Any]
        summary = (payload?["description"] as? String).map(StudipMarkup.plain)?.nilIfEmpty
        canVisit = resource.bool("can-visit")
        position = resource.int("position") ?? 0
    }
}

/// Ein Abschnitt innerhalb eines Kapitels. Das Attribut `title` liefert
/// Stud.IP als Titel des Abschnittstyps — der eigentliche Name steht im
/// `payload`; ohne ihn trägt der Typ die Zeile.
struct CoursewareSection: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let kind: String
    let position: Int

    init?(_ resource: Resource) {
        guard resource.type == "courseware-containers" else { return nil }
        id = resource.id
        kind = resource.string("container-type") ?? ""
        let payload = resource.attributes["payload"] as? [String: Any]
        let name = (payload?["title"] as? String).map(StudipMarkup.plain)?.nilIfEmpty
        title = name ?? resource.string("title")?.nilIfEmpty ?? "Abschnitt"
        position = resource.int("position") ?? 0
    }
}

/// Ein Block — der Inhalt selbst. `block-type` sagt, was der Block zeigt;
/// `payload` ist je Typ anders bestückt. Für die Anzeige werden die Felder
/// herausgeholt, die textähnliche und verweisende Typen gemeinsam haben.
struct CoursewareBlock: Identifiable, Equatable {
    let id: String
    /// `text`, `typewriter`, `html`, `video`, `pdf`, `download`, `link`, …
    let blockType: String
    /// Der Klartextname des Blocktyps — bei Stud.IP das Attribut `title`.
    let typeTitle: String
    /// Eigener Titel des Blocks aus dem `payload`, sofern gepflegt.
    let title: String?
    /// Textinhalt — Text, Typewriter, Schlüsselworte und ähnliche Typen.
    let text: String?
    /// Reines HTML — der HTML-Block.
    let html: String?
    /// Ziel eines verweisenden Blocks (Verweis, eingebettete Quelle).
    let url: String?
    /// Datei-Bezug — Video, Audio, PDF, Download. Über die Beziehung
    /// `file-refs` ließe sich die Datei öffnen; dafür ist hier nur die
    /// Kennung, die Anzeige verweist auf Stud.IP.
    let fileID: String?
    let position: Int

    init?(_ resource: Resource) {
        guard resource.type == "courseware-blocks" else { return nil }
        id = resource.id
        blockType = resource.string("block-type") ?? ""
        typeTitle = resource.string("title")?.nilIfEmpty ?? blockType
        position = resource.int("position") ?? 0

        let payload = resource.attributes["payload"] as? [String: Any]
        func string(_ key: String) -> String? {
            (payload?[key] as? String).map(StudipMarkup.plain)?.nilIfEmpty
        }
        // Der HTML-Block trägt sein Markup im Schlüssel `html` — als
        // Klartext geglättet wäre es kaputt, deshalb roh.
        html = (payload?["html"] as? String)?.nilIfEmpty
        text = string("text")
        title = string("title")
        url = string("url") ?? string("source") ?? string("src")
        fileID = (payload?["file_id"] as? String)?.nilIfEmpty
    }

    /// Welcher Teil des `payload` trägt den Inhalt dieses Blocks — das
    /// entscheidet die Ansicht zwischen setzen, verweisen und überlagern.
    enum Content: Equatable {
        case formatted(String)
        case html(String)
        case link(url: String, title: String?)
        case file
        case unsupported
    }

    var content: Content {
        if let html { return .html(html) }
        if let text { return .formatted(text) }
        if let url {
            let address = URL(string: url)
            return address?.scheme == "http" || address?.scheme == "https"
                ? .link(url: url, title: title)
                : .unsupported
        }
        if fileID != nil { return .file }
        return .unsupported
    }
}
