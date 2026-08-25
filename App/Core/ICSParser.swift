import Foundation

/// Liest den iCalendar-Strom, den Stud.IP unter
/// `GET /v1/users/{id}/events.ics` ausliefert.
///
/// **Warum das die bessere Terminquelle ist:** `/v1/users/{id}/events` gibt
/// nur den *persönlichen* Kalender heraus (die Route filtert auf
/// `range_id = user`) und immer nur zwei Wochen am Stück. Die Sitzungen der
/// belegten Veranstaltungen mussten deshalb bisher aus dem Wochenraster
/// *abgeleitet* werden — mit allen Nachteilen: keine Ausfälle, keine
/// Einzeltermine, kein Thema der Sitzung, und außerhalb der Vorlesungszeit
/// gar nichts.
///
/// Der ICS-Endpunkt dagegen ruft `ICalendarExport::exportCourseDates()` und
/// `exportCourseExDates()` auf. Er liefert **jede einzelne echte Sitzung**
/// vom heutigen Tag bis 2036, samt Raum, Thema und den ausgefallenen
/// Terminen (`… (fällt aus)`) — und damit auch die des kommenden Semesters,
/// sobald man dort eingetragen ist.
///
/// **Zwei Eigenheiten des Stud.IP-Exports**, an denen ein strenger Leser
/// scheitert:
/// 1. Die Zeilen werden **nicht** nach RFC 5545 umbrochen (kein Folding auf
///    75 Zeichen) — Falten muss man trotzdem können, falls sich das ändert.
/// 2. In `DESCRIPTION` landen **echte Zeilenumbrüche**: `prepareCourseDate()`
///    fügt die Themen mit `"\n"` zusammen, `quoteText()` maskiert aber nur
///    die Zeichenfolge Backslash-n, nicht das Zeichen selbst. Solche
///    Fortsetzungszeilen beginnen ohne Leerzeichen und sind formal ungültig;
///    hier zählen sie zum vorigen Feld, statt den Rest der Datei zu verwerfen.
enum ICSParser {

    /// Ein Termin aus dem Strom, noch ohne StudGo-Bedeutung.
    struct Event {
        let uid: String
        let summary: String
        let description: String?
        let location: String?
        let categories: String?
        let start: Date
        let end: Date
        let isAllDay: Bool

        /// Stud.IP kennzeichnet Veranstaltungstermine an der Kennung
        /// (`'Stud.IP-SEM-' . $date->id . '@' . $server`). Alles andere kommt
        /// aus dem persönlichen Kalender.
        var isCourseDate: Bool { uid.hasPrefix("Stud.IP-SEM-") }
    }

    // MARK: - Einstieg

