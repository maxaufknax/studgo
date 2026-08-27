import Foundation

/// Die Daten hinter dem Demo-Modus — ein vollständiges, erfundenes
/// Stud.IP-Konto.
///
/// **Wozu:** Die Anmeldung an StudGo läuft über OAuth2 gegen
/// `studip.uni-hannover.de`, und dort hängt die LUH an **Shibboleth**. Wer
/// keine Kennung der Leibniz Universität hat, kommt an keinen einzigen
/// Bildschirm der App — das betrifft die Prüfung im App Store genauso wie
/// jeden, der sich die App vor der Einschreibung ansehen möchte. Ein
/// Demo-Konto beim Rechenzentrum zu beantragen hilft nicht: Es müsste
/// dauerhaft gültig bleiben, das Kennwort stünde in einem Formular bei Apple,
/// und die Prüfung fiele trotzdem aus, sobald das Kennwort abläuft.
///
/// Deshalb liegt die Demo **in der App**. `DemoServer` beantwortet dieselben
/// Routen wie Stud.IP, mit denselben Feldnamen — die Modelle, der Parser, der
/// ICS-Leser, das Zusammenführen der Termine laufen unverändert. Was der
/// Prüfer sieht, ist also nicht ein zweiter, nachgebauter Bildschirmsatz,
/// sondern die echte App an einer erfundenen Datenlage.
///
/// **Alles hier ist erfunden.** Namen, Veranstaltungen, Nachrichten und
/// Raumnummern gehören zu niemandem. Die Termine werden bei jedem Zugriff
/// relativ zum heutigen Tag erzeugt, damit die Demo weder veraltet noch in
/// die vorlesungsfreie Zeit fällt.
enum DemoData {

    // MARK: - Kennungen

    static let userID = "demo-alex"
    static let globalThreadID = "global"

    // MARK: - Kalender

    /// Fester Kalender für alle abgeleiteten Daten. `firstWeekday = 2` ist
    /// nötig, damit `yearForWeekOfYear` den **Montag** der Woche liefert und
    /// nicht den Sonntag davor.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    static var today: Date { calendar.startOfDay(for: Date()) }

    /// Montag der laufenden Woche.
    static var monday: Date {
        let calendar = self.calendar
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        return calendar.date(from: parts) ?? today
    }

