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
}
