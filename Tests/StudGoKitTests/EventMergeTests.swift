import Foundation
import Testing
@testable import StudGoKit

/// Was aus dem Wochenplan zu datierten Terminen wird.
///
/// Der Anlass für diese Suite ist ein Befund aus dem Testflug 1.3.0: Zwei
/// selbst angelegte Termine („Tutorium Philosophie") standen im Wochenraster,
/// in der Tagesansicht dagegen nicht. Die Ursache lag hier — beide Sorten
/// Eintrag wurden gleich behandelt und in der vorlesungsfreien Zeit
/// weggeworfen.
@Suite("Terminquellen zusammenführen")
struct EventMergeTests {

    /// **Bewusst der Kalender des Systems.** Sonst schlägt der Test genau da
    /// zu, wo er nichts prüfen soll: `EventMerge` rechnet mit
    /// `Calendar.current`, und ein hier in Europe/Berlin gebauter Montag
    /// 00:00 ist unter UTC der Sonntag davor — `startOfDay` schiebt ihn
    /// zurück, `Weekday.of` liest einen anderen Wochentag, und die Sitzung
    /// fällt heraus. Genau das ist auf dem Codemagic-Läufer (UTC) passiert,
    /// während die Suite auf dem Entwicklungsrechner (`TZ=Europe/Berlin`)
    /// durchlief.
    ///
    /// Ein Tag „Montag" heißt hier also: Montag dort, wo das Gerät steht —
    /// und das ist genau die Zusicherung, die der Kalender in der App gibt.
    static let calendar = Calendar.current

    static func entry(id: String, titel: String, wochentag: Int,
                      von: String, bis: String, kurs: Bool) throws -> ScheduleEntry {
        let type = kurs ? "seminar-cycle-dates" : "schedule-entries"
        let owner = kurs
            ? """
              , "relationships": {"owner": {"data": {"type": "courses", "id": "kurs1"}}}
              """
            : ""
        let json = """
        {"data": {"type": "\(type)", "id": "\(id)", "attributes": {
            "title": "\(titel)", "weekday": \(wochentag),
            "start": "\(von)", "end": "\(bis)"}\(owner)}}
        """
        let doc = try JSONAPIDocument(data: Data(json.utf8))
        let resource = try #require(doc.first)
        return try #require(ScheduleEntry(resource))
    }

