import Foundation

/// Ein Termin, wie er im iOS-Kalender stehen soll.
///
/// Bewusst ohne EventKit: Was eingetragen, geändert oder entfernt wird,
/// entscheidet `CalendarSyncPlan` - und das soll sich unter Linux prüfen
/// lassen. `CalendarSync` überträgt die Entscheidung nur noch.
struct CalendarSyncItem: Equatable {
    /// Wiedererkennung über alle Abgleiche hinweg - steht als
    /// `studgo://termin/<key>` in der Adresse des Kalendereintrags.
    let key: String
    let title: String
    let start: Date
    let end: Date
    var location: String?
    var notes: String?
}

/// Was beim Abgleich mit dem Kalender „StudGo" zu tun ist.
///
/// **Der Grundsatz:** StudGo verwaltet nur Einträge, die es selbst angelegt
/// hat - erkennbar an der Adresse `studgo://termin/…`. Was jemand von Hand in
/// den Kalender „StudGo" schreibt, bleibt unberührt, und Vergangenes auch:
/// Ein Kalender, aus dem die Vorlesung von gestern verschwindet, taugt nicht
/// zum Nachschlagen.
enum CalendarSyncPlan {

    /// Die Termine, die im Kalender stehen sollen: noch nicht vorbei, höchstens
    /// `horizonDays` voraus, ohne ausgefallene Sitzungen. Jeder Schlüssel nur
    /// einmal - `EventMerge` hat Doppelungen schon entfernt, aber der Kalender
    /// darf sich nicht darauf verlassen müssen.
    static func items(from events: [CourseEvent],
                      now: Date,
                      horizonDays: Int,
                      calendar: Calendar = .current) -> [CalendarSyncItem] {
        let horizon = calendar.date(byAdding: .day, value: horizonDays,
                                    to: calendar.startOfDay(for: now)) ?? now
        var seen = Set<String>()
        return events
            .filter { !$0.isCancelled && $0.end > now && $0.start < horizon }
            .sorted { $0.start < $1.start }
            .compactMap { event in
                let key = Self.key(for: event)
                guard seen.insert(key).inserted else { return nil }
                return CalendarSyncItem(key: key,
                                        title: event.displayTitle,
                                        start: event.start,
                                        end: event.end,
                                        location: event.location?.nilIfBlank,
                                        notes: notes(for: event))
            }
    }

    /// Thema der Sitzung, falls es eines gibt, und der Hinweis, woher der
    /// Eintrag stammt - damit niemand in der Kalender-App etwas ändert, das
    /// der nächste Abgleich wieder überschreibt.
    static func notes(for event: CourseEvent) -> String {
        var lines: [String] = []
        if let topic = event.topic, topic != event.title, topic != event.displayTitle {
            lines.append(topic)
        }
        lines.append(String(localized: "Aus StudGo übernommen. Änderungen bitte in Stud.IP vornehmen – StudGo gleicht diesen Kalender bei jedem Öffnen ab."))
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Schlüssel

    /// FNV-1a über die Kennung des Termins. Ein Prüfwert statt der Kennung
    /// selbst: Stud.IP-Kennungen tragen `@` und Leerzeichen, und im Kalender
    /// soll nichts stehen, was über den Termin hinaus etwas verrät.
    static func key(for event: CourseEvent) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in event.id.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }

    static func url(for key: String) -> URL? {
        URL(string: "studgo://termin/\(key)")
    }

    /// Der Schlüssel aus der Adresse eines Kalendereintrags - oder `nil`, wenn
    /// der Eintrag nicht von StudGo stammt.
    static func key(from url: URL?) -> String? {
        guard let url, url.scheme == "studgo", url.host == "termin" else { return nil }
        let key = url.lastPathComponent
        guard !key.isEmpty, key != "/", key.allSatisfy(\.isHexDigit) else { return nil }
        return key
    }

    // MARK: - Unterschied

    struct Changes: Equatable {
        var insert: [CalendarSyncItem] = []
        var update: [CalendarSyncItem] = []
        /// Schlüssel, deren Einträge ganz verschwinden.
        var remove: [String] = []
        /// Schlüssel, die mehrfach im Kalender stehen - alles ausser dem
        /// ersten Eintrag kommt weg (etwa nach einem Abbruch mitten im
        /// Abgleich).
        var duplicates: [String] = []

        var isEmpty: Bool {
            insert.isEmpty && update.isEmpty && remove.isEmpty && duplicates.isEmpty
        }
    }

    /// Vergleicht, was im Kalender steht, mit dem Soll.
    ///
    /// `existing` sind die Einträge **von StudGo** im Abgleichsfenster, je
    /// Eintrag ein Element - ein Schlüssel kann also mehrfach vorkommen.
    static func changes(existing: [CalendarSyncItem], desired: [CalendarSyncItem]) -> Changes {
        var changes = Changes()
        var byKey: [String: [CalendarSyncItem]] = [:]
        for item in existing { byKey[item.key, default: []].append(item) }

        var wanted = Set<String>()
        for item in desired where wanted.insert(item.key).inserted {
            if let current = byKey[item.key]?.first {
                if current != item { changes.update.append(item) }
            } else {
                changes.insert.append(item)
            }
        }

        for (key, items) in byKey {
            if !wanted.contains(key) {
                changes.remove.append(key)
            } else if items.count > 1 {
                changes.duplicates.append(key)
            }
        }
        changes.remove.sort()
        changes.duplicates.sort()
        return changes
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
