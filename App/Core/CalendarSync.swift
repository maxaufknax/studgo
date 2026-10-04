import CoreGraphics
import EventKit
import Foundation

/// Der Stundenplan im iOS-Kalender - in einem eigenen Kalender „StudGo“.
///
/// **Warum überhaupt:** Was im Systemkalender steht, erscheint auch auf der
/// Apple Watch, in CarPlay, bei Siri und in jeder anderen Kalender-App. Der
/// Export als `.ics` (Plan → „…“) tut das auch, aber nur einmal: Fällt danach
/// eine Sitzung aus, steht sie dort weiter. Dieser Abgleich hält die nächsten
/// acht Wochen aktuell - bei jedem Öffnen von „Heute“.
///
/// **Warum ein eigener Kalender:** Er lässt sich mit einem Schalter in der
/// Kalender-App ausblenden und beim Ausschalten in StudGo restlos entfernen,
/// ohne einen einzigen fremden Termin anzufassen. Was eingetragen, geändert
/// oder entfernt wird, entscheidet `CalendarSyncPlan` (geprüft unter Linux);
/// hier wird es nur übertragen.
///
/// **Warum voller Zugriff:** Mit dem reinen Schreibzugriff (ab iOS 17) ließe
/// sich ein Termin anlegen, aber nie wieder finden - ein ausgefallener stünde
/// dann für immer im Kalender. Gelesen wird trotzdem nur der eigene Kalender.
@MainActor
enum CalendarSync {

    /// Wie weit voraus eingetragen wird. Acht Wochen tragen über Ferien und
    /// lange Wochenenden, ohne den Kalender mit einem ganzen Semester zu
    /// fluten, das sich ohnehin noch ändert.
    static let horizonDays = 56

    private static var store = EKEventStore()
    private static let calendarIDKey = "studgo.calendar.identifier"
    private static let lastSyncKey = "studgo.calendar.lastSync"
    private static let lastCountKey = "studgo.calendar.lastCount"
    /// Der Titel des eigenen Kalenders - in jeder Sprache derselbe Name.
    private static let calendarTitle = "StudGo"

    enum Access {
        case granted, denied, undetermined
    }

    enum SyncError: LocalizedError {
        case noAccess
        case noWritableSource

        var errorDescription: String? {
            switch self {
            case .noAccess:
                return String(localized: "StudGo hat keinen Zugriff auf den Kalender.")
            case .noWritableSource:
                return String(localized: "Auf diesem Gerät lässt sich kein neuer Kalender anlegen.")
            }
        }
    }

    // MARK: - Zugriff

    static var access: Access {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            switch status {
            case .fullAccess: return .granted
            case .notDetermined: return .undetermined
            default: return .denied
            }
        }
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    /// Fragt nach dem Zugriff, falls noch nicht entschieden. Gibt zurück, ob
    /// er vorliegt.
    static func requestAccess() async -> Bool {
        switch access {
        case .granted: return true
        case .denied: return false
        case .undetermined: break
        }
        let granted: Bool
        do {
            if #available(iOS 17.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
        } catch {
            granted = false
        }
        // Ein Speicher, der vor der Erlaubnis entstand, sieht die Quellen
        // des Geräts erst nach einem Neuanlegen.
        if granted { store = EKEventStore() }
        return granted
    }

    // MARK: - Abgleich

    /// Wann zuletzt abgeglichen wurde und wie viele Termine im Kalender
    /// stehen - für die Einstellung, damit sichtbar ist, dass etwas passiert.
    static var lastSync: (date: Date, count: Int)? {
        let defaults = UserDefaults.standard
        guard let date = defaults.object(forKey: lastSyncKey) as? Date else { return nil }
        return (date, defaults.integer(forKey: lastCountKey))
    }

    /// Gleicht den Kalender „StudGo“ mit `events` ab und gibt zurück, wie
    /// viele Termine darin stehen.
    ///
    /// `events` sind die zusammengeführten Termine der App (siehe
    /// `EventMerge`), ausgeblendete schon heraus.
    @discardableResult
    static func sync(_ events: [CourseEvent], now: Date = Date()) throws -> Int {
        guard access == .granted else { throw SyncError.noAccess }
        let calendar = try ownCalendar()
        let desired = CalendarSyncPlan.items(from: events, now: now, horizonDays: horizonDays)

        // Das Fenster beginnt **jetzt**: Was schon vorbei ist, bleibt stehen.
        // Laufende Termine überlappen den Beginn und gehören dazu.
        let end = Calendar.current.date(byAdding: .day, value: horizonDays + 1,
                                        to: Calendar.current.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: [calendar])
        var mine: [String: [EKEvent]] = [:]
        for event in store.events(matching: predicate) {
            guard let key = CalendarSyncPlan.key(from: event.url) else { continue }
            mine[key, default: []].append(event)
        }
        let existing = mine.flatMap { key, events in events.map { item(key: key, from: $0) } }
        let changes = CalendarSyncPlan.changes(existing: existing, desired: desired)

        for item in changes.insert {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            apply(item, to: event)
            try store.save(event, span: .thisEvent, commit: false)
        }
        for item in changes.update {
            guard let event = mine[item.key]?.first else { continue }
            apply(item, to: event)
            try store.save(event, span: .thisEvent, commit: false)
        }
        for key in changes.remove {
            for event in mine[key] ?? [] {
                try store.remove(event, span: .thisEvent, commit: false)
            }
        }
        for key in changes.duplicates {
            for event in (mine[key] ?? []).dropFirst() {
                try store.remove(event, span: .thisEvent, commit: false)
            }
        }
        if !changes.isEmpty { try store.commit() }

        UserDefaults.standard.set(now, forKey: lastSyncKey)
        UserDefaults.standard.set(desired.count, forKey: lastCountKey)
        return desired.count
    }

