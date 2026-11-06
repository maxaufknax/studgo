import Foundation

/// Der Abgleich geplanter Erinnerungen mit dem frischen Kalender - reine
/// Logik, geprüft auf Linux.
///
/// **Das Problem:** Erinnerungen plant „Heute“ - jedes Laden, Weiterplanen,
/// Verlegen läuft über die Ansicht. Endet die App nur im Hintergrund, ändert
/// sich nichts: Eine abgesagte Sitzung *klingelt trotzdem*, weil ihre
/// Erinnerung noch steht.
///
/// **Der Abgleich im Hintergrund** (siehe `BackgroundSync.reviewerCancellations`)
/// läuft deshalb selten - etwa einmal am Tag, als letzter Schritt des Laufs.
/// Was er entscheidet, steht hier, ohne Apple-Framework:
///
/// * **Entfernen:** Erinnerungen zu Sitzungen, die inzwischen abgesagt sind,
///   und Erinnerungen mit falscher Weckzeit, weil sich der Beginn verschoben
///   hat. Beides wird einzeln entfernt, **nie** erst alles weggeräumt und neu
///   gesetzt - ein Abbruch in der Mitte darf keine Erinnerung kosten.
/// * **Ergänzen:** Kommende Sitzungen ohne Erinnerung, im Rahmen des
///   Abgleichfensters (7 Tage) - der Rest wartet bis zum nächsten Öffnen.
/// * **Melden:** Frisch abgesagte Sitzungen, *nur* wenn dafür eine Erinnerung
///   stand - das ist der Beweis, dass sie vorher nicht abgesagt war - und nur
///   je Sitzung einmal.
///
/// Kann der Kalender nicht geholt werden, wird diese Funktionen gar nicht erst
/// gerufen: Bestehende Erinnerungen überleben jeden Fehlschlag unangetastet.
enum CancellationReview {

    /// Der Schwellwert, ab dem zwei Weckzeiten als verschieden gelten. Ein
    /// Kalender plant auf die Minute; Sekunden­unterschiede sind Artifakte
    /// der Zeitzone, nicht des Termins.
    static let fireTolerance: TimeInterval = 60

    /// Über welchen Zeitraum der Abgleich Ereignisse nachschiebt und meldet.
    static var horizon: TimeInterval { 7 * 24 * 3600 }

    /// Eine geplante Erinnerung, wie sie im Mitteilungszentrum steht:
    /// zugehöriger Termin und Weckzeit (ohne das Präfix der Kennung).
    struct PlannedReminder: Equatable, Hashable {
        let eventID: String
        let fireDate: Date?

        init(eventID: String, fireDate: Date?) {
            self.eventID = eventID
            self.fireDate = fireDate
        }
    }

    /// Was der Lauf zu tun hat - alles ohne Nebenwirkungen errechnet.
    struct Adjustment: Equatable {
        /// Kennungen der Termine, deren Erinnerung weg soll: abgesagt oder
        /// verschoben.
        let retireEventIDs: [String]
        /// Termine im Abgleichsfenster, die eine Erinnerung brauchen: neu
        /// dazu oder mit geänderter Weckzeit.
        let missing: [CourseEvent]
        /// Frisch abgesagte Termine im Fenster, über die noch nicht gemeldet
        /// wurde - nur Ziel der optionalen Mitteilung.
        let newlyCancelled: [CourseEvent]
        /// Der neue Stand der gemeldeten Ausfälle - gesäubert um alles, was
        /// im Kalender nicht mehr vorkommt.
        let announced: Set<String>
    }

    /// Der Abgleich.
    ///
    /// - Parameters:
    ///   - planned: Die geplanten Erinnerungen (nur die eigenen; das Präfix
    ///     ist schon entfernt).
    ///   - announced: Bereits gemeldete Absagen.
    ///   - fresh: Der frische Kalender, mit Ausfällen (aus dem ICS-Strom).
    ///   - leadMinutes: Die eingestellte Vorlaufzeit - dieselbe, mit der die
    ///     Erinnerungen geplant wurden.
    static func review(planned: [PlannedReminder],
                       announced: Set<String>,
                       fresh: [CourseEvent],
                       leadMinutes: Int,
                       quietWeekend: Bool,
                       now: Date,
                       calendar: Calendar = .current) -> Adjustment {
        let lead = TimeInterval(leadMinutes * 60)
        let window = now.addingTimeInterval(horizon)
        var plannedByEvent = Dictionary(planned.map { ($0.eventID, $0) },
                                         uniquingKeysWith: { first, _ in first })

        let upcoming = fresh.filter { $0.start > now && $0.start < window }
        let cancelledUpcoming = upcoming.filter { $0.isCancelled }

        // 1. Entfernen: abgesagte Termine mit Erinnerung, und solche, deren
        //    Weckzeit nicht mehr zur verschobenen Anfangszeit passt.
        var retire: Set<String> = []
        for event in cancelledUpcoming where plannedByEvent[event.id] != nil {
            retire.insert(event.id)
        }
        for event in upcoming where !event.isCancelled {
            guard let reminder = plannedByEvent[event.id] else { continue }
            let desired = event.start.addingTimeInterval(-lead)
            if reminder.fireDate == nil ||
                abs(reminder.fireDate!.timeIntervalSince(desired)) > fireTolerance {
                retire.insert(event.id)
            }
        }

        // 2. Ergänzen: kommende, nicht abgesagte Sitzungen ohne Erinnerung -
        //    Wochenenden ausgespart, falls die Einstellung es verlangt
        //    (dieselbe Regel wie beim ursprünglichen Planen; sonst würde der
        //    Abgleich die bewusste Ausnahme gleich wieder zurücknehmen).
        var missing: [CourseEvent] = []
        for event in upcoming where !event.isCancelled {
            guard !(quietWeekend && calendar.isDateInWeekend(event.start)) else { continue }
            guard plannedByEvent[event.id] == nil || retire.contains(event.id) else { continue }
            missing.append(event)
        }

        // 3. Melden: frisch abgesagt heißt, es stand eine Erinnerung dafür
        //    (geplant ist nur, was nicht schon abgesagt war) und es wurde
        //    noch nicht gemeldet. Je Sitzung genau einmal.
        let newlyCancelled = cancelledUpcoming
            .filter { plannedByEvent[$0.id] != nil && !announced.contains($0.id) }
            .sorted { $0.start < $1.start }

        // Gesäuberte Menge der gemeldeten Absagen: alles, was der Kalender
        // nicht mehr kennt, fällt weg - sonst wüchse sie ohne Grenze.
        let known = Set(fresh.map(\.id))
        let cleanAnnounced = announced.union(newlyCancelled.map(\.id)).intersection(known)

        return Adjustment(retireEventIDs: retire.sorted(),
                          missing: missing,
                          newlyCancelled: newlyCancelled,
                          announced: cleanAnnounced)
    }
}
