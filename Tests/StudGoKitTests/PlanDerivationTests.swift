import Foundation
import Testing
@testable import StudGoKit

/// Wochenplanblöcke aus datierten Kurssitzungen.
///
/// Der Anlass (Rückmeldung zur Fassung 1.6.1): In den Wochen vor Semesterbeginn
/// liefert `/v1/users/{id}/schedule` für das kommende Semester noch keine
/// Turnustermine — der ICS-Strom die einzelnen Sitzungen aber schon. Das
/// Wochenraster blieb beim alten Semester stehen, während die Listenansicht
/// längst das kommende zeigte. `PlanDerivation` legt die Sitzungen zurück in
/// ein Wochenraster, damit beide Ansichten dasselbe Semester zeigen.
@Suite("Stundenplan aus Sitzungen ableiten")
struct PlanDerivationTests {

    static let calendar = Calendar.current

    static func am(_ text: String, um zeit: String) -> Date {
        let datum = text.split(separator: "-").compactMap { Int($0) }
        let uhr = zeit.split(separator: ":").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: datum[0], month: datum[1],
                                                  day: datum[2], hour: uhr[0],
                                                  minute: uhr[1]))!
    }

    /// Ein datierter Termin über denselben Weg, den auch der ICS-Strom geht.
    static func sitzung(_ id: String, titel: String, am datum: String,
                        von: String, bis: String, kurs: String? = "kurs1",
                        abgesagt: Bool = false, persoenlich: Bool = false) -> CourseEvent {
        // Abgesagte Sitzungen trägt Stud.IP als „… (fällt aus)" im Titel;
        // `CourseEvent(ics:))` erkennt genau das. Persönliche Termine
        // erkennen sich am fehlenden Kennungspräfix.
        let name = abgesagt ? titel + " (fällt aus)" : titel
        let uid = persoenlich ? id : "Stud.IP-SEM-\(id)"
        let event = ICSParser.Event(uid: uid, summary: name, description: nil,
                                    location: nil, categories: nil,
                                    start: am(datum, um: von), end: am(datum, um: bis),
                                    isAllDay: false)
        return CourseEvent(ics: event, courseID: kurs)
    }

    /// Vorlesungszeit des WiSe 2026/27 — ab Montag, 12. Oktober 2026.
    static let vorlesungszeit = am("2026-10-12", um: "00:00")...am("2027-02-06", um: "23:59")

    @Test("Aus einer Turnusreihe wird ein Wochenblock")
    func einBlockJeZeitfenster() {
        // Drei Sitzungen desselben Kurses am selben Wochentag zur selben
        // Stunde — der ICS-Strom listet jede einzeln, der Block im Raster
        // ist einer.
        let sessions = [
            Self.sitzung("a", titel: "11568  Übung: Logik und Formale Systeme",
                         am: "2026-10-13", von: "12:15", bis: "13:45"),
            Self.sitzung("b", titel: "11568  Übung: Logik und Formale Systeme",
                         am: "2026-10-20", von: "12:15", bis: "13:45"),
            Self.sitzung("c", titel: "11568  Übung: Logik und Formale Systeme",
                         am: "2026-10-27", von: "12:15", bis: "13:45"),
        ]

        let entries = PlanDerivation.cycleEntries(from: sessions, within: Self.vorlesungszeit)

        #expect(entries.count == 1)
        #expect(entries.first?.isCourse == true)
        #expect(entries.first?.normalizedWeekday == 2)
        #expect(entries.first?.start == "12:15")
        #expect(entries.first?.end == "13:45")
        #expect(entries.first?.courseID == "kurs1")
    }

    @Test("Zwei Zeitfenster desselben Kurses werden zwei Blöcke")
    func zweiZeitfenster() {
        let sessions = [
            Self.sitzung("a", titel: "Grundlagen der Rechnerarchitektur",
                         am: "2026-10-15", von: "11:30", bis: "13:00"),
            Self.sitzung("b", titel: "Grundlagen der Rechnerarchitektur",
                         am: "2026-10-15", von: "14:15", bis: "15:45"),
        ]

        let entries = PlanDerivation.cycleEntries(from: sessions, within: Self.vorlesungszeit)

        #expect(entries.count == 2)
        #expect(entries.first?.startMinutes == 690)  // 11:30
    }

    @Test("Nur abgesagte Sitzungen ergeben keinen Block")
    func nurAbgesagte() {
        // Fiele eine Turnusreihe komplett aus, stünde sonst eine Übung im
        // Raster, die nie stattfindet.
        let sessions = [Self.sitzung("a", titel: "Übung", am: "2026-10-13",
                                     von: "12:15", bis: "13:45", abgesagt: true)]

        let entries = PlanDerivation.cycleEntries(from: sessions, within: Self.vorlesungszeit)

        #expect(entries.isEmpty)
    }

    @Test("Sitzungen außerhalb des Fensters zählen nicht")
    func nurInnerhalbDesFensters() {
        // Eine SoSe-Sitzung im August darf keinen WiSe-Block erzeugen.
        let sessions = [Self.sitzung("a", titel: "Übung", am: "2026-08-03",
                                     von: "12:15", bis: "13:45")]

        let entries = PlanDerivation.cycleEntries(from: sessions, within: Self.vorlesungszeit)

        #expect(entries.isEmpty)
    }

    @Test("Eigene Termine und Sitzungen ohne Kurs zählen nicht")
    func ohneKursZahlenNicht() {
        let personal = Self.sitzung("a", titel: "Zahnarzt", am: "2026-10-13",
                                    von: "12:15", bis: "13:00", kurs: nil,
                                    persoenlich: true)

        let entries = PlanDerivation.cycleEntries(from: [personal],
                                                  within: Self.vorlesungszeit)

        #expect(entries.isEmpty)
    }
}

@Suite("Titel für die Anzeige glätten")
struct TitleFormatTests {

    @Test("Führende Veranstaltungsnummer fällt weg")
    func nummerFälltWeg() {
        #expect(Format.displayTitle("11568  Übung: Logik und Formale Systeme")
                == "Übung: Logik und Formale Systeme")
        #expect(Format.displayTitle("11412 Gruppenübungen zu Grundlagen der Rechnerarchitektur")
                == "Gruppenübungen zu Grundlagen der Rechnerarchitektur")
    }

    @Test("Mehrfache Leerzeichen werden eins")
    func leerzeichen() {
        #expect(Format.displayTitle("Programmieren 2   Objektorientierung")
                == "Programmieren 2 Objektorientierung")
    }

    @Test("Titel ohne Nummer bleiben, wie sie sind")
    func ohneNummer() {
        #expect(Format.displayTitle("Analysis I") == "Analysis I")
        #expect(Format.displayTitle("Datenbanksysteme – Übung") == "Datenbanksysteme – Übung")
    }

    @Test("Ein Titel aus bloßen Ziffern bleibt stehen")
    func blosseZiffern() {
        #expect(Format.displayTitle("2026") == "2026")
    }
}
