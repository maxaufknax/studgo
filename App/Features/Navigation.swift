import SwiftUI

/// Die Ziele, die in jedem Reiter erreichbar sein müssen — **einmal** je
/// Navigationsstapel angemeldet.
///
/// **Warum zentral:** `navigationDestination(for:)` gilt für den ganzen
/// Stapel, nicht für die Ansicht, an der es steht. Lagen zwei Anmeldungen
/// desselben Typs im selben Stapel — etwa `NewsItem` einmal in `NewsView` und
/// einmal in `CourseNewsView` —, benutzte SwiftUI die wurzelnächste und
/// meldete zur Laufzeit: „A navigationDestination for … was declared earlier
/// on the stack." Angetippt öffnete sich dann die Seite des jeweils anderen
/// Bereichs, und in ungünstiger Reihenfolge schob der Stapel zweimal.
///
/// Deshalb: Ein Reiter meldet an seiner Wurzel diesen Satz an, und keine
/// Unteransicht meldet noch einmal denselben Typ.
struct StudGoDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .navigationDestination(for: CourseEvent.self) { EventDetailView(event: $0) }
            .navigationDestination(for: ScheduleEntry.self) { ScheduleEntryDetailView(entry: $0) }
            .navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }
            .navigationDestination(for: ActivityItem.self) { ActivityDetailView(item: $0) }
            .navigationDestination(for: BlubberThread.self) { BlubberThreadView(thread: $0) }
    }
}

extension View {
    /// An der Wurzel eines `NavigationStack` anzuwenden — nirgends sonst.
    func studGoDestinations() -> some View {
        modifier(StudGoDestinations())
    }
}
