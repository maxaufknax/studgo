import SwiftUI

/// Der Navigationspfad eines Reiters — **eine** Quelle der Wahrheit, im Umfeld
/// hinterlegt, damit ihn jede Zeile erreichen kann.
///
/// **Warum das der Kern der Reparatur ist:** Ein `NavigationLink(value:)` in
/// einer Liste bindet den Sprung an *seine Zeile*. Verschwindet die Zeile,
/// während die Detailseite aufgeht — die Suchleiste räumt beim Weiterschieben
/// von selbst ihren Text, eine nachladende Liste tauscht ihren Inhalt, oder
/// iOS 18 verschluckt sich am Zusammenspiel von `searchable` und `NavigationStack`
/// —, nimmt SwiftUI den halb geschobenen Push wieder zurück oder schiebt gar
/// zweimal. Von außen sah das aus wie „Kurs geöffnet, sofort wieder bei der
/// Auswahl; erst der Zurück-Pfeil führt zur eigentlichen Seite".
///
/// Legt der Push den Wert dagegen in *diesen* Pfad, hängt die Detailseite an
/// nichts, was die Liste darunter tut. Die Zeile darf verschwinden — der Pfad
/// bleibt, und mit ihm die geöffnete Seite.
@Observable
final class Navigator {
    var path = NavigationPath()

    func push<Value: Hashable>(_ value: Value) {
        path.append(value)
    }

    func popToRoot() {
        guard !path.isEmpty else { return }
        path = NavigationPath()
    }
}

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
            // Ordner werden **über den Pfad** geschoben (früher: verschachtelte
            // `NavigationLink { … }`). Ein Ordner in einer nachladenden Liste
            // fiel sonst wieder zu, sobald der übergeordnete Ordner seinen
            // Inhalt austauschte.
            .navigationDestination(for: Folder.self) { FolderContentView(folder: $0) }
    }
}

extension View {
    /// An der Wurzel eines `NavigationStack` anzuwenden — nirgends sonst.
    func studGoDestinations() -> some View {
        modifier(StudGoDestinations())
    }
}

/// Ein Navigationsstapel mit eigenem `Navigator` und allen Zielen.
///
/// Der `Navigator` liegt im Umfeld, sodass jede Zeile über `PushLink` oder
/// direkt `@Environment(Navigator.self)` in *diesen* Stapel schieben kann.
struct StudGoStack<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var navigator = Navigator()

    var body: some View {
        NavigationStack(path: $navigator.path) {
            content
                .studGoDestinations()
        }
        .environment(navigator)
    }
}

/// Wie ein `NavigationLink(value:)`, aber der Sprung läuft über den
/// `Navigator`-Pfad statt über die Zeile.
///
/// Damit überlebt die geöffnete Seite alles, was die Liste darunter noch tut:
/// Nachladen, Umsortieren, das Räumen der Suchleiste. Genau daran scheiterte
/// die value-basierte Verknüpfung (siehe `Navigator`). Optisch bleibt es eine
/// Listenzeile mit Verweispfeil rechts.
struct PushLink<Value: Hashable, Label: View>: View {
    let value: Value
    @ViewBuilder var label: Label

    @Environment(Navigator.self) private var navigator

    var body: some View {
        Button {
            navigator.push(value)
        } label: {
            HStack(spacing: 8) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
