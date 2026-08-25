import BackgroundTasks
import Foundation
import UserNotifications

/// Benachrichtigungen ohne Push-Server.
///
/// **Warum kein echtes Push:** Push über APNs setzt einen Server voraus, der
/// erfährt, dass etwas passiert ist, und dann an Apple sendet. Stud.IP bietet
/// dafür nichts an — es gibt weder Webhooks noch eine Abo-Route in der
/// JSON:API; die Weboberfläche selbst pollt. Ein Push-Dienst für StudGo hieße
/// also: ein eigenes Backend, das für jede Nutzerin dauerhaft ein
/// OAuth-Token vorhält und im Minutentakt bei Stud.IP nachfragt. Das
/// widerspricht der Zusage, dass die App **kein** Backend hat und Tokens das
/// Gerät nicht verlassen (siehe „Über StudGo").
///
/// **Was stattdessen geht — und für den Zweck genügt:**
///
/// 1. **Terminerinnerungen** als lokale Benachrichtigung. Der Kalender liegt
///    ohnehin auf dem Gerät (`GET /users/{id}/events.ics` reicht bis 2036),
///    also lässt sich jede Sitzung im Voraus einplanen. Das ist sogar
///    zuverlässiger als Push: Es funktioniert ohne Netz.
/// 2. **Neue Nachrichten und Beiträge** über `BGAppRefreshTask`. iOS weckt
///    die App, wenn es passt — typisch mehrmals täglich, gelernt am
///    Nutzungsverhalten. Für ein Postfach reicht das; für einen Chat, in dem
///    man auf Antwort wartet, nicht. Das sagt die Einstellung auch so.
///
/// **iOS-Grenze, die den Entwurf bestimmt:** Es dürfen höchstens **64**
/// lokale Benachrichtigungen gleichzeitig geplant sein. Danach verwirft das
/// System stillschweigend die überzähligen. Deshalb werden nur die nächsten
/// Termine eingeplant und bei jedem Start neu aufgesetzt.
///
/// **Ohne `@MainActor`:** `UNUserNotificationCenter` und `BGTaskScheduler`
/// sind für sich nebenläufigkeitssicher, und der Rückruf des Hintergrundlaufs
/// kommt nicht auf dem Hauptaktor an. Eine Bindung daran hieße, in jedem
/// dieser Aufrufe einen Sprung zu erzwingen, den es nicht braucht — und
/// `scheduleBackgroundRefresh()` ließe sich aus dem Rückruf gar nicht rufen.
enum Notifications {

    /// Kennung des Hintergrundlaufs. Muss wortgleich in `Info.plist` unter
    /// `BGTaskSchedulerPermittedIdentifiers` stehen — sonst wirft
    /// `BGTaskScheduler.register` zur Laufzeit eine Ausnahme.
    static let refreshTaskID = "de.maxaufknax.studgo.refresh"

    /// Wie viele Termine im Voraus geplant werden. Deutlich unter 64, damit
    /// für die Meldungen aus dem Hintergrund Platz bleibt.
    private static let maxScheduledEvents = 48

    private static let center = UNUserNotificationCenter.current()

    // MARK: - Erlaubnis

    /// Fragt einmalig nach der Erlaubnis. Gibt zurück, ob sie vorliegt.
    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Terminerinnerungen

    private static let eventPrefix = "studgo.event."

    /// Plant Erinnerungen für die nächsten Termine.
    ///
    /// Wird bei jedem Start und nach jedem Laden des Kalenders gerufen: Fällt
    /// eine Sitzung aus oder verschiebt sie sich, ist der alte Eintrag sonst
    /// noch geplant. Deshalb erst alles Eigene wegräumen, dann neu setzen.
    static func scheduleEventReminders(_ events: [CourseEvent],
                                       leadMinutes: Int,
                                       quietWeekend: Bool) async {
        await clearEventReminders()

        let now = Date()
        let lead = TimeInterval(leadMinutes * 60)
        let calendar = Calendar.current

        let upcoming = events
            .filter { !$0.isCancelled }
            .filter { $0.start.addingTimeInterval(-lead) > now }
            .filter { !(quietWeekend && calendar.isDateInWeekend($0.start)) }
            .sorted { $0.start < $1.start }
            .prefix(maxScheduledEvents)

        for event in upcoming {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = reminderBody(for: event, leadMinutes: leadMinutes)
            content.sound = .default
            content.threadIdentifier = "studgo.calendar"
            content.categoryIdentifier = "STUDGO_EVENT"

            let fireDate = event.start.addingTimeInterval(-lead)
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: eventPrefix + event.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }

    private static func reminderBody(for event: CourseEvent, leadMinutes: Int) -> String {
        var parts: [String] = []
        parts.append(leadMinutes == 0
                     ? "Beginnt jetzt"
                     : "Beginnt um \(event.start.formatted(date: .omitted, time: .shortened))")
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    /// Wie viele Erinnerungen gerade vorgemerkt sind — für die Einstellung,
    /// damit sichtbar ist, dass wirklich etwas geplant wurde.
    static func pendingReminderCount() async -> Int {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(eventPrefix) }
            .count
    }

    static func clearEventReminders() async {
        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(eventPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    static func clearAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Meldungen aus dem Hintergrund

    /// Meldet eine neue Nachricht oder einen neuen Beitrag.
    static func post(title: String, body: String, thread: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        try? await center.add(request)
    }

    // MARK: - Hintergrundlauf

    /// Meldet den Hintergrundlauf an. **Muss beim Start geschehen**, bevor die
    /// erste Szene steht — später abgegeben lehnt iOS die Anmeldung ab.
    static func registerBackgroundTask(handler: @escaping @Sendable () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID,
                                        using: nil) { task in
            // Direkt den nächsten Lauf anfordern: iOS plant immer nur einen.
            // Wer das erst am Ende tut, verliert die Kette, sobald der Lauf
            // in die Zeitgrenze läuft.
            scheduleBackgroundRefresh()
            let work = Task {
                await handler()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Bittet um den nächsten Weckruf.
    ///
    /// `earliestBeginDate` ist eine Bitte, keine Zusage — iOS entscheidet nach
    /// Akkustand, Netz und Nutzungsgewohnheit. Eine Stunde ist der übliche
    /// Kompromiss: häufiger wird ohnehin nicht bewilligt.
    static func scheduleBackgroundRefresh(after interval: TimeInterval = 3600) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
    }
}