    /// Holt, was „Heute“ auch holt, und gleicht ab - für den Schalter in den
    /// Einstellungen und die Einführung, die nicht warten sollen, bis „Heute“
    /// das nächste Mal lädt.
    @discardableResult
    static func syncNow(client: StudIPClient,
                        userID: String,
                        isHidden: (CourseEvent) -> Bool) async throws -> Int {
        // Scheitern beide Wege, bricht der Abgleich ab, statt mit einer leeren
        // Liste jeden künftigen Eintrag aus dem Kalender zu räumen.
        let dated: [CourseEvent]
        do {
            dated = try await client.calendarEvents(for: userID)
        } catch {
            dated = try await client.events(for: userID, weeks: horizonDays / 7)
        }
        let plan = (try? await client.schedule(for: userID)) ?? []
        let context = SemesterContext((try? await client.semesters()) ?? [])
        let merged = EventMerge.combine(dated: dated,
                                        plans: [EventMerge.PlanWindow(entries: plan,
                                                                      semester: context.current())],
                                        days: horizonDays)
        return try sync(merged.filter { !isHidden($0) })
    }

    /// Entfernt den Kalender „StudGo“ samt allen Einträgen - beim Ausschalten
    /// und beim Abmelden: Der Stundenplan des bisherigen Kontos soll nicht im
    /// Kalender des Geräts zurückbleiben.
    static func removeCalendar() {
        let defaults = UserDefaults.standard
        let identifier = defaults.string(forKey: calendarIDKey)
        defaults.removeObject(forKey: calendarIDKey)
        defaults.removeObject(forKey: lastSyncKey)
        defaults.removeObject(forKey: lastCountKey)
        guard access == .granted, let identifier,
              let calendar = store.calendar(withIdentifier: identifier) else { return }
        try? store.removeCalendar(calendar, commit: true)
    }

    // MARK: - Kalender

    /// Der eigene Kalender - gefunden über die gemerkte Kennung, sonst über
    /// den Namen (nach einer Neuinstallation liegt er noch in iCloud), sonst
    /// neu angelegt.
    private static func ownCalendar() throws -> EKCalendar {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: calendarIDKey),
           let calendar = store.calendar(withIdentifier: identifier) {
            return calendar
        }
        if let calendar = store.calendars(for: .event)
            .first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            defaults.set(calendar.calendarIdentifier, forKey: calendarIDKey)
            return calendar
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        // Das Blau der Wortmarke, #38B6FF.
        calendar.cgColor = CGColor(red: 56 / 255, green: 182 / 255, blue: 1, alpha: 1)
        for source in candidateSources() {
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                defaults.set(calendar.calendarIdentifier, forKey: calendarIDKey)
                return calendar
            } catch {
                continue
            }
        }
        throw SyncError.noWritableSource
    }

    /// Wo ein neuer Kalender hin darf: dorthin, wo iOS neue Termine anlegt
    /// (meist iCloud), sonst iCloud ausdrücklich, sonst „Auf meinem iPhone“.
    /// Abonnierte Kalender und Geburtstage scheiden aus, sie nehmen nichts an.
    private static func candidateSources() -> [EKSource] {
        var sources: [EKSource] = []
        if let preferred = store.defaultCalendarForNewEvents?.source {
            sources.append(preferred)
        }
        sources += store.sources.filter { $0.sourceType == .calDAV }
        sources += store.sources.filter { $0.sourceType == .local }
        var seen = Set<String>()
        return sources.filter { seen.insert($0.sourceIdentifier).inserted }
    }

    // MARK: - Übertragung

    private static func item(key: String, from event: EKEvent) -> CalendarSyncItem {
        CalendarSyncItem(key: key,
                         title: event.title ?? "",
                         start: event.startDate,
                         end: event.endDate,
                         location: event.location.flatMap { $0.isEmpty ? nil : $0 },
                         notes: event.notes.flatMap { $0.isEmpty ? nil : $0 })
    }

    private static func apply(_ item: CalendarSyncItem, to event: EKEvent) {
        event.title = item.title
        event.startDate = item.start
        event.endDate = item.end
        event.location = item.location
        event.notes = item.notes
        event.url = CalendarSyncPlan.url(for: item.key)
    }
}
