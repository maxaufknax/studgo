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
        // Getrennt je Mitteilungsart: Bis 1.8 brach der Lauf ganz ab, wenn
        // Nachrichten aus waren - Hinweis und Widget hingen an einem
        // Schalter, der sie nichts anging.
        let wantsMailbox = preferences.mailboxAlerts
        let wantsCourseNews = preferences.courseNewsAlerts
        let wantsCancellations = preferences.eventReminders || preferences.cancellationAlerts
        guard wantsMailbox || wantsCourseNews || wantsCancellations,
              await Notifications.isAuthorized() else { return }
        if preferences.quietWeekend, Calendar.current.isDateInWeekend(Date()) { return }

        // Passiv: Dieser Lauf erneuert Tokens, meldet aber nie ab - auch
        // nicht, wenn Stud.IP nachts in Wartung ist (siehe `AuthStore.isPassive`).
        let auth = AuthStore(passive: true)
        await auth.restore()
        guard case .signedIn(let user) = auth.state, !auth.isDemo else { return }

        let client = auth.freshClient

        if wantsMailbox {
            let unread = await notifyNewMessages(client: client, userID: user.id,
                                                 preferences: preferences)
            await notifyNewThreads(client: client, userID: user.id, preferences: preferences)

            // Was das Nachrichten-Widget zeigt - aus dem Posteingang, der hier
            // ohnehin geholt wird; der nächste Termin bleibt dem Startbildschirm
            // überlassen (siehe `WidgetBridge.publish(unread:)`). Konnte der
            // Posteingang nicht geholt werden (nil), bleibt im Widget der alte
            // Wert stehen - bis 1.9 stand dann „0 Nachrichten“ da.
            WidgetBridge.publish(unread: unread)
        }

        if wantsCourseNews {
            await notifyNewCourseNews(client: client, userID: user.id,
                                      preferences: preferences)
        }

        // Der Ausfallsabgleich: letzter Schritt, selten (etwa einmal am Tag)
        // und für jeden Abbruch gefeit - die `events.ics` kann groß sein, und
        // das Zeitfenster ist auch dann zu Ende gegangen, wenn sie gerade
        // unterwegs war. Was nicht mehr geschafft wird, bleibt für den
        // nächsten Lauf.
        if wantsCancellations {
            await reviewCancellations(client: client, userID: user.id,
                                      preferences: preferences)
        }
    }

    // MARK: - Ausfälle

    /// Vergleicht die geplanten Erinnerungen mit dem frischen Kalender und
    /// nimmt Absagen heraus - sie würden sonst klingeln, obwohl die
    /// Sitzung nicht stattfindet.
    ///
    /// **Abbruchfest durch die Bauerweise:** Der Abgleich räumt nie alles
    /// und plant dann neu, sondern entfernt und ergänzt einzeln, nach einer
    /// Entscheidung in purem Code (`CancellationReview`). Schlägt der
    /// Kalenderabruf fehl oder läuft die App in die Zeitgrenze, bleibt der
    /// Bestand einfach stehen - still liegen ist besser als Erinnerungen
    /// verlieren.
    private static func reviewCancellations(client: StudIPClient,
                                            userID: String,
                                            preferences: Preferences) async {
        // Nicht öfter als etwa einmal am Tag; `max` für den Fall, dass die
        // Uhr einmal verrückt gespielt hat.
        let interval = max(0, Date().timeIntervalSince(preferences.lastCancellationReview))
        guard interval > 20 * 3600 else { return }
        defer { preferences.lastCancellationReview = Date() }

        // Fehler überlebt hier still: Kein Kalender, kein Abgleich - der
        // nächste Lauf versucht es erneut (siehe `AuthStore.isPassive` für
        // den Grund, warum ein Fehlschlag keine Sitzung beendet).
        guard let events = try? await client.calendarEvents(for: userID),
              !events.isEmpty else { return }

        let planned = await Notifications.plannedReminders()
        let adjustment = CancellationReview.review(planned: planned,
                                                   announced: preferences.announcedCancellations,
                                                   fresh: events,
                                                   leadMinutes: preferences.leadMinutes,
                                                   quietWeekend: preferences.quietWeekend,
                                                   now: Date())
        await Notifications.applyCancellationAdjustment(adjustment,
                                                        leadMinutes: preferences.leadMinutes,
                                                        quietWeekend: preferences.quietWeekend)
        preferences.replaceAnnouncedCancellations(adjustment.announced)

        // Die Mitteilung über einen Ausfall: optional, nur die nächsten
        // sieben Tage (der Rest der Liste ist ohnehin raus), je Sitzung
        // einmal - `announced` hält es fest.
        guard preferences.cancellationAlerts else { return }
        for event in adjustment.newlyCancelled {
            await Notifications.post(title: String(localized: "Fällt aus"),
                                     body: "\(event.displayTitle)\n\(event.start.formatted(date: .abbreviated, time: .shortened))",
                                     thread: "studgo.calendar")
        }
    }

    // MARK: - Neu in deinen Kursen

    /// Eine gesammelte Mitteilung über neue Dateien, Forenbeiträge,
    /// Wikiseiten und Ankündigungen in den belegten Veranstaltungen.
    ///
    /// Der Merker wandert **erst nach Erfolg** - schlägt der eine Abruf
    /// fehl (Netz, Wartung, ein verwaistes Ziel im Strom), gibt es keine
    /// Falschmeldung und beim nächsten Lauf dieselbe Chance noch einmal.
    private static func notifyNewCourseNews(client: StudIPClient,
                                            userID: String,
                                            preferences: Preferences) async {
        let since = preferences.lastNotifiedCourseNews.timeIntervalSince1970 > 0
            ? preferences.lastNotifiedCourseNews
            : Date().addingTimeInterval(-CourseNews.fallbackHorizon)
        guard let items = try? await client.courseNews(since: since, for: userID) else { return }

        let fresh = CourseNews.unmuted(CourseNews.fresh(items, since: since, limit: 30),
                                       muted: preferences.mutedCourseIDs)
        guard let summary = CourseNews.summary(for: fresh) else { return }
        await Notifications.post(title: summary.title, body: summary.body,
                                 thread: "studgo.coursenews")

        if let newest = fresh.first?.createdAt {
            preferences.lastNotifiedCourseNews = newest
        }
    }

    // MARK: - Nachrichten

    /// Sagt zurück, wie viele Nachrichten im Posteingang ungelesen sind -
    /// das Widget zeigt dieselbe Zahl wie das App-Symbol. `nil` heißt: Der
    /// Posteingang ließ sich nicht holen; dann bleibt im Widget der alte
    /// Wert stehen, statt „0 Nachrichten“ zu behaupten.
    @discardableResult
    private static func notifyNewMessages(client: StudIPClient,
                                          userID: String,
                                          preferences: Preferences) async -> Int? {
        guard let inbox = try? await client.inbox(for: userID) else { return nil }
        let unread = inbox.filter { !$0.isRead }.count

        let since = preferences.lastNotifiedMessage
        let fresh = inbox
            .filter { !$0.isRead }
            .filter { ($0.sentAt ?? .distantPast) > since }
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }

        guard !fresh.isEmpty else { return unread }

        if fresh.count > maxAlerts {
            // Gesammelt statt einzeln - sonst wäre der Sperrbildschirm voll.
            await Notifications.post(title: String(localized: "\(fresh.count) neue Nachrichten"),
                                     body: fresh.prefix(3)
                                        .map { $0.counterpart(outgoing: false) ?? $0.subject }
                                        .joined(separator: ", "),
                                     thread: "studgo.inbox")
        } else {
            for message in fresh.reversed() {
                await Notifications.post(title: message.counterpart(outgoing: false)
                                            ?? String(localized: "Neue Nachricht"),
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
            await Notifications.post(title: String(localized: "Neues in \(fresh.count) Unterhaltungen"),
                                     body: fresh.prefix(3).map(\.name).joined(separator: ", "),
                                     thread: "studgo.blubber")
        } else {
            for thread in fresh.reversed() {
                let count = thread.unseenComments
                await Notifications.post(
                    title: thread.name,
                    body: count > 0
                        ? (count == 1 ? String(localized: "1 neuer Beitrag") : String(localized: "\(count) neue Beiträge"))
                        : thread.preview.firstLine,
                    thread: "studgo.blubber")
            }
        }

        if let newest = fresh.first?.latestActivity {
            preferences.lastNotifiedActivity = newest
        }
    }
}
