import Foundation

/// Führt die Terminquellen von Stud.IP zusammen.
///
/// `/v1/users/{id}/events` liefert **nur den persönlichen Kalender**: die Route
/// filtert auf `range_id = user`, Veranstaltungstermine hängen dagegen am Kurs.
/// Wer sich allein darauf verlässt, zeigt Studierenden einen leeren Kalender,
/// obwohl ihr Stundenplan voll ist. Die Sitzungen der belegten Veranstaltungen
/// werden deshalb aus den Turnusterminen des Stundenplans abgeleitet.
enum EventMerge {

    /// Ein Stundenplan zusammen mit der Vorlesungszeit, für die er gilt.
    ///
    /// **Warum die Zeit mitgeführt wird:** `/v1/users/{id}/schedule` gibt
    /// immer den Plan *eines* Semesters — welches, entscheidet
    /// `filter[timestamp]`. Würde man den Plan des laufenden Semesters über
    /// Tage des nächsten legen, stünden dort Sitzungen, die es nicht gibt.
    /// Seit der Kalender in der vorlesungsfreien Zeit vorausschaut, liegen
    /// zwei Pläne gleichzeitig vor, und jeder gilt nur in seinem Fenster.
    struct PlanWindow {
        let entries: [ScheduleEntry]
        let period: ClosedRange<Date>?

        init(entries: [ScheduleEntry], period: ClosedRange<Date>?) {
            self.entries = entries
            self.period = period
        }

        /// Bequemer Weg für den Regelfall: der Plan des Semesters, in dessen
        /// Vorlesungszeit `reference` liegt.
        init(entries: [ScheduleEntry], semester: Semester?) {
            self.entries = entries
            self.period = semester.flatMap(SemesterContext.lecturePeriod(of:))
        }
    }

    /// Persönliche Termine und abgeleitete Sitzungen, nach Zeit sortiert.
    ///
    /// **Zwei Sorten doppel, die es zu vermeiden gilt** — beide aus der
    /// Rückmeldung zur Fassung 1.6.1:
    ///
    /// * **Dasselbe Ereignis zweimal in `dated`.** Der ICS-Strom ruft
    ///   `exportCalendarDates()` *und* `exportCourseDates()` auf. Wer eine
    ///   Veranstaltung in den persönlichen Kalender übernommen hat (Stud.IP
    ///   bietet das an), erhält dieselbe Sitzung dort **zweimal**: einmal als
    ///   Kalenderkopie, einmal als Veranstaltungstermin. Zwei Schlüssel mit
    ///   derselben Kennung, aber ohne Deduplizierung innerhalb `dated`
    ///   standen beide im Kalender.
    /// * **Ein echter Termin neben seiner Ableitung.** Bis hier stand der
    ///   Abgleich auf dem Slot allein: Eine abgeleitete Sitzung fiel weg,
    ///   sobald **irgendein** datierter Termin den Slot belegte. Zwei
    ///   *verschiedene* Veranstaltungen zur selben Stunde — Vorlesung und
    ///   Übung im Block — blendete das stillschweigend die eine aus.
    ///
    /// Der Abgleich führt deshalb **Slot und Zugehörigkeit** zusammen: dieselbe
    /// Veranstaltung (oder derselbe Wortlaut) im selben Slot ist ein Termin,
    /// verschiedene Veranstaltungen im selben Slot sind zwei.
    ///
    /// **Warum erst in Slots vorsortiert wird:** Der Vergleich selbst ist
    /// teuer (Titel normalisieren, Wortfolgen prüfen). Über die volle
    /// Terminliste paarweise gegerechnet — und `combine` läuft dreimal je
    /// Bildschirmaufbau direkt auf dem Hauptthread — blockierte das die App
    /// beim Start so lange, dass iOS sie über den Wachhund abschoss
    /// (Testflug-Bericht zu 1.7.0: „lädt nichts, stürzt ab"). Termine mit
    /// verschiedenem Slot können ohnehin nie dasselbe Ereignis sein; der
    /// Blick in den Slot-Eimer genügt.
    static func combine(dated: [CourseEvent],
                        plans: [PlanWindow],
                        from start: Date = Date(),
                        days: Int) -> [CourseEvent] {
        var merged: [CourseEvent] = []
        var buckets: [String: [CourseEvent]] = [:]

        func admit(_ event: CourseEvent) {
            let key = slot(event)
            if let sameSlot = buckets[key],
               sameSlot.contains(where: { isSameEvent($0, event) }) { return }
            buckets[key, default: []].append(event)
            merged.append(event)
        }

        for event in dated { admit(event) }

        for plan in plans {
            for session in plannedSessions(from: plan.entries,
                                           startingAt: start,
                                           days: days,
                                           within: plan.period) {
                admit(session)
            }
        }
        return merged.sorted { $0.start < $1.start }
    }

