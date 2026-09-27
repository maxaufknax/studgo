import Foundation

/// Die Auswahl für „Demnächst" auf dem Startbildschirm.
///
/// **Warum das eine eigene Stelle ist:** Bis 1.7.0 nahm die Ansicht die
/// ersten vier Termine *nach* dem heutigen Tag - ungegruppiert und ohne
/// erkennbares Kriterium. Auf dem Bildschirm wirkte das wie „je einer je
/// Tag": Stehen dienstags und mittwochs je zwei Vorlesungen an, zeigte der
/// Abschnitt Dienstag-morgens und Mittwoch-mittags, aber nie beide vom
/// selben Tag - und niemand sah, wonach eigentlich ausgewählt wurde.
///
/// Das Kriterium steht jetzt hier und ist einfach: **die tatsächlich
/// nächstliegenden Termine**, streng chronologisch, wie viele am selben Tag
/// auch immer dazugehören - gruppiert nach Tag, damit der Abschnitt liest
/// wie der Rest des Kalenders. Heute bleibt draußen: Dafür gibt es den
/// Abschnitt „Heute noch" direkt darüber.
enum UpcomingEvents {

    /// Die nächsten Termine nach heute - chronologisch, ohne Tagesdeckel,
    /// bis `limit` erreicht sind. Abgesagte stehen mit dabei (der Kalender
    /// zeigt sie ebenfalls markiert), der laufende Termin zählt nicht: Der
    /// steht oben in der Karte.
    ///
    /// `calendar` und `now` sind Parameter, damit die Auswahl sich unter
    /// UTC prüfen lässt - sonst tippt ein Test auf Mitternacht in Berlin
    /// in den Vortag (siehe `Weekday.of`).
    static func select(_ events: [CourseEvent],
                       now: Date = Date(),
                       limit: Int = 6,
                       calendar: Calendar = .current) -> [CourseEvent] {
        let today = calendar.startOfDay(for: now)
        return events
            .filter { calendar.startOfDay(for: $0.start) > today && $0.start > now }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    /// Termine nach Tag gruppiert - der erste Termin des Tages entscheidet
    /// über die Reihenfolge der Tage, innerhalb eines Tages zählt die Uhrzeit.
    static func group(_ events: [CourseEvent],
                      calendar: Calendar = .current) -> [(day: Date, events: [CourseEvent])] {
        var days: [Date: [CourseEvent]] = [:]
        for event in events {
            days[calendar.startOfDay(for: event.start), default: []].append(event)
        }
        return days
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
    }
}
