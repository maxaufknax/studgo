import Foundation

/// Alle Wege aus der App hinaus, an einer Stelle.
///
/// **Warum es sie überhaupt gibt:** Nicht alles, was Studierende brauchen,
/// liegt hinter der JSON:API. Drei Sorten von Lücken:
///
/// 1. **Die API verweigert es.** Ein- und Austragen zu Veranstaltungen:
///    `Routes\Courses\Rel\Memberships::authorize()` gibt für jede Methode
///    außer GET hart `false` zurück. Es gibt keine Route, die man übersehen
///    hätte — es gibt sie nicht.
/// 2. **Es steht in einem anderen System.** Prüfungsanmeldung und Noten
///    laufen an der LUH über **QIS** (HISinOne), die Kennung über den
///    **Account-Manager**. Beide haben keine öffentliche Schnittstelle.
/// 3. **Nativ wäre es ein eigenes Projekt.** Profilbild zuschneiden,
///    Courseware bearbeiten, Foren moderieren.
///
/// Für all das ist ein Knopf, der genau auf die richtige Seite führt, ehrlicher
/// als ein nachgebauter Dialog, der auf halbem Weg abbricht.
///
/// **Zur Anmeldung:** Stud.IP der LUH hängt an **Shibboleth**
/// (`login.uni-hannover.de`). Wer dort in Safari eine gültige Sitzung hat,
/// wird beim Öffnen dieser Adressen ohne Zutun durchgereicht — der
/// `SFSafariViewController` teilt sich den Cookie-Vorrat mit Safari. Ob StudGo
/// die Anmeldung überhaupt dorthin legt, entscheidet
/// `Preferences.sharesWebSession`.
enum WebLinks {

    // MARK: - Stud.IP

