import Foundation

/// Die gesetzlichen Feiertage in Niedersachsen - der Rahmen, in dem die
/// Vorlesungs- und Klausurenpläne der LUH stehen.
///
/// **Warum das in der App liegt und nicht im Kalender von Stud.IP:** Der
/// ICS-Strom nennt Sitzungen und persönliche Termine, aber keine Feiertage.
/// Ein Dienstag, an dem die Hochschule geschlossen hat, sähe sonst wie ein
/// freier Tag aus - die falsche Antwort auf „warum steht hier nichts".
///
/// Die Liste ist **bewusst** auf Niedersachsen beschränkt statt auf ganz
/// Deutschland: Die App ist auf die LUH eingerichtet, und Feiertage sind
/// Ländersache - ein bundesweiter Mix (etwa Fronleichnam) wäre in Hannover
/// schlicht falsch. Alle hier aufgeführten Tage sind im
/// Niedersächsischen Feiertagsgesetz benannt.
struct Holiday: Hashable {
    let date: Date
    let name: String
}

enum HolidayCalendar {

    // MARK: - Abfragen

    /// Der Feiertag, der auf dieses Datum fällt - oder keiner.
    static func holiday(on date: Date, calendar: Calendar = .current) -> Holiday? {
        holidays(of: calendar.component(.year, from: date), calendar: calendar)
            .first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Alle Feiertage, die in eine Zeitspanne fallen - aufsteigend.
    static func holidays(in range: ClosedRange<Date>, calendar: Calendar = .current) -> [Holiday] {
        let years = calendar.component(.year, from: range.lowerBound)...calendar.component(.year, from: range.upperBound)
        return years.flatMap { holidays(of: $0, calendar: calendar) }
            .filter { range.contains($0.date) }
    }

    // MARK: - Rechnung

    /// Die Feiertage eines Jahres: sechs feste Termine und die vier, die am
    /// Ostersonntag hängen.
    static func holidays(of year: Int, calendar: Calendar = .current) -> [Holiday] {
        var days: [(month: Int, day: Int, name: String)] = [
            (1, 1, String(localized: "Neujahr")),
            (5, 1, String(localized: "Tag der Arbeit")),
            (10, 3, String(localized: "Tag der Deutschen Einheit")),
            (10, 31, String(localized: "Reformationstag")),
            (12, 25, String(localized: "1. Weihnachtstag")),
            (12, 26, String(localized: "2. Weihnachtstag")),
        ]

        guard let easter = easterSunday(year, calendar: calendar) else { return [] }
        func offset(_ days: Int) -> (month: Int, day: Int) {
            let date = calendar.date(byAdding: .day, value: days, to: easter) ?? easter
            return (calendar.component(.month, from: date), calendar.component(.day, from: date))
        }

        days.append((offset(-2).month, offset(-2).day, String(localized: "Karfreitag")))
        days.append((offset(1).month, offset(1).day, String(localized: "Ostermontag")))
        days.append((offset(39).month, offset(39).day, String(localized: "Christi Himmelfahrt")))
        days.append((offset(50).month, offset(50).day, String(localized: "Pfingstmontag")))

        return days.compactMap { entry in
            calendar.date(from: DateComponents(year: year, month: entry.month, day: entry.day))
                .map { Holiday(date: $0, name: entry.name) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Der Ostersonntag eines Jahres - die beweglichen Feiertage hängen an
    /// ihm. Gaußsche Osterformel in der Fassung von Meeus/Jones/Butcher;
    /// sie gilt für jeden Gregorianischen Kalender, den die App je sieht.
    static func easterSunday(_ year: Int, calendar: Calendar = .current) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
