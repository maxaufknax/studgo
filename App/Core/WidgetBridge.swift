import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Die App-Seite der Widgets: schreibt den Schnappschuss und stößt die
/// Zeitlinien zur Neuberechnung an.
///
/// **Wo das passiert:** „Heute" legt bei jedem Laden den nächsten Termin und
/// die ungelesenen Nachrichten ab - es lädt ohnehin beides. `BackgroundSync`
/// hält den Stand im Hintergrund frisch, `AuthStore` räumt ihn beim Abmelden
/// weg. Die Widgets selbst lesen nur (siehe `WidgetSnapshotStore`).
enum WidgetBridge {
    /// Neuen Stand hinterlegen und die Widgets anstoßen.
    static func publish(next: CourseEvent?, unread: Int) {
        WidgetSnapshotStore.save(WidgetSnapshot(
            nextEvent: next.map { event in
                WidgetSnapshot.NextEvent(title: event.displayTitle,
                                         start: event.start,
                                         end: event.end,
                                         location: event.location)
            },
            unreadMessages: max(0, unread),
            updatedAt: Date()
        ))
        reload()
    }

    /// Nur die ungelesenen Nachrichten erneuern - der Weg des
    /// Hintergrundlaufs, der den nächsten Termin bewusst nicht abruft
    /// (siehe `BackgroundSync`): Der Termin bleibt stehen, wie ihn „Heute“
    /// zuletzt hinterlegt hat.
    static func publish(unread: Int) {
        var snapshot = WidgetSnapshotStore.load()
            ?? WidgetSnapshot(nextEvent: nil, unreadMessages: 0, updatedAt: Date())
        snapshot.unreadMessages = max(0, unread)
        snapshot.updatedAt = Date()
        WidgetSnapshotStore.save(snapshot)
        reload()
    }

    /// Alle Widget-Zeitlinien neu rechnen - im Demo-Modus bewusst auch: Das
    /// Widget zeigt dann Beispieldaten, genau wie der Startbildschirm.
    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Beim Abmelden: Sperrbildschirm und Startbildschirm dürfen nichts mehr
    /// vom bisherigen Konto wissen.
    static func clear() {
        WidgetSnapshotStore.clear()
        reload()
    }
}