    static func am(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0],
                                                  month: parts[1],
                                                  day: parts[2]))!
    }

    /// Montag, 24. August 2026 — mitten in den Semesterferien.
    static let ferienMontag = am("2026-08-24")
    /// Vorlesungszeit des Wintersemesters, weit nach diesem Montag.
    static let vorlesungszeit = am("2026-10-12")...am("2027-02-06")

    @Test("Ein eigener Termin gilt auch in der vorlesungsfreien Zeit")
    func eigenerTerminInDenFerien() throws {
        let tutorium = try Self.entry(id: "t1", titel: "Tutorium Philosophie",
                                      wochentag: 1, von: "16:00", bis: "18:00", kurs: false)

        let sessions = EventMerge.plannedSessions(from: [tutorium],
                                                  startingAt: Self.ferienMontag,
                                                  days: 7,
                                                  within: Self.vorlesungszeit)

        #expect(sessions.count == 1)
        #expect(sessions.first?.title == "Tutorium Philosophie")
        #expect(sessions.first?.isPersonal == true)
    }

    @Test("Eine Vorlesung gilt in der vorlesungsfreien Zeit nicht")
    func kurssitzungNichtInDenFerien() throws {
        let vorlesung = try Self.entry(id: "c1", titel: "Analysis I",
                                       wochentag: 1, von: "10:00", bis: "12:00", kurs: true)

        let sessions = EventMerge.plannedSessions(from: [vorlesung],
                                                  startingAt: Self.ferienMontag,
                                                  days: 7,
                                                  within: Self.vorlesungszeit)

        #expect(sessions.isEmpty)
    }

    @Test("In der Vorlesungszeit kommen beide Sorten")
    func beideSortenInDerVorlesungszeit() throws {
        let vorlesung = try Self.entry(id: "c1", titel: "Analysis I",
                                       wochentag: 1, von: "10:00", bis: "12:00", kurs: true)
        let tutorium = try Self.entry(id: "t1", titel: "Tutorium Philosophie",
                                      wochentag: 1, von: "16:00", bis: "18:00", kurs: false)

        // Montag, 19. Oktober 2026 — in der Vorlesungszeit.
        let sessions = EventMerge.plannedSessions(from: [vorlesung, tutorium],
                                                  startingAt: Self.am("2026-10-19"),
                                                  days: 1,
                                                  within: Self.vorlesungszeit)

        #expect(sessions.count == 2)
        #expect(Set(sessions.map(\.title)) == ["Analysis I", "Tutorium Philosophie"])
    }

    /// Ohne bekannte Vorlesungszeit werden **keine** Kurssitzungen erfunden —
    /// die eigenen Termine stehen trotzdem, denn für die gibt es serverseitig
    /// gar keinen Semesterbezug.
    @Test("Ohne Vorlesungszeit bleiben nur die eigenen Termine")
    func ohneVorlesungszeit() throws {
        let vorlesung = try Self.entry(id: "c1", titel: "Analysis I",
                                       wochentag: 1, von: "10:00", bis: "12:00", kurs: true)
        let tutorium = try Self.entry(id: "t1", titel: "Tutorium Philosophie",
                                      wochentag: 1, von: "16:00", bis: "18:00", kurs: false)

        let sessions = EventMerge.plannedSessions(from: [vorlesung, tutorium],
                                                  startingAt: Self.ferienMontag,
                                                  days: 1,
                                                  within: nil)

        #expect(sessions.map(\.title) == ["Tutorium Philosophie"])
    }

    /// Derselbe eigene Termin steckt in beiden Wochenplänen (laufendes und
    /// kommendes Semester) — serverseitig laufen die Einträge ohne
    /// Semesterfilter mit. Doppelt im Kalender stehen darf er trotzdem nicht.
    @Test("Ein Termin aus zwei Plänen erscheint einmal")
    func keineDoppelten() throws {
        let tutorium = try Self.entry(id: "t1", titel: "Tutorium Philosophie",
                                      wochentag: 1, von: "16:00", bis: "18:00", kurs: false)

        let merged = EventMerge.combine(
            dated: [],
            plans: [EventMerge.PlanWindow(entries: [tutorium], period: Self.vorlesungszeit),
                    EventMerge.PlanWindow(entries: [tutorium], period: nil)],
            from: Self.ferienMontag,
            days: 7)

        #expect(merged.count == 1)
    }
}

// MARK: - Deduplizierung (Rückmeldung 1.6.1: doppelt angezeigte Termine)

extension EventMergeTests {

    /// Zwei Darstellungen desselben Termins aus einer Hand: ein datierter
    /// Termin in zwei Kopien. `combine` muss ihn einmal zeigen.
    static func icsEvent(id: String, titel: String, am tag: String,
                         von: String, bis: String, kurs: String? = nil,
                         persoenlich: Bool = false) -> CourseEvent {
        let uhr = { (_ zeit: String) -> Date in
            let teile = zeit.split(separator: ":").compactMap { Int($0) }
            return Self.calendar.date(bySettingHour: teile[0], minute: teile[1],
                                      second: 0, of: Self.am(tag))!
        }
        let uid = persoenlich ? id : "Stud.IP-SEM-\(id)"
        let event = ICSParser.Event(uid: uid, summary: titel, description: nil,
                                    location: nil, categories: nil,
                                    start: uhr(von), end: uhr(bis), isAllDay: false)
        return CourseEvent(ics: event, courseID: kurs)
    }

