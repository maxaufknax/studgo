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

    static func dayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
