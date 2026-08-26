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

/// Jede Seite, die in einem Reiter aufgeschlagen werden kann — als **Wert**.
///
/// **Warum das 1.4.0 überhaupt gibt.** Bis 1.3.0 gab es zwei Arten zu
/// schieben, und sie vertrugen sich nicht:
///
/// * `NavigationLink(value:)` bzw. `PushLink` legen den Wert in
///   `Navigator.path`. Der Stapel ist dann genau das, was im Pfad steht.
/// * `NavigationLink { Ziel } label: { … }` schiebt die Seite dagegen an
///   `path` **vorbei**. SwiftUI zeigt sie, aber der Pfad weiß nichts davon.
///
/// Solange nur die zweite Art benutzt wurde, fiel das nicht auf. Sobald aber
/// *hinter* einer so geschobenen Seite eine `PushLink`-Zeile lag — die
/// Studiengruppen im Campus-Reiter, der Aushang einer Veranstaltung, das
/// Verzeichnis —, stand der Pfad plötzlich auf einem Element, während im
/// Stapel schon zwei Seiten lagen. SwiftUI gleicht den Stapel gegen den Pfad
/// ab und räumt dabei die Zwischenseite ab: Man tippte eine Ankündigung an,
/// landete darauf, ging zurück — und stand nicht im Aushang, sondern zwei
/// Ebenen weiter unten oder gleich wieder auf der Übersicht.
///
/// Deshalb führen ab 1.4.0 **alle** Sprünge über den Pfad. Diese Aufzählung
/// ist das Verzeichnis dafür: ein Fall je Seite, `Hashable`, ohne Ansicht und
/// ohne Ladezustand darin.
enum Route: Hashable {

    // MARK: Veranstaltung

    /// Eine Veranstaltung, von der nur die Kennung bekannt ist — aus einem
    /// Termin, einer Meldung oder dem Stundenplan heraus.
    case courseByID(String)
    case courseDates(Course)
    case courseFiles(Course)
    case courseParticipants(Course)
    case courseNews(Course)
    case courseForum(Course)
    case courseWiki(Course)
    case courseBlubber(Course)
    case forumCategory(ForumCategory)
    case forumEntry(ForumEntry)
    case wikiPage(WikiPage)

    // MARK: Campus

    case statistics
    case activityStream
    case courseSearch
    case personSearch
    case contacts
    case studygroups
    case institutes
    case announcements

    // MARK: Profil und Einstellungen

    /// Das Profilblatt führt einen **eigenen** Stapel (es ist ein Sheet), aber
    /// denselben Pfad-Mechanismus. Ohne diese Fälle blieben dort
    /// `NavigationLink { … }` übrig — und die schoben an dem Pfad vorbei, in
    /// dem `PushLink` seine Werte ablegt: Eine Ankündigung, aus den
    /// Einstellungen heraus geöffnet, landete hinter dem Blatt im Reiter
    /// darunter.
    case appearance
    case notificationSettings
    case semesters
    case mailSetup
    case about

    // MARK: Kalender

    /// Die selbst angelegten Termine des Stundenplans — anlegen, ändern,
    /// löschen.
    case ownScheduleEntries
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
    /// Wer angemeldet ist. Mehrere Seiten (eigene Zahlen, Kontakte,
    /// Einrichtungen, Ankündigungen) hängen daran — und da die Ziele hier
    /// zentral entstehen, muss die Person mitgereicht werden.
    let user: StudIPUser

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
            .navigationDestination(for: Route.self) { destination(for: $0) }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .courseByID(let id):             CourseLoaderView(courseID: id)
        case .courseDates(let course):        CourseDatesView(course: course)
        case .courseFiles(let course):        FolderBrowserView(course: course)
        case .courseParticipants(let course): CourseParticipantsView(course: course)
        case .courseNews(let course):         CourseNewsView(course: course)
        case .courseForum(let course):        CourseForumView(course: course)
        case .courseWiki(let course):         CourseWikiView(course: course)
        case .courseBlubber(let course):      CourseBlubberView(course: course)
        case .forumCategory(let category):    ForumCategoryView(category: category)
        case .forumEntry(let entry):          ForumEntryView(entry: entry)
        case .wikiPage(let page):             WikiPageView(page: page)

        case .statistics:                     StatisticsView(user: user)
        case .activityStream:                 ActivityStreamView(user: user)
        case .courseSearch:                   CourseSearchView()
        case .personSearch:                   PersonSearchView()
        case .contacts:                       ContactsView(user: user)
        case .studygroups:                    StudygroupsView()
        case .institutes:                     InstitutesView(user: user)
        case .announcements:                  NewsView(user: user)

        case .appearance:                     AppearanceView()
        case .notificationSettings:           NotificationSettingsView()
        case .semesters:                      SemesterListView()
        case .mailSetup:                      MailSetupView()
        case .about:                          AboutView()

        case .ownScheduleEntries:             OwnScheduleEntriesView(user: user)
        }
    }
}

extension View {
    /// An der Wurzel eines `NavigationStack` anzuwenden — nirgends sonst.
    func studGoDestinations(user: StudIPUser) -> some View {
        modifier(StudGoDestinations(user: user))
    }
}

/// Ein Navigationsstapel mit eigenem `Navigator` und allen Zielen.
///
/// Der `Navigator` liegt im Umfeld, sodass jede Zeile über `PushLink` oder
/// direkt `@Environment(Navigator.self)` in *diesen* Stapel schieben kann.
struct StudGoStack<Content: View>: View {
    let user: StudIPUser
    @ViewBuilder var content: Content

    @State private var navigator = Navigator()

    var body: some View {
        NavigationStack(path: $navigator.path) {
            content
                .studGoDestinations(user: user)
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

/// Ein Sprung über den Pfad **ohne** Listen-Aufmachung — für Kacheln, Karten
/// und alles, was seinen eigenen Rahmen mitbringt.
///
/// `PushLink` hängt rechts ein Winkelzeichen an und dehnt die Beschriftung auf
/// die volle Breite; in einem Kachelraster ist beides falsch.
struct PushButton<Value: Hashable, Label: View>: View {
    let value: Value
    @ViewBuilder var label: Label

    @Environment(Navigator.self) private var navigator

    var body: some View {
        Button {
            navigator.push(value)
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