    /// Ein Tag der Woche `weekOffset` mit Stud.IP-Wochentag (1 = Montag).
    static func day(weekday: Int, weekOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day,
                      value: (weekday - 1) + weekOffset * 7,
                      to: monday) ?? monday
    }

    /// „14:15" auf einem Tag.
    static func at(_ clock: String, on day: Date) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }

    static func days(_ count: Int, from base: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: count, to: base ?? today) ?? today
    }

    /// ISO-8601 mit Zeitzone — genau so schreibt Stud.IP jeden Zeitstempel.
    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return formatter.string(from: date)
    }

    // MARK: - Semester

    struct DemoSemester {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let lectureStart: Date
        let lectureEnd: Date
        let isCurrent: Bool
    }

    /// Zwei Semester, so gelegt, dass **heute** immer in der Vorlesungszeit
    /// des laufenden liegt.
    ///
    /// Das ist bewusst nicht der echte Kalender der LUH: Fiele die Demo in
    /// die vorlesungsfreie Zeit, zeigte der Stundenplan zu Recht ein blasses
    /// Raster und der Startbildschirm „keine Termine" — richtig, aber als
    /// erster Eindruck der App unbrauchbar.
    static var semesters: [DemoSemester] {
        let current = DemoSemester(
            id: "sem-current",
            title: seasonTitle(for: today),
            start: days(-70),
            end: days(84),
            lectureStart: days(-42),
            lectureEnd: days(56),
            isCurrent: true)
        let nextStart = days(85)
        let next = DemoSemester(
            id: "sem-next",
            title: seasonTitle(for: days(200)),
            start: nextStart,
            end: days(250),
            lectureStart: days(112),
            lectureEnd: days(210),
            isCurrent: false)
        return [current, next]
    }

    /// „Sommersemester 2026" bzw. „Wintersemester 2026/27" — nach dem Monat,
    /// wie es die LUH benennt.
    static func seasonTitle(for date: Date) -> String {
        let calendar = self.calendar
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        if (4...9).contains(month) { return "Sommersemester \(year)" }
        let first = month >= 10 ? year : year - 1
        return "Wintersemester \(first)/\(String(format: "%02d", (first + 1) % 100))"
    }

    // MARK: - Personen

    struct DemoPerson {
        let id: String
        let username: String
        let name: String
        let given: String
        let family: String
        let email: String
        let role: String
    }

    static let me = DemoPerson(id: userID, username: "muster",
                               name: "Alex Muster", given: "Alex", family: "Muster",
                               email: "alex.muster@stud.uni-hannover.de",
                               role: "autor")

    static let people: [DemoPerson] = [
        me,
        DemoPerson(id: "demo-weber", username: "weber",
                   name: "Prof. Dr. Julia Weber", given: "Julia", family: "Weber",
                   email: "julia.weber@demo.invalid", role: "dozent"),
        DemoPerson(id: "demo-sobczak", username: "sobczak",
                   name: "Marek Sobczak", given: "Marek", family: "Sobczak",
                   email: "marek.sobczak@demo.invalid", role: "tutor"),
        DemoPerson(id: "demo-behrens", username: "behrens",
                   name: "Lena Behrens", given: "Lena", family: "Behrens",
                   email: "lena.behrens@demo.invalid", role: "autor"),
        DemoPerson(id: "demo-okonkwo", username: "okonkwo",
                   name: "Dr. Chidi Okonkwo", given: "Chidi", family: "Okonkwo",
                   email: "chidi.okonkwo@demo.invalid", role: "dozent"),
        DemoPerson(id: "demo-studienbuero", username: "studienbuero",
                   name: "Studienbüro Informatik", given: "Studienbüro", family: "Informatik",
                   email: "studienbuero@demo.invalid", role: "autor"),
        DemoPerson(id: "demo-haas", username: "haas",
                   name: "Tim Haas", given: "Tim", family: "Haas",
                   email: "tim.haas@demo.invalid", role: "autor"),
    ]

    static func person(_ id: String) -> DemoPerson? {
        people.first { $0.id == id }
    }

    // MARK: - Veranstaltungen

    struct DemoCourse {
        let id: String
        let title: String
        let subtitle: String?
        let number: String?
        let typeID: Int
        let room: String?
        let description: String
        let enrolled: Bool
    }

    /// Die Veranstaltungsarten dieser „Installation". `sem-class` 1 sind
    /// gewöhnliche Veranstaltungen, 5 sind Studiengruppen — daraus leitet
    /// `StudygroupKinds` ab, was eine Studiengruppe ist.
    static let semTypes: [(id: String, name: String, classID: String)] = [
        ("1", "Vorlesung", "1"),
        ("2", "Seminar", "1"),
        ("3", "Übung", "1"),
        ("4", "Praktikum", "1"),
        ("99", "Studiengruppe", "5"),
    ]

    static let studygroupClassID = "5"

    static let courses: [DemoCourse] = [
        DemoCourse(id: "demo-analysis",
                   title: "Analysis für Ingenieurinnen und Ingenieure I",
                   subtitle: "Vorlesung mit Übung",
                   number: "10101", typeID: 1, room: "1101 - E001",
                   description: """
                   **Inhalt der Veranstaltung**

                   - Folgen, Reihen und Konvergenzkriterien
                   - Stetigkeit und Differenzierbarkeit
                   - Integralrechnung in einer Veränderlichen

                   Die Übungsblätter erscheinen jeweils **montags** im \
                   Dateibereich und werden in der folgenden Woche besprochen.

                   [Skript zur Vorlesung]https://www.uni-hannover.de
                   """,
                   enrolled: true),
        DemoCourse(id: "demo-prog2",
                   title: "Programmieren 2 — Objektorientierung",
                   subtitle: nil,
                   number: "10203", typeID: 1, room: "3703 - 023",
                   description: """
                   <!--HTML--><p>Diese Veranstaltung setzt <b>Programmieren 1</b> fort. \
                   Im Mittelpunkt stehen Vererbung, Schnittstellen und Testen.</p>\
                   <p>Die Abgabe der Programmieraufgaben erfolgt w&ouml;chentlich \
                   bis Freitag, 12:00 Uhr.</p>
                   """,
                   enrolled: true),
        DemoCourse(id: "demo-dbs",
                   title: "Datenbanksysteme",
                   subtitle: "Grundlagen relationaler Systeme",
                   number: "30410", typeID: 1, room: "1101 - B305",
                   description: """
                   Relationales Modell, SQL, Normalformen, Transaktionen.
                   Das Wiki der Veranstaltung sammelt die Beispielabfragen.
                   """,
                   enrolled: true),
        DemoCourse(id: "demo-ethik",
                   title: "Technikethik",
                   subtitle: "Studium Generale",
                   number: "50120", typeID: 2, room: "1146 - A210",
                   description: """
                   Seminar mit Lektüre und Diskussion. Die Teilnahme wird über
                   ein Referat und ein Essay abgeschlossen.
                   """,
                   enrolled: true),
        DemoCourse(id: "demo-lerngruppe",
                   title: "Lerngruppe Analysis",
                   subtitle: nil,
                   number: nil, typeID: 99, room: nil,
                   description: "Wir treffen uns freitags in der Bibliothek und rechnen die Blätter durch.",
                   enrolled: true),
        // Nicht belegt — nur über die Suche zu finden.
        DemoCourse(id: "demo-lineare-algebra",
                   title: "Lineare Algebra für Informatik",
                   subtitle: nil, number: "10110", typeID: 1, room: "1101 - F303",
                   description: "Vektorräume, lineare Abbildungen, Eigenwerte.",
                   enrolled: false),
        DemoCourse(id: "demo-betriebssysteme",
                   title: "Betriebssysteme",
                   subtitle: nil, number: "30220", typeID: 1, room: "3703 - 135",
                   description: "Prozesse, Speicherverwaltung, Dateisysteme.",
                   enrolled: false),
        DemoCourse(id: "demo-sg-erstsemester",
                   title: "Studiengruppe Erstsemester Informatik",
                   subtitle: nil, number: nil, typeID: 99, room: nil,
                   description: "Austausch für alle im ersten Semester.",
                   enrolled: false),
        DemoCourse(id: "demo-sg-python",
                   title: "Studiengruppe Python am Wochenende",
                   subtitle: nil, number: nil, typeID: 99, room: nil,
                   description: "Kleine Projekte, jeden zweiten Samstag.",
                   enrolled: false),
    ]

    static var enrolledCourses: [DemoCourse] { courses.filter(\.enrolled) }

    static func course(_ id: String) -> DemoCourse? { courses.first { $0.id == id } }

    // MARK: - Stundenplan

    struct DemoSlot {
        let id: String
        let title: String
        let courseID: String?
        /// 1 = Montag … 7 = Sonntag, wie in Stud.IP.
        let weekday: Int
        let start: String
        let end: String
        let room: String?
        let note: String?
        /// Sitzungsthemen, die im ICS-Strom unter `DESCRIPTION` landen.
        let topics: [String]
    }

    /// Sieben Veranstaltungstermine und zwei eigene Einträge — genug für ein
    /// glaubwürdiges Wochenraster, wenig genug, um übersichtlich zu bleiben.
    static let slots: [DemoSlot] = [
        DemoSlot(id: "demo-cyc-1", title: "Analysis für Ingenieurinnen und Ingenieure I",
                 courseID: "demo-analysis", weekday: 1, start: "10:15", end: "11:45",
                 room: "1101 - E001", note: nil,
                 topics: ["Konvergenz von Reihen", "Potenzreihen", "Stetigkeit",
                          "Der Mittelwertsatz", "Taylorentwicklung"]),
        DemoSlot(id: "demo-cyc-2", title: "Programmieren 2 — Objektorientierung",
                 courseID: "demo-prog2", weekday: 1, start: "14:00", end: "15:30",
                 room: "3703 - 023", note: nil,
                 topics: ["Vererbung", "Schnittstellen", "Generics", "Testen mit JUnit",
                          "Entwurfsmuster"]),
        DemoSlot(id: "demo-cyc-3", title: "Datenbanksysteme",
                 courseID: "demo-dbs", weekday: 2, start: "09:15", end: "10:45",
                 room: "1101 - B305", note: nil,
                 topics: ["Relationales Modell", "SQL: Joins", "Normalformen",
                          "Transaktionen", "Indexe"]),
        DemoSlot(id: "demo-cyc-4", title: "Übung Analysis",
                 courseID: "demo-analysis", weekday: 2, start: "14:15", end: "15:45",
                 room: "1101 - F303", note: nil,
                 topics: ["Blatt 3", "Blatt 4", "Blatt 5", "Blatt 6", "Blatt 7"]),
        DemoSlot(id: "demo-cyc-5", title: "Technikethik",
                 courseID: "demo-ethik", weekday: 3, start: "12:00", end: "13:30",
                 room: "1146 - A210", note: nil,
                 topics: ["Verantwortung in der Technik", "Datenschutz als Wert",
                          "Automatisierung und Arbeit", "Referate", "Abschlussdiskussion"]),
        DemoSlot(id: "demo-cyc-6", title: "Tutorium Programmieren 2",
                 courseID: "demo-prog2", weekday: 4, start: "10:15", end: "11:45",
                 room: "3703 - 135", note: nil,
                 topics: ["Aufgabe 3 besprechen", "Debugging", "Codeverbesserung",
                          "Aufgabe 6 besprechen", "Klausurvorbereitung"]),
        DemoSlot(id: "demo-cyc-7", title: "Datenbanksysteme — Übung",
                 courseID: "demo-dbs", weekday: 5, start: "09:15", end: "10:45",
                 room: "1101 - B302", note: nil,
                 topics: ["SQL üben", "Normalisierung üben", "ER-Diagramme",
                          "Anfrageoptimierung", "Probeklausur"]),
        DemoSlot(id: "demo-entry-1", title: "Hochschulsport: Volleyball",
                 courseID: nil, weekday: 3, start: "18:00", end: "19:30",
                 room: nil, note: "Sporthalle Am Moritzwinkel", topics: []),
        DemoSlot(id: "demo-entry-2", title: "Lerngruppe Analysis",
                 courseID: nil, weekday: 5, start: "14:00", end: "16:00",
                 room: nil, note: "Bibliothek, 2. Obergeschoss", topics: []),
    ]

    /// Eine Sitzung, die ausfällt — im ICS-Strom mit „(fällt aus)" markiert,
    /// damit die Ansicht ihren durchgestrichenen Zustand auch zeigt.
    static let cancelledSlotID = "demo-cyc-5"
    static let cancelledWeekOffset = 1

    /// Einzeltermine des persönlichen Kalenders.
    struct DemoAppointment {
        let id: String
        let title: String
        let description: String?
        let dayOffset: Int
        let start: String
        let end: String
        let location: String?
    }

    static let appointments: [DemoAppointment] = [
        DemoAppointment(id: "demo-cal-1", title: "Abgabe Übungsblatt 4",
                        description: "Programmieren 2 — Abgabe im Dateibereich",
                        dayOffset: 2, start: "12:00", end: "12:30", location: nil),
        DemoAppointment(id: "demo-cal-2", title: "Sprechstunde Prof. Weber",
                        description: "Frage zur Reihenkonvergenz",
                        dayOffset: 4, start: "14:00", end: "14:15", location: "1101 - A410"),
        DemoAppointment(id: "demo-cal-3", title: "Erstsemesterabend der Fachschaft",
                        description: nil,
                        dayOffset: 9, start: "19:00", end: "22:00", location: "Kesselhaus"),
    ]

    // MARK: - Einrichtungen

    static let institute = (id: "demo-fk4",
                            name: "Fakultät für Elektrotechnik und Informatik",
                            street: "Appelstraße 4",
                            city: "30167 Hannover",
                            phone: "+49 511 762-0",
                            url: "https://www.et-inf.uni-hannover.de",
                            type: "Fakultät")

    // MARK: - Dateien

    struct DemoFile {
        let id: String
        let name: String
        let mime: String
        let size: Int
        let dayOffset: Int
    }

    struct DemoFolder {
        let id: String
        let courseID: String
        let parentID: String?
        let name: String
        let description: String?
        let files: [DemoFile]
    }

    static let folders: [DemoFolder] = [
        DemoFolder(id: "demo-f-prog2", courseID: "demo-prog2", parentID: nil,
                   name: "Allgemeiner Dateiordner",
                   description: "<!--HTML--><p>Hier liegen Folien und Übungsblätter.</p>",
                   files: [
                       DemoFile(id: "demo-file-1", name: "Folien 05 — Vererbung.pdf",
                                mime: "application/pdf", size: 482_113, dayOffset: -3),
                       DemoFile(id: "demo-file-2", name: "Modulhandbuch.pdf",
                                mime: "application/pdf", size: 1_204_882, dayOffset: -40),
                   ]),
        DemoFolder(id: "demo-f-prog2-ub", courseID: "demo-prog2", parentID: "demo-f-prog2",
                   name: "Übungsblätter", description: nil,
                   files: [
                       DemoFile(id: "demo-file-3", name: "Blatt 04.pdf",
                                mime: "application/pdf", size: 121_004, dayOffset: -6),
                       DemoFile(id: "demo-file-4", name: "Blatt 05.pdf",
                                mime: "application/pdf", size: 118_770, dayOffset: -1),
                   ]),
        DemoFolder(id: "demo-f-analysis", courseID: "demo-analysis", parentID: nil,
                   name: "Allgemeiner Dateiordner", description: nil,
                   files: [
                       DemoFile(id: "demo-file-5", name: "Skript Kapitel 1-3.pdf",
                                mime: "application/pdf", size: 2_931_004, dayOffset: -30),
                   ]),
        DemoFolder(id: "demo-f-dbs", courseID: "demo-dbs", parentID: nil,
                   name: "Allgemeiner Dateiordner", description: nil,
                   files: [
                       DemoFile(id: "demo-file-6", name: "Beispieldatenbank.pdf",
                                mime: "application/pdf", size: 88_120, dayOffset: -12),
                   ]),
        DemoFolder(id: "demo-f-ethik", courseID: "demo-ethik", parentID: nil,
                   name: "Allgemeiner Dateiordner", description: nil, files: []),
        DemoFolder(id: "demo-f-lerngruppe", courseID: "demo-lerngruppe", parentID: nil,
                   name: "Allgemeiner Dateiordner", description: nil, files: []),
    ]

    // MARK: - Nachrichten

    struct DemoMessage {
        let id: String
        let subject: String
        let body: String
        let senderID: String
        let recipientIDs: [String]
        let hoursAgo: Int
        let isRead: Bool
        let outgoing: Bool
    }

    static let messages: [DemoMessage] = [
        DemoMessage(id: "demo-msg-1", subject: "Übungsblatt 5 ist online",
                    body: """
                    Hallo zusammen,

                    das fünfte Übungsblatt liegt ab sofort im Dateibereich. \
                    Abgabe ist **Freitag, 12:00 Uhr**.

                    Viele Grüße
                    Marek
                    """,
                    senderID: "demo-sobczak", recipientIDs: [userID],
                    hoursAgo: 5, isRead: false, outgoing: false),
        DemoMessage(id: "demo-msg-2", subject: "Sprechstunde am Donnerstag",
                    body: """
                    Guten Tag Frau/Herr Muster,

                    Ihren Termin am Donnerstag um 14:00 Uhr habe ich notiert. \
                    Bringen Sie gern Ihre Rechnung zu Aufgabe 3 mit.

                    Mit freundlichen Grüßen
                    J. Weber
                    """,
                    senderID: "demo-weber", recipientIDs: [userID],
                    hoursAgo: 26, isRead: false, outgoing: false),
        DemoMessage(id: "demo-msg-3", subject: "Rückmeldung zum Sommersemester",
                    body: """
                    Die Rückmeldefrist läuft noch bis zum Ende des Monats. \
                    Der Semesterbeitrag ist bereits eingegangen — es ist nichts \
                    weiter zu tun.
                    """,
                    senderID: "demo-studienbuero", recipientIDs: [userID],
                    hoursAgo: 72, isRead: true, outgoing: false),
        DemoMessage(id: "demo-msg-4", subject: "Lerngruppe am Freitag?",
                    body: "Treffen wir uns wie immer um 14 Uhr in der Bibliothek?",
                    senderID: "demo-behrens", recipientIDs: [userID],
                    hoursAgo: 96, isRead: true, outgoing: false),
        DemoMessage(id: "demo-msg-5", subject: "Re: Lerngruppe am Freitag?",
                    body: "Ja, ich bin dabei. Ich bringe Blatt 4 mit.",
                    senderID: userID, recipientIDs: ["demo-behrens"],
                    hoursAgo: 94, isRead: true, outgoing: true),
        DemoMessage(id: "demo-msg-6", subject: "Frage zu Aufgabe 3",
                    body: "Guten Tag, ich komme bei Aufgabe 3b nicht weiter — darf ich in die Sprechstunde kommen?",
                    senderID: userID, recipientIDs: ["demo-weber"],
                    hoursAgo: 30, isRead: true, outgoing: true),
    ]

    // MARK: - Ankündigungen

    struct DemoNews {
        let id: String
        let title: String
        let content: String
        let authorID: String
        let daysAgo: Int
        /// `nil` = universitätsweit.
        let courseID: String?
    }

    static let news: [DemoNews] = [
        DemoNews(id: "demo-news-1", title: "Klausurtermin steht fest",
                 content: """
                 Die Klausur zu **Programmieren 2** findet am Ende der \
                 Vorlesungszeit statt. Die Anmeldung läuft über QIS.

                 - Dauer: 90 Minuten
                 - Hilfsmittel: keine
                 """,
                 authorID: "demo-weber", daysAgo: 1, courseID: "demo-prog2"),
        DemoNews(id: "demo-news-2", title: "Übung fällt einmalig aus",
                 content: "Die Übung nächste Woche entfällt wegen einer Tagung. Der Termin wird nachgeholt.",
                 authorID: "demo-sobczak", daysAgo: 3, courseID: "demo-analysis"),
        DemoNews(id: "demo-news-3", title: "Wiki zur Veranstaltung angelegt",
                 content: "Im Wiki sammeln wir gemeinsam die Beispielabfragen. Beiträge sind willkommen.",
                 authorID: "demo-okonkwo", daysAgo: 6, courseID: "demo-dbs"),
        DemoNews(id: "demo-news-4", title: "Bibliothek mit verlängerten Öffnungszeiten",
                 content: "Während der Prüfungsphase öffnet die TIB werktags bereits ab 7:30 Uhr.",
                 authorID: "demo-studienbuero", daysAgo: 2, courseID: nil),
        DemoNews(id: "demo-news-5", title: "Wartungsarbeiten am Wochenende",
                 content: "Am Sonntag steht das System zwischen 8 und 12 Uhr nicht zur Verfügung.",
                 authorID: "demo-studienbuero", daysAgo: 8, courseID: nil),
    ]

    // MARK: - Aktivitäten

    struct DemoActivity {
        let id: String
        let title: String
        let content: String
        let verb: String
        let type: String
        let hoursAgo: Int
        let actorID: String
        let courseID: String
        let objectType: String
        let objectID: String
    }

    static let activities: [DemoActivity] = [
        DemoActivity(id: "demo-act-1",
                     title: "Marek Sobczak hat die Datei **Blatt 05.pdf** hochgeladen",
                     content: "Übungsblätter", verb: "created", type: "documents",
                     hoursAgo: 4, actorID: "demo-sobczak", courseID: "demo-prog2",
                     objectType: "file-refs", objectID: "demo-file-4"),
        DemoActivity(id: "demo-act-2",
                     title: "Prof. Dr. Julia Weber hat eine Ankündigung geschrieben",
                     content: "Klausurtermin steht fest", verb: "created", type: "news",
                     hoursAgo: 26, actorID: "demo-weber", courseID: "demo-prog2",
                     objectType: "news", objectID: "demo-news-1"),
        DemoActivity(id: "demo-act-3",
                     title: "Lena Behrens hat im Forum geantwortet",
                     content: "Ich habe bei 3b denselben Fehler bekommen …",
                     verb: "created", type: "forum",
                     hoursAgo: 30, actorID: "demo-behrens", courseID: "demo-prog2",
                     objectType: "forum-entries", objectID: "demo-forum-3"),
        DemoActivity(id: "demo-act-4",
                     title: "Dr. Chidi Okonkwo hat die Wikiseite **Normalformen** bearbeitet",
                     content: "Dritte Normalform ergänzt", verb: "edited", type: "wiki",
                     hoursAgo: 50, actorID: "demo-okonkwo", courseID: "demo-dbs",
                     objectType: "wiki-pages", objectID: "demo-wiki-2"),
        DemoActivity(id: "demo-act-5",
                     title: "Marek Sobczak hat einen Termin geändert",
                     content: "Übung Analysis",
                     verb: "edited", type: "schedule",
                     hoursAgo: 74, actorID: "demo-sobczak", courseID: "demo-analysis",
                     objectType: "courses", objectID: "demo-analysis"),
        DemoActivity(id: "demo-act-6",
                     title: "Tim Haas ist der Veranstaltung beigetreten",
                     content: "", verb: "created", type: "participants",
                     hoursAgo: 96, actorID: "demo-haas", courseID: "demo-dbs",
                     objectType: "courses", objectID: "demo-dbs"),
    ]

    // MARK: - Blubber

    struct DemoThread {
        let id: String
        let content: String
        let contextType: String
        let contextID: String?
        let name: String?
        let authorID: String
        let hoursAgo: Int
    }

    struct DemoComment {
        let id: String
        let threadID: String
        let authorID: String
        let content: String
        let minutesAgo: Int
    }

    static let threads: [DemoThread] = [
        DemoThread(id: globalThreadID,
                   content: "",
                   contextType: "public", contextID: nil,
                   name: "Alle", authorID: "demo-haas", hoursAgo: 1),
        DemoThread(id: "demo-thread-prog2",
                   content: "Weiß jemand, ob die Abgabe am Freitag verschoben wird? Bei mir läuft der Test nicht durch.",
                   contextType: "course", contextID: "demo-prog2",
                   name: nil, authorID: "demo-haas", hoursAgo: 6),
        DemoThread(id: "demo-thread-lena",
                   content: "",
                   contextType: "private", contextID: nil,
                   name: "Lena Behrens", authorID: "demo-behrens", hoursAgo: 3),
        DemoThread(id: "demo-thread-lerngruppe",
                   content: "Nächste Woche rechnen wir Blatt 5 — bringt eure Lösungen mit.",
                   contextType: "course", contextID: "demo-lerngruppe",
                   name: nil, authorID: "demo-behrens", hoursAgo: 20),
    ]

    static let comments: [DemoComment] = [
        DemoComment(id: "demo-c-1", threadID: globalThreadID, authorID: "demo-haas",
                    content: "Weiß jemand, ob heute noch ein Platz in der Bibliothek frei ist?",
                    minutesAgo: 90),
        DemoComment(id: "demo-c-2", threadID: globalThreadID, authorID: "demo-behrens",
                    content: "Im dritten Stock war eben noch viel Platz.", minutesAgo: 72),
        DemoComment(id: "demo-c-3", threadID: globalThreadID, authorID: "demo-sobczak",
                    content: "Kleine Erinnerung: Das Tutorium beginnt donnerstags pünktlich um 10:15 Uhr.",
                    minutesAgo: 40),
        DemoComment(id: "demo-c-4", threadID: "demo-thread-prog2", authorID: "demo-behrens",
                    content: "Bei mir lief er erst durch, nachdem ich die Bibliothek neu eingebunden hatte.",
                    minutesAgo: 300),
        DemoComment(id: "demo-c-5", threadID: "demo-thread-prog2", authorID: "demo-sobczak",
                    content: "Die Abgabe bleibt bei Freitag 12:00 Uhr. Wer Probleme hat, meldet sich gern vorher.",
                    minutesAgo: 210),
        DemoComment(id: "demo-c-6", threadID: "demo-thread-lena", authorID: "demo-behrens",
                    content: "Hey! Kommst du morgen mit in die Vorlesung?", minutesAgo: 200),
        DemoComment(id: "demo-c-7", threadID: "demo-thread-lena", authorID: userID,
                    content: "Klar, ich bin um zehn da.", minutesAgo: 185),
        DemoComment(id: "demo-c-8", threadID: "demo-thread-lena", authorID: "demo-behrens",
                    content: "Super, bis morgen!", minutesAgo: 170),
        DemoComment(id: "demo-c-9", threadID: "demo-thread-lerngruppe", authorID: "demo-haas",
                    content: "Ich bringe Kaffee mit.", minutesAgo: 900),
    ]

    // MARK: - Forum

    struct DemoForumCategory {
        let id: String
        let courseID: String
        let title: String
        let position: Int
    }

    struct DemoForumEntry {
        let id: String
        let parentID: String
        let title: String
        let content: String
        let hoursAgo: Int
    }

    static let forumCategories: [DemoForumCategory] = [
        DemoForumCategory(id: "demo-cat-1", courseID: "demo-prog2", title: "Allgemeines", position: 0),
        DemoForumCategory(id: "demo-cat-2", courseID: "demo-prog2", title: "Übungsblätter", position: 1),
        DemoForumCategory(id: "demo-cat-3", courseID: "demo-dbs", title: "Fragen zur Vorlesung", position: 0),
    ]

    static let forumEntries: [DemoForumEntry] = [
        DemoForumEntry(id: "demo-forum-1", parentID: "demo-cat-1",
                       title: "Willkommen im Forum",
                       content: "Hier können Fragen zur Veranstaltung gestellt werden. Bitte vorher schauen, ob es die Frage schon gibt.",
                       hoursAgo: 400),
        DemoForumEntry(id: "demo-forum-2", parentID: "demo-cat-2",
                       title: "Aufgabe 3b — Verständnisfrage",
                       content: "Ist mit „stabil sortieren\" gemeint, dass gleiche Schlüssel ihre Reihenfolge behalten?",
                       hoursAgo: 34),
        DemoForumEntry(id: "demo-forum-3", parentID: "demo-forum-2",
                       title: "Re: Aufgabe 3b — Verständnisfrage",
                       content: "Ich habe bei 3b denselben Fehler bekommen — es lag an der Vergleichsfunktion.",
                       hoursAgo: 30),
        DemoForumEntry(id: "demo-forum-4", parentID: "demo-forum-2",
                       title: "Re: Aufgabe 3b — Verständnisfrage",
                       content: "Genau so ist es gemeint. Die Reihenfolge gleicher Schlüssel bleibt erhalten.",
                       hoursAgo: 28),
        DemoForumEntry(id: "demo-forum-5", parentID: "demo-cat-3",
                       title: "Wann kommt die dritte Normalform dran?",
                       content: "Steht das schon fest?",
                       hoursAgo: 60),
    ]

    // MARK: - Wiki

    struct DemoWikiPage {
        let id: String
        let courseID: String
        let name: String
        let content: String
        let daysAgo: Int
        let version: Int
    }

    static let wikiPages: [DemoWikiPage] = [
        DemoWikiPage(id: "demo-wiki-1", courseID: "demo-dbs", name: "WikiWikiWeb",
                     content: """
                     Willkommen im Wiki der Veranstaltung **Datenbanksysteme**.

                     - [[Normalformen]]
                     - Beispielabfragen
                     """,
                     daysAgo: 20, version: 3),
        DemoWikiPage(id: "demo-wiki-2", courseID: "demo-dbs", name: "Normalformen",
                     content: """
                     Die **dritte Normalform** verlangt, dass kein Nichtschlüsselattribut
                     transitiv vom Schlüssel abhängt.

                     - 1NF: atomare Werte
                     - 2NF: volle funktionale Abhängigkeit
                     - 3NF: keine transitiven Abhängigkeiten
                     """,
                     daysAgo: 2, version: 7),
    ]

    // MARK: - Sprechstunden

    struct DemoBlock {
        let id: String
        let ownerID: String
        let dayOffset: Int
        let start: String
        let end: String
        let room: String
        let note: String
    }

    static let consultationBlocks: [DemoBlock] = [
        DemoBlock(id: "demo-block-1", ownerID: "demo-weber", dayOffset: 4,
                  start: "14:00", end: "15:00", room: "1101 - A410",
                  note: "Bitte Rechenweg mitbringen."),
        DemoBlock(id: "demo-block-2", ownerID: "demo-weber", dayOffset: 11,
                  start: "14:00", end: "15:00", room: "1101 - A410", note: ""),
        DemoBlock(id: "demo-block-3", ownerID: "demo-okonkwo", dayOffset: 6,
                  start: "11:00", end: "12:00", room: "3703 - 210", note: ""),
    ]

    // MARK: - Lizenzen

    static let termsOfUse: [(id: String, name: String, description: String, isDefault: Bool)] = [
        ("demo-term-1", "Selbst erstelltes Werk",
         "Ich habe die Datei selbst erstellt und darf sie hier veröffentlichen.", true),
        ("demo-term-2", "Freies Werk",
         "Die Datei steht unter einer freien Lizenz.", false),
    ]
}
