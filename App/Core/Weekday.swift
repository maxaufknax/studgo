import Foundation

/// Wochentage in Stud.IP-Zählung: 1 = Montag … 7 = Sonntag.
///
/// Lag bis 2026-08 als Sammlung statischer Mitglieder in `TimetableView`.
/// Das war eine Umkehrung: `EventMerge` und `Models` — beides Schichten
/// unterhalb der Oberfläche — griffen für reine Kalenderrechnung auf eine
/// SwiftUI-Ansicht zu. Hier steht sie unabhängig und lässt sich damit auch
/// ausserhalb von Xcode übersetzen und prüfen.
enum Weekday {
    static let shortNames = ["", "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let fullNames = ["", "Montag", "Dienstag", "Mittwoch",
                            "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static func short(_ day: Int) -> String {
        shortNames.indices.contains(day) ? shortNames[day] : "?"
    }

    static func full(_ day: Int) -> String {
        fullNames.indices.contains(day) ? fullNames[day] : "Unbekannt"
    }

    /// `Calendar` zählt 1 = Sonntag, Stud.IP 1 = Montag.
    ///
    /// Der Kalender ist bewusst ein Parameter: `Calendar.current` hängt an der
    /// Zeitzone des Geräts, und genau daran scheitert sonst jeder Test, der
    /// auf einem Server unter UTC läuft — Mitternacht in Berlin ist dort noch
    /// der Vortag. In der App bleibt der Standardwert richtig.
    static func of(_ date: Date, in calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static var today: Int { of(Date()) }
}
