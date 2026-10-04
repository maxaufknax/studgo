import Foundation

/// Was StudGo tut, wenn iOS die App im Hintergrund weckt.
///
/// **Eigene Sitzung statt der aus der Oberfläche:** Der Hintergrundlauf
/// startet die App unter Umständen aus dem kalten Zustand - es gibt dann
/// keinen `AuthStore`, den man sich greifen könnte. Deshalb baut sich dieser
/// Lauf einen eigenen auf, einen **passiven**: Er darf Tokens erneuern, aber
/// keine Sitzung beenden. Die Tokens liegen in der Keychain und werden dort
/// auch erneuert; die Oberfläche gleicht sich vor jedem Erneuern damit ab,
/// sodass beide Wege denselben Stand sehen.
///
/// **Sparsam mit dem Zeitfenster:** iOS gibt einem `BGAppRefreshTask` rund
/// 30 Sekunden. Deshalb genau drei Anfragen - Profil, Posteingang, Fäden - und
/// keine Kalenderabrufe: Die Erinnerungen sind ohnehin im Voraus geplant.
@MainActor
enum BackgroundSync {

    /// Höchstzahl der Meldungen je Lauf. Wer über Nacht zwanzig Beiträge
    /// bekommt, will morgens nicht zwanzig Mitteilungen wegwischen.
    private static let maxAlerts = 5

    static func run() async {
        // Erst hier erzeugt: `Preferences` hängt am Hauptaktor, der Rückruf
        // des `BGAppRefreshTask` läuft nicht darauf.
        let preferences = Preferences()
        guard preferences.mailboxAlerts, await Notifications.isAuthorized() else { return }
        if preferences.quietWeekend, Calendar.current.isDateInWeekend(Date()) { return }

        // Passiv: Dieser Lauf erneuert Tokens, meldet aber nie ab - auch
        // nicht, wenn Stud.IP nachts in Wartung ist (siehe `AuthStore.isPassive`).
        let auth = AuthStore(passive: true)
        await auth.restore()
        guard case .signedIn(let user) = auth.state, !auth.isDemo else { return }

        let client = auth.freshClient
        let unread = await notifyNewMessages(client: client, userID: user.id,
                                             preferences: preferences)
        await notifyNewThreads(client: client, userID: user.id, preferences: preferences)

        // Was das Nachrichten-Widget zeigt - aus dem Posteingang, der hier
        // ohnehin geholt wird; der nächste Termin bleibt dem Startbildschirm
        // überlassen (siehe `WidgetBridge.publish(unread:)`).
        WidgetBridge.publish(unread: unread)
    }

    // MARK: - Nachrichten

    /// Sagt zurück, wie viele Nachrichten im Posteingang ungelesen sind -
    /// das Widget zeigt dieselbe Zahl wie das App-Symbol.
    @discardableResult
    private static func notifyNewMessages(client: StudIPClient,
                                          userID: String,
                                          preferences: Preferences) async -> Int {
        guard let inbox = try? await client.inbox(for: userID) else { return 0 }
        let unread = inbox.filter { !$0.isRead }.count

        let since = preferences.lastNotifiedMessage
        let fresh = inbox
            .filter { !$0.isRead }
            .filter { ($0.sentAt ?? .distantPast) > since }
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }

        guard !fresh.isEmpty else { return unread }

        if fresh.count > maxAlerts {
            // Gesammelt statt einzeln - sonst wäre der Sperrbildschirm voll.
            await Notifications.post(title: "\(fresh.count) neue Nachrichten",
                                     body: fresh.prefix(3)
                                        .map { $0.counterpart(outgoing: false) ?? $0.subject }
                                        .joined(separator: ", "),
                                     thread: "studgo.inbox")
        } else {
            for message in fresh.reversed() {
                await Notifications.post(title: message.counterpart(outgoing: false)
                                            ?? "Neue Nachricht",
                                         body: "\(message.subject)\n\(message.preview.firstLine)",
                                         thread: "studgo.inbox")
            }
        }

        if let newest = fresh.first?.sentAt {
            preferences.lastNotifiedMessage = newest
        }
        return unread
    }

    // MARK: - Blubber

    private static func notifyNewThreads(client: StudIPClient,
                                         userID: String,
                                         preferences: Preferences) async {
        guard let threads = try? await client.personalBlubberThreads(for: userID, limit: 40)
        else { return }

        let since = preferences.lastNotifiedActivity
        let fresh = threads
            .filter(\.hasNews)
            .filter { ($0.latestActivity ?? .distantPast) > since }
            .sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }

        guard !fresh.isEmpty else { return }

        if fresh.count > maxAlerts {
            await Notifications.post(title: "Neues in \(fresh.count) Unterhaltungen",
                                     body: fresh.prefix(3).map(\.name).joined(separator: ", "),
                                     thread: "studgo.blubber")
        } else {
            for thread in fresh.reversed() {
                let count = thread.unseenComments
                await Notifications.post(
                    title: thread.name,
                    body: count > 0
                        ? (count == 1 ? "1 neuer Beitrag" : "\(count) neue Beiträge")
                        : thread.preview.firstLine,
                    thread: "studgo.blubber")
            }
        }

        if let newest = fresh.first?.latestActivity {
            preferences.lastNotifiedActivity = newest
        }
    }
}