    private static func studip(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(
            url: AppConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    /// Startseite.
    static var studipHome: URL { AppConfig.baseURL }

    /// Eine Veranstaltung öffnen.
    static func course(_ id: String) -> URL {
        studip("seminar_main.php", query: [URLQueryItem(name: "auswahl", value: id)])
    }

    /// Ein- und Austragen — der einzige Weg, den es dafür gibt.
    static func enrolment(_ courseID: String) -> URL {
        studip("dispatch.php/course/enrolment/apply/\(courseID)")
    }

    /// „Meine Veranstaltungen" — dort wird ausgetragen.
    static var myCourses: URL { studip("dispatch.php/my_courses") }

    /// Der Dateibereich einer Veranstaltung in der Weboberfläche.
    ///
    /// Hochladen kann StudGo inzwischen selbst
    /// (`POST /folders/{id}/file-refs`); dieser Weg bleibt für alles darüber
    /// hinaus — Ordnerrechte, Massenaktionen, Lizenzen im Nachhinein ändern.
    static func courseFiles(_ courseID: String) -> URL {
        studip("dispatch.php/course/files", query: [URLQueryItem(name: "cid", value: courseID)])
    }

    // MARK: - Blubber

    /// Der Blubber der Weboberfläche — ohne Kennung der globale Strom, mit
    /// Kennung genau dieser Faden.
    ///
    /// `app/controllers/blubber.php::index_action($thread_id = null)`. Die
    /// Oberfläche hängt hinter der Adresse noch ein `#/` an; nötig ist es
    /// nicht, der Router liest den Faden aus dem Pfad.
    static func blubber(thread id: String? = nil) -> URL {
        guard let id, !id.isEmpty else { return studip("dispatch.php/blubber") }
        return studip("dispatch.php/blubber/index/\(id)")
    }

    // MARK: - Stundenplan: eigene Termine

    /// Der Stundenplan der Weboberfläche.
    static var schedule: URL { studip("dispatch.php/calendar/schedule") }

    /// **Einen eigenen Termin anlegen.**
    ///
    /// In der JSON:API gibt es dafür nichts: `RouteMap.php` kennt zu
    /// `schedule-entries` genau eine Route, und die ist ein `GET`
    /// (`Routes\Schedule\ScheduleEntriesShow`). Kein POST, kein PATCH, kein
    /// DELETE — auch nicht unter `/users/{id}/schedule`. Die Weboberfläche
    /// legt Termine über `calendar/schedule/entry/add` an; dieselbe Seite
    /// nimmt Wochentag und Uhrzeit als Vorgabewerte entgegen
    /// (`Request::int('dow')`, `Request::get('start'|'end')`), sodass der
    /// Knopf aus der App heraus schon mit dem angetippten Tag aufgeht.
    ///
    /// - Parameters:
    ///   - weekday: 1 = Montag … 7 = Sonntag, wie in Stud.IP.
    ///   - start: "HH:mm"
    ///   - end: "HH:mm"
    static func newScheduleEntry(weekday: Int? = nil,
                                 start: String? = nil,
                                 end: String? = nil) -> URL {
        var query: [URLQueryItem] = []
        if let weekday { query.append(URLQueryItem(name: "dow", value: String(weekday))) }
        if let start {
            // Das Formular verzweigt auf das Feld `start`; ohne es greifen die
            // Vorgaben „nächste volle Stunde", und der angetippte Tag wäre
            // verloren.
            query.append(URLQueryItem(name: "start", value: start))
            query.append(URLQueryItem(name: "end", value: end ?? start))
        }
        return studip("dispatch.php/calendar/schedule/entry/add", query: query)
    }

    /// **Einen eigenen Termin bearbeiten oder löschen.**
    ///
    /// Dieselbe Seite trägt beides; das Löschen läuft serverseitig über einen
    /// `POST` mit CSRF-Merkmal (`CSRFProtection::verifyUnsafeRequest()`) und
    /// ist deshalb nicht als Verweis nachzubauen.
    static func scheduleEntry(_ id: String) -> URL {
        studip("dispatch.php/calendar/schedule/entry/\(id)")
    }

    /// Der persönliche Kalender der Weboberfläche — dort liegen die datierten
    /// Einzeltermine, die nicht Teil des Wochenplans sind.
    static var calendar: URL { studip("dispatch.php/calendar/single") }

    /// Das eigene Profilbild ändern. In der API gibt es dafür nichts:
    /// `Schemas/User` liefert die Adresse des Bildes, mehr nicht.
    static var avatarSettings: URL { studip("dispatch.php/settings/avatar") }

    /// Stud.IPs eigene Benachrichtigungseinstellungen — was per Mail
    /// herausgeht und worüber die Weboberfläche meldet.
    static var notificationSettings: URL { studip("dispatch.php/settings/notification") }

    /// Das eigene Profil, wie andere es sehen.
    static var profile: URL { studip("dispatch.php/profile") }

    // MARK: - Andere Systeme der LUH

    /// **QIS** — Prüfungsverwaltung der LUH (HISinOne).
    ///
    /// Prüfungsanmeldung, Notenspiegel und Bescheinigungen laufen dort und
    /// **nicht** über Stud.IP. Eine Schnittstelle gibt es nicht; wer Klausuren
    /// sucht, findet sie in StudGos Kalender nur, soweit sie als
    /// Veranstaltungstermin eingetragen wurden.
    static let qis = URL(string: "https://qis.verwaltung.uni-hannover.de/")!

    /// **Account-Manager** der LUH (`login.uni-hannover.de/ui`) — Kennwort
    /// ändern, Mailweiterleitung, Dienste freischalten.
    static let accountManager = URL(string: "https://login.uni-hannover.de/ui/")!

    /// Die IT-Dienste des LUIS im Überblick.
    static let itServices = URL(string: "https://www.luis.uni-hannover.de/services/")!

    /// Der Standortfinder der LUH — Gebäude, Hörsäle, Wege.
    static let campusMap = URL(string: "https://standortfinder.uni-hannover.de/de/")!

    /// Mensen und Cafés des Studentenwerks Hannover.
    ///
    /// **Falls das je nativ werden soll:** Es gibt eine offene Quelle —
    /// [OpenMensa](https://openmensa.org) führt alle Hannoveraner Mensen
    /// (Kennungen 6, 7 und 9 bis 17; die Hauptmensa ist 6) mit Speisen,
    /// Preisen nach Gruppe und Kennzeichnungen unter
    /// `GET /api/v2/canteens/{id}/days/{YYYY-MM-DD}/meals`. Kein Schlüssel,
    /// kein Scraping der Studentenwerk-Seite, keine Urheberrechtsfrage.
    static let canteen = URL(string: "https://www.studentenwerk-hannover.de/essen/mensen-und-cafes")!

    /// Sucht einen Raum im Standortfinder.
    ///
    /// Stud.IP schreibt Räume als „1101 - E001": vorn die Gebäudenummer der
    /// LUH, dahinter der Raum. Der Standortfinder findet über die
    /// Gebäudenummer zuverlässig, über den vollen Text nicht.
    static func campusMap(searching room: String) -> URL {
        let building = room.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
        var components = URLComponents(url: campusMap, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: building ?? room)]
        return components.url ?? campusMap
    }
}