    @Test("Dieselbe Sitzung zweimal im ICS-Strom erscheint einmal")
    func doppelteSitzungImStrom() throws {
        // exportCalendarDates + exportCourseDates liefern dieselbe Sitzung,
        // wenn sie auch im persönlichen Kalender liegt — mit derselben
        // Kennung der Veranstaltung.
        let erste = Self.icsEvent(id: "a", titel: "Logik und Formale Systeme",
                                  am: "2026-10-13", von: "12:15", bis: "13:45", kurs: "kurs1")
        let zweite = Self.icsEvent(id: "b", titel: "11568  Übung: Logik und Formale Systeme",
                                   am: "2026-10-13", von: "12:15", bis: "13:45", kurs: "kurs1")

        let merged = EventMerge.combine(dated: [erste, zweite], plans: [], days: 1)

        #expect(merged.count == 1)
    }

    @Test("Zwei verschiedene Veranstaltungen zur selben Stunde bleiben beide")
    func verschiedeneKurseGleicheStunde() throws {
        // Bis 1.7.0 flog jede abgeleitete Sitzung aus dem Raster, sobald
        // *irgendein* datierter Termin den Slot belegte — Vorlesung und
        // Übung im selben Block verloren so die eine Hälfte.
        let vorlesung = Self.icsEvent(id: "a", titel: "Analysis I",
                                      am: "2026-10-13", von: "10:00", bis: "12:00", kurs: "kursA")
        let uebung = Self.icsEvent(id: "b", titel: "Analysis I Übung",
                                   am: "2026-10-13", von: "10:00", bis: "12:00", kurs: "kursB")

        let merged = EventMerge.combine(dated: [vorlesung, uebung], plans: [], days: 1)

        #expect(merged.count == 2)
    }

    @Test("Eine abgeleitete Sitzung weicht dem echten Termin desselben Kurses")
    func abgeleiteteWeichtEchtem() throws {
        let echt = Self.icsEvent(id: "a", titel: "11568 Übung: Logik und Formale Systeme",
                                 am: "2026-10-13", von: "12:15", bis: "13:45", kurs: "kurs1")
        let vorlesung = try Self.entry(id: "c1", titel: "Logik und Formale Systeme",
                                       wochentag: 2, von: "12:15", bis: "13:45", kurs: true)

        let merged = EventMerge.combine(
            dated: [echt],
            plans: [EventMerge.PlanWindow(entries: [vorlesung], period: Self.vorlesungszeit)],
            from: Self.am("2026-10-12"),
            days: 7)

        #expect(merged.count == 1)
    }

    @Test("Ein persönlicher Termin zur Vorlesungsstunde bleibt sichtbar")
    func persoenlicherTerminZurVorlesungsstunde() throws {
        // Vorlesung um 10 Uhr, persönlicher Termin (Zahnarzt) auch um 10 Uhr:
        // zwei Termine, die nichts miteinander zu tun haben.
        let vorlesung = Self.icsEvent(id: "a", titel: "Analysis I",
                                      am: "2026-10-13", von: "10:00", bis: "12:00", kurs: "kursA")
        let arzt = Self.icsEvent(id: "b", titel: "Zahnarzt",
                                 am: "2026-10-13", von: "10:00", bis: "11:00", persoenlich: true)

        let merged = EventMerge.combine(dated: [vorlesung, arzt], plans: [], days: 1)

        #expect(merged.count == 2)
    }

    @Test("Titel-Wortfolgen: Analysis I ist nicht Analysis II")
    func wortfolgen() {
        #expect(EventMerge.titleWords("11568  Übung: Logik und Formale Systeme")
                == ["11568", "ubung", "logik", "und", "formale", "systeme"])
        #expect(EventMerge.isSameEvent(
            Self.icsEvent(id: "a", titel: "Analysis I", am: "2026-10-13", von: "10:00", bis: "12:00"),
            Self.icsEvent(id: "b", titel: "Analysis II", am: "2026-10-13", von: "10:00", bis: "12:00"))
            == false)
        #expect(EventMerge.isSameEvent(
            Self.icsEvent(id: "a", titel: "Logik und Formale Systeme", am: "2026-10-13", von: "12:15", bis: "13:45"),
            Self.icsEvent(id: "b", titel: "11568 Übung: Logik und Formale Systeme", am: "2026-10-13", von: "12:15", bis: "13:45"))
            == true)
    }
}
