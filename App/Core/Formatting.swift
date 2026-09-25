import Foundation

enum Format {
    /// "Heute, 14:00" / "Morgen, 09:15" / "Mo, 3. Nov, 14:00"
    static func eventTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute, \(time)" }
        if calendar.isDateInTomorrow(date) { return "Morgen, \(time)" }
        if calendar.isDateInYesterday(date) { return "Gestern, \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }

    /// Kurzform für Listen: heute die Uhrzeit, sonst das Datum.
    static func listDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "Mo, 3. Nov" — kompakt genug für eine Zeile neben anderen Angaben.
    static func dayShort(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Minuten ab Mitternacht als Uhrzeit — die Beschriftung der
    /// Stundenleiste im Wochenraster.
    static func clock(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Uhrzeit eines Datums als "HH:mm" — im 24-Stunden-Format, unabhängig
    /// von der Systemeinstellung.
    ///
    /// Das Formular von Stud.IP (`calendar/schedule/entry/add`) liest
    /// `start` und `end` mit `strtotime`-Semantik; „4:00 PM" käme dort falsch
    /// oder gar nicht an. Deshalb nicht `formatted(date:time:)`, sondern
    /// dieselbe feste Schreibweise, die auch `schedule-entries` liefert.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// „17. Juli" bzw. „17. Juli 2027", wenn das Jahr nicht das laufende ist.
    /// Für Sätze, in denen ein Datum genannt wird — dort ist „17.07." zu karg
    /// und die volle Jahresangabe meist überflüssig.
    static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    static func dayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
    /// Veranstaltungs- und Termintitel für die Anzeige.
    ///
    /// Stud.IP nennt dieselbe Veranstaltung je Quelle unterschiedlich: Der
    /// ICS-Strom schreibt `Course::getFullName()` — „11568  Übung: Logik und
    /// Formale Systeme", mit führender Nummer und je Einrichtung doppeltem
    /// Leerzeichen —, der Stundenplan und die Kursliste dagegen nur den Titel.
    /// Ohne Angleich sah eine Terminliste von zwei Kursen zweierlei Format
    /// aus (Rückmeldung zur Fassung 1.6.1, Screenshots IMG_1179/1180).
    ///
    /// Gekürzt wird nur, was eindeutig Zusatz ist: mehrfache Leerzeichen, eine
    /// führende Veranstaltungsnummer samt Trennraum. Alles Weitere — etwa der
    /// Zusatz „Übung:" — ist Inhalt und bleibt stehen.
    static func displayTitle(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Führende Veranstaltungsnummer: „11568 Übung: …" oder „11412 – …".
        // Nur kürzen, wenn danach noch etwas folgt — sonst wäre ein Titel aus
        // bloßen Ziffern hinterher leer.
        if let range = collapsed.range(of: "^\\d{2,6}\\s*[-–:.]?\\s*",
                                       options: .regularExpression) {
            let remainder = String(collapsed[range.upperBound...])
            if !remainder.isEmpty {
                let trimmed = remainder.trimmingCharacters(in: CharacterSet(charactersIn: " –-:"))
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return collapsed
    }
}
