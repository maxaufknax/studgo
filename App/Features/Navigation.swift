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
            .navigationDestination(for: Message.self) { MessageDetailView(message: $0) }
    }
}

extension View {
    /// An der Wurzel eines `NavigationStack` anzuwenden — nirgends sonst.
    func studGoDestinations() -> some View {
        modifier(StudGoDestinations())
    }
}

/// Ein Navigationsstapel mit eigenem Pfad und allen Zielen.
///
/// **Warum der Pfad ausdrücklich geführt wird:** Ohne `path`-Bindung hängt ein
/// `NavigationLink(value:)` an der Zeile, die ihn erzeugt hat. Verschwindet
/// diese Zeile, während die Detailseite offen ist, nimmt SwiftUI die Seite
/// wieder vom Stapel — die App springt von selbst zurück.
///
/// Genau das passierte bei den **Studiengruppen**: Die Ansicht lädt „Meine
/// Gruppen" und „Vorschläge" nebenläufig und tauscht beim Suchen den ganzen
/// Listeninhalt aus. Traf eine Antwort ein, nachdem man eine Gruppe
/// angetippt hatte — oder räumte die Suchleiste beim Weiterschieben ihren Text
/// weg —, wurde die Zeile neu gebaut und die eben geöffnete Gruppe fiel wieder
/// zu. Von außen sah das aus, als schöbe die App eigenmächtig vor und zurück.
///
/// Mit eigenem Pfad liegt das Ziel im Stapel, nicht in der Zeile: Die
/// Detailseite bleibt stehen, egal was die Liste darunter tut.
struct StudGoStack<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .studGoDestinations()
        }
    }
}