    static func events(in text: String) -> [Event] {
        var events: [Event] = []
        var fields: [String: (value: String, parameters: [String: String])] = [:]
        var inEvent = false
        var lastKey: String?

        for line in unfolded(text) {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                fields = [:]
                lastKey = nil
                continue
            }
            if line == "END:VEVENT" {
                inEvent = false
                if let event = event(from: fields) { events.append(event) }
                fields = [:]
                lastKey = nil
                continue
            }
            guard inEvent else { continue }

            guard let parsed = property(in: line) else {
                // Kein `NAME:Wert` — also die Fortsetzung des vorigen Feldes
                // (siehe die Anmerkung zu `DESCRIPTION` oben).
                if let lastKey, var previous = fields[lastKey] {
                    previous.value += "\n" + line
                    fields[lastKey] = previous
                }
                continue
            }
            fields[parsed.name] = (value: parsed.value, parameters: parsed.parameters)
            lastKey = parsed.name
        }
        return events
    }

    // MARK: - Zeilen

    /// Zeilenumbrüche auflösen und Fortsetzungszeilen nach RFC 5545
    /// (Zeilenanfang ist Leerzeichen oder Tabulator) wieder anhängen.
    private static func unfolded(_ text: String) -> [String] {
        let raw = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var lines: [String] = []
        for line in raw {
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    /// `DTSTART;TZID=Europe/Berlin:20261012T101500` →
    /// (`DTSTART`, `["TZID": "Europe/Berlin"]`, `20261012T101500`).
    private static func property(in line: String)
        -> (name: String, parameters: [String: String], value: String)? {
        // Der Doppelpunkt im Wert (etwa in einer Adresse) darf nicht zählen:
        // Der erste vor jedem Anführungszeichen trennt Name von Wert.
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])
        guard !head.isEmpty else { return nil }

        var parts = head.components(separatedBy: ";")
        let name = parts.removeFirst().uppercased()
        // Ein Name enthält nur Buchstaben, Ziffern und Bindestriche — sonst
        // war der Doppelpunkt Teil eines Fließtexts.
        guard name.range(of: "^[A-Z0-9-]+$", options: .regularExpression) != nil else { return nil }

        var parameters: [String: String] = [:]
        for part in parts {
            let pair = part.components(separatedBy: "=")
            guard pair.count == 2 else { continue }
            parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return (name: name, parameters: parameters, value: value)
    }

    // MARK: - Termin

    private static func event(from fields: [String: (value: String, parameters: [String: String])]) -> Event? {
        guard let startField = fields["DTSTART"],
              let start = date(from: startField.value, parameters: startField.parameters)
        else { return nil }

        let isAllDay = startField.parameters["VALUE"] == "DATE"
        let endField = fields["DTEND"]
        let end = endField.flatMap { date(from: $0.value, parameters: $0.parameters) }
            // Ohne Ende ist ein Termin eine Stunde lang — das ist die
            // freundlichste Annahme für die Darstellung im Raster.
            ?? start.addingTimeInterval(isAllDay ? 24 * 3600 : 3600)

        return Event(uid: unescape(fields["UID"]?.value ?? UUID().uuidString),
                     summary: unescape(fields["SUMMARY"]?.value ?? "Termin"),
                     description: unescape(fields["DESCRIPTION"]?.value ?? "").nilIfEmpty,
                     location: unescape(fields["LOCATION"]?.value ?? "").nilIfEmpty,
                     categories: unescape(fields["CATEGORIES"]?.value ?? "").nilIfEmpty,
                     start: start,
                     end: max(end, start),
                     isAllDay: isAllDay)
    }

    /// `\,` `\;` `\\` und `\n` zurückübersetzen.
    private static func unescape(_ raw: String) -> String {
        var result = ""
        var escaped = false
        for character in raw {
            if escaped {
                switch character {
                case "n", "N": result.append("\n")
                case "\\", ",", ";": result.append(character)
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Zeitangaben

    private static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private static func date(from raw: String, parameters: [String: String]) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespaces)

        // Ganztägig: `VALUE=DATE:20261012`
        if parameters["VALUE"] == "DATE" || value.count == 8 {
            return components(from: value, hasTime: false)?.date(in: zone(for: parameters))
        }
        // UTC: `20261012T081500Z`
        if value.hasSuffix("Z") {
            return components(from: String(value.dropLast()), hasTime: true)?
                .date(in: TimeZone(secondsFromGMT: 0) ?? .current)
        }
        return components(from: value, hasTime: true)?.date(in: zone(for: parameters))
    }

    private static func zone(for parameters: [String: String]) -> TimeZone {
        guard let name = parameters["TZID"], let zone = TimeZone(identifier: name) else {
            // Stud.IP schreibt für die LUH grundsätzlich Europe/Berlin; ohne
            // Angabe ist das die richtige Annahme und nicht die Gerätezone.
            return berlin
        }
        return zone
    }

    private struct Parts {
        let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int

        func date(in zone: TimeZone) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            components.second = second
            components.timeZone = zone
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: components)
        }
    }

    /// `20261012T101500` in seine Bestandteile — von Hand statt über einen
    /// `DateFormatter`: Der müsste je Zeitzone neu gebaut werden und ist in
    /// einer Schleife über tausend Termine spürbar langsamer.
    private static func components(from value: String, hasTime: Bool) -> Parts? {
        let digits = Array(value.filter(\.isNumber))
        guard digits.count >= 8 else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= digits.count else { return nil }
            return Int(String(digits[range]))
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        guard hasTime, digits.count >= 14 else {
            return Parts(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
        }
        return Parts(year: year, month: month, day: day,
                     hour: number(8..<10) ?? 0,
                     minute: number(10..<12) ?? 0,
                     second: number(12..<14) ?? 0)
    }
}