    /// Zwei Darstellungen desselben Termins: gleicher Tag, gleiche
    /// Startminute — und entweder dieselbe Veranstaltung oder derselbe Wortlaut.
    static func isSameEvent(_ a: CourseEvent, _ b: CourseEvent) -> Bool {
        guard slot(a) == slot(b) else { return false }

        if let courseA = a.courseID, let courseB = b.courseID {
            return courseA == courseB
        }
        // Titel-Wortfolge gegen Titel-Wortfolge. Nötig, weil die Quellen
        // denselben Kurs verschieden vollständig nennen: Der ICS-Strom
        // schreibt `Course::getFullName()` („11568  Übung: Logik …"), der
        // Stundenplan nur den Kurstitel. Wortweise statt zeichenweise, damit
        // „Analysis I" nicht in „Analysis II" gefunden wird.
        let wordsA = titleWords(a.title)
        let wordsB = titleWords(b.title)
        guard !wordsA.isEmpty else { return false }
        return wordsA == wordsB || containsWords(wordsA, in: wordsB)
            || containsWords(wordsB, in: wordsA)
    }

    /// Titel in vergleichbare Wörter — Groß-/Kleinschreibung und
    /// Satzzeichen fallen weg, Diakritika werden abgebaut.
    static func titleWords(_ raw: String) -> [String] {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Ob `short` als zusammenhängende Wortfolge in `long` steckt.
    private static func containsWords(_ short: [String], in long: [String]) -> Bool {
        guard short.count >= 2, short.count < long.count else { return false }
        for offset in 0...long.count - short.count {
            let window = long[offset..<(offset + short.count)]
            if window.elementsEqual(short) { return true }
        }
        return false
    }

    /// Erkennt den Slot eines Termins an Tag und Startminute.
    static func slot(_ event: CourseEvent) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: event.start)
        let minutes = calendar.component(.hour, from: event.start) * 60
            + calendar.component(.minute, from: event.start)
        return "\(Int(day.timeIntervalSince1970))/\(minutes)"
    }

    /// Die Sitzungen aus einem Wochenplan, Tag für Tag ausgerollt.
    ///
    /// **Zwei Sorten Eintrag, zwei Regeln.** `/v1/users/{id}/schedule` mischt
    /// beides in eine Liste:
    ///
    /// * **Turnustermine von Veranstaltungen** (`seminar-cycle-dates`). Sie
    ///   gelten nur während der **Vorlesungszeit**; ohne bekanntes Fenster
    ///   wird bewusst nichts abgeleitet — lieber eine Quelle weniger als
    ///   erfundene Termine.
    /// * **Selbst angelegte Termine** (`schedule-entries`) — das Tutorium,
    ///   die AG, der Sport am Donnerstag. Die gelten **das ganze Jahr**:
    ///   `ScheduleEntry::findByUser_id()` läuft serverseitig ohne
    ///   Semesterfilter, und in der Weboberfläche stehen sie auch in den
    ///   Semesterferien im Stundenplan.
    ///
    /// Bis 1.3.0 galt für beide dieselbe Regel, und die Folge war der Befund
    /// aus dem Testflug: Zwei eigene Termine standen im **Wochenraster** (das
    /// zeigt die Einträge unmittelbar), in der **Tagesansicht** dagegen nicht
    /// — die leitet aus denselben Einträgen datierte Sitzungen ab und warf
    /// sie mit der vorlesungsfreien Zeit gleich wieder weg.
    static func plannedSessions(from entries: [ScheduleEntry],
                                startingAt start: Date = Date(),
                                days: Int,
                                within period: ClosedRange<Date>?) -> [CourseEvent] {
        guard days > 0 else { return [] }

        let cycles = entries.filter(\.isCourse)
        let personal = entries.filter { !$0.isCourse }
        guard !cycles.isEmpty || !personal.isEmpty else { return [] }

        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)

        return (0..<days).flatMap { offset -> [CourseEvent] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return [] }
            let weekday = Weekday.of(day)
            let inLecturePeriod = period?.contains(day) ?? false

            var matching = personal.filter { $0.normalizedWeekday == weekday }
            if inLecturePeriod {
                matching += cycles.filter { $0.normalizedWeekday == weekday }
            }
            return matching.map { CourseEvent(entry: $0, on: day) }
        }
    }
}
