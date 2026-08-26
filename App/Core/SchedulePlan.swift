import Foundation

/// Welcher Wochenplan im Raster steht.
enum SchedulePlanScope: String, Hashable, CaseIterable, Identifiable {
    /// Das laufende Semester — in Stud.IP die Vorauswahl.
    case current
    /// Das Semester, dessen Vorlesungszeit als Nächstes beginnt.
    case upcoming

    var id: String { rawValue }
}

/// Welcher Wochenplan gezeigt wird und woraus er besteht.
///
/// **Warum das eine eigene Entscheidung ist und nicht drei Zeilen in der
/// Ansicht.** `/v1/users/{id}/schedule` gibt es zweimal: einmal ohne
/// `filter[timestamp]` (laufendes Semester) und einmal mit dem Zeitstempel des
/// kommenden. Beide Antworten mischen zwei Sorten Eintrag:
///
/// * `seminar-cycle-dates` — die Turnustermine der belegten Veranstaltungen.
///   Die hängen wirklich am Semester.
/// * `schedule-entries` — die selbst angelegten Blöcke. `ScheduleEntry::
///   findByUser_id()` läuft **ohne** Semesterfilter, sie kommen also bei
///   *jedem* Zeitstempel mit.
///
/// Genau daran ist die Fassung 1.4.0 gescheitert. Sie prüfte „ist der Plan des
/// kommenden Semesters leer?", um zu entscheiden, welchen Plan sie zeigt — und
/// zwei selbst angelegte Tutorien machten ihn nicht-leer. Das Raster zeigte
/// deshalb *nur* diese beiden, überschrieben mit „Vorschau auf das
/// Wintersemester". Kaum waren sie in Stud.IP gelöscht, kippte die Antwort auf
/// leer, und beim nächsten Aktualisieren standen schlagartig alle
/// Veranstaltungen des Sommersemesters im Bild. Von außen sah das aus wie ein
/// Fehler; tatsächlich war beides je einmal dieselbe falsche Frage.
///
/// Die richtige Frage lautet: **Führt der Plan des kommenden Semesters schon
/// Veranstaltungen?** Nur die hängen am Semester.
struct SchedulePlan: Equatable {
    /// Was ins Raster gehört: die Veranstaltungen des gewählten Semesters,
    /// dazu **alle** eigenen Termine — die gelten ganzjährig.
    let entries: [ScheduleEntry]
    /// Welcher Plan das geworden ist.
    let scope: SchedulePlanScope
    /// Wurde `scope` aus der Lage abgeleitet (`true`) oder von Hand gewählt?
    /// Die Ansicht schreibt den Unterschied nicht hin, aber sie darf eine
    /// eigene Wahl nicht stillschweigend überschreiben, sobald neu geladen
    /// wird.
    let isAutomatic: Bool

    /// Führt dieser Plan überhaupt Veranstaltungen? Eigene Termine zählen
    /// hier ausdrücklich **nicht** — siehe die Erklärung oben.
    static func hasCourses(_ entries: [ScheduleEntry]) -> Bool {
        entries.contains(where: \.isCourse)
    }

    /// Stellt den anzuzeigenden Plan zusammen.
    ///
    /// - Parameters:
    ///   - current: Antwort ohne `filter[timestamp]`.
    ///   - upcoming: Antwort mit dem Zeitstempel des kommenden Semesters.
    ///     Leer, solange man dort in keiner Veranstaltung eingetragen ist —
    ///     das ist zwei Monate vor Beginn der Regelfall und kein Fehler.
    ///   - isSemesterBreak: Ob gerade vorlesungsfreie Zeit ist.
    ///   - preferred: Die Wahl aus dem Menü. `nil` heißt „automatisch".
    static func resolve(current: [ScheduleEntry],
                        upcoming: [ScheduleEntry],
                        isSemesterBreak: Bool,
                        preferred: SchedulePlanScope? = nil) -> SchedulePlan {
        // In der vorlesungsfreien Zeit lohnt der Blick nach vorn — aber nur,
        // wenn dort schon etwas steht. Sonst bleibt der laufende Plan stehen,
        // so wie ihn auch die Weboberfläche zeigt.
        let automatic: SchedulePlanScope =
            isSemesterBreak && hasCourses(upcoming) ? .upcoming : .current
        let scope = preferred ?? automatic

        let courses = (scope == .upcoming ? upcoming : current).filter(\.isCourse)

        // Eigene Termine stehen in **beiden** Antworten, mit derselben
        // Kennung. Ohne dieses Aussieben stünde jedes Tutorium doppelt im
        // Raster, sobald beide Pläne geladen sind.
        var seen = Set<String>()
        let personal = (current + upcoming)
            .filter { !$0.isCourse }
            .filter { seen.insert($0.id).inserted }

        return SchedulePlan(entries: courses + personal,
                            scope: scope,
                            isAutomatic: preferred == nil)
    }
}
