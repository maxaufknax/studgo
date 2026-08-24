import Foundation

/// Minimaler JSON:API-Leser. Stud.IP liefert Attributnamen in kebab-case und
/// verteilt verknüpfte Ressourcen auf `included` — beides wird hier aufgelöst,
/// damit die Modelle mit einfachen Zugriffen auskommen.
struct JSONAPIDocument {
    let resources: [Resource]
    let included: [String: Resource]  // "type:id" -> Ressource
    let total: Int?

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding("Antwort ist kein JSON-Objekt")
        }
        if let errors = root["errors"] as? [[String: Any]] {
            throw APIError.jsonAPI(errors.compactMap {
                ($0["detail"] as? String) ?? ($0["title"] as? String)
            })
        }

        switch root["data"] {
        case let array as [[String: Any]]:
            resources = array.compactMap(Resource.init)
        case let object as [String: Any]:
            resources = [Resource(object)].compactMap { $0 }
        default:
            resources = []
        }

        let includedList = (root["included"] as? [[String: Any]] ?? []).compactMap(Resource.init)
        included = Dictionary(includedList.map { ("\($0.type):\($0.id)", $0) },
                              uniquingKeysWith: { first, _ in first })

        total = ((root["meta"] as? [String: Any])?["page"] as? [String: Any])?["total"] as? Int
    }

    var first: Resource? { resources.first }

    /// Löst eine to-one-Beziehung gegen `included` auf.
    func related(_ name: String, of resource: Resource) -> Resource? {
        guard let key = resource.relationshipKey(name) else { return nil }
        return included[key]
    }

    /// Dasselbe für to-many — nicht aufgelöste Gegenstücke fallen weg.
    func relatedList(_ name: String, of resource: Resource) -> [Resource] {
        resource.relatedKeys(name).compactMap { included[$0] }
    }
}

struct Resource {
    let type: String
    let id: String
    let attributes: [String: Any]
    let relationships: [String: Any]

    init?(_ raw: [String: Any]) {
        guard let type = raw["type"] as? String, let id = raw["id"] as? String else { return nil }
        self.type = type
        self.id = id
        self.attributes = raw["attributes"] as? [String: Any] ?? [:]
        self.relationships = raw["relationships"] as? [String: Any] ?? [:]
    }

    func string(_ key: String) -> String? {
        attributes[key] as? String
    }

    func bool(_ key: String) -> Bool {
        optionalBool(key) ?? false
    }

    /// Unterscheidet „steht auf false" von „steht gar nicht in der Antwort".
    /// Stud.IP blendet Attribute je nach Rechtelage aus — `is-downloadable`
    /// etwa fehlt ganz, wenn der Ordnertyp nicht ermittelt werden kann.
    /// Als `false` gelesen sperrte das Dateien, die sich sehr wohl laden lassen.
    func optionalBool(_ key: String) -> Bool? {
        if let value = attributes[key] as? Bool { return value }
        if let value = attributes[key] as? NSNumber { return value.boolValue }
        return nil
    }

    /// Stud.IP liefert Zahlen mal als JSON-Zahl, mal als Zeichenkette
    /// (`course-type` etwa ist im Schema ein `(int)`, `filesize` ebenso) —
    /// beides muss hier ankommen.
    func int(_ key: String) -> Int? {
        if let number = attributes[key] as? NSNumber { return number.intValue }
        if let text = attributes[key] as? String { return Int(text) }
        return nil
    }

    /// Stud.IP formatiert Zeitstempel durchgängig als ISO 8601 mit Zeitzone.
    func date(_ key: String) -> Date? {
        guard let raw = string(key) else { return nil }
        return ISO8601DateFormatter.studip.date(from: raw)
    }

    func relationshipKey(_ name: String) -> String? {
        guard let (type, id) = relatedReference(name) else { return nil }
        return "\(type):\(id)"
    }

    func relatedID(_ name: String) -> String? {
        relatedReference(name)?.id
    }

    /// Typ **und** ID der Gegenseite. Der Typ zählt dort, wo derselbe
    /// Beziehungsname auf Verschiedenes zeigen kann: `owner` eines
    /// `calendar-events` ist mal eine Veranstaltung, mal die eigene Person.
    func relatedReference(_ name: String) -> (type: String, id: String)? {
        guard let relation = relationships[name] as? [String: Any],
              let data = relation["data"] as? [String: Any],
              let type = data["type"] as? String,
              let id = data["id"] as? String else { return nil }
        return (type, id)
    }

    /// Gegenstücke einer to-many-Beziehung, etwa die Empfänger einer Nachricht.
    func relatedKeys(_ name: String) -> [String] {
        guard let relation = relationships[name] as? [String: Any],
              let list = relation["data"] as? [[String: Any]] else { return [] }
        return list.compactMap {
            guard let type = $0["type"] as? String, let id = $0["id"] as? String else { return nil }
            return "\(type):\(id)"
        }
    }
}

extension ISO8601DateFormatter {
    static let studip: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum APIError: LocalizedError {
    case http(Int, String?)
    case decoding(String)
    case jsonAPI([String])
    /// Kein Netz und nichts im Zwischenspeicher — das ist kein Serverfehler
    /// und soll auch nicht wie einer aussehen.
    case offline

    /// Trennt „das Token ist hinüber" von allen anderen Fehlern: nur darauf
    /// meldet die App von sich aus ab.
    var isUnauthorized: Bool {
        if case .http(let code, _) = self { return code == 401 }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .http(401, _):
            return "Die Sitzung ist abgelaufen. Bitte erneut anmelden."
        case .http(403, _):
            return "Für diesen Bereich fehlen die Rechte."
        case .http(404, _):
            return "Nicht gefunden — vielleicht wurde der Eintrag entfernt."
        case .http(let code, let detail):
            return detail.map { "Serverfehler \(code): \($0)" } ?? "Serverfehler \(code)"
        case .decoding(let reason):
            return "Die Antwort von Stud.IP war unlesbar: \(reason)"
        case .jsonAPI(let messages):
            return messages.isEmpty ? "Stud.IP hat einen Fehler gemeldet." : messages.joined(separator: "\n")
        case .offline:
            return "Keine Verbindung zu Stud.IP."
        }
    }
}
