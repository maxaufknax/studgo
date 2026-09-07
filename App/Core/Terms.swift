import Foundation

/// Die Nutzungsbedingungen, denen vor der ersten Anmeldung zugestimmt wird.
///
/// **Warum der Text hier steht und nicht in der Ansicht:** Er ist eine Zusage,
/// keine Gestaltung. In der Logikschicht lässt er sich prüfen — `TermsTests`
/// besteht darauf, dass die Sätze über Null Toleranz, das Melden, das
/// Blockieren und die 24 Stunden darin vorkommen. Wer sie herausstreicht,
/// bricht einen Test und nicht bloss ein Versprechen.
///
/// Ändert sich der Text inhaltlich, wird `ModerationStore.termsVersion`
/// hochgezählt; dann wird erneut zugestimmt.
enum Terms {
    /// Kurzfassung für den Anmeldebildschirm — was jemand mindestens gelesen
    /// haben muss, bevor er zustimmt.
    static let summary = """
    StudGo zeigt Inhalte, die andere Menschen geschrieben haben. \
    Für anstößige Inhalte und für Personen, die sich daneben benehmen, \
    gibt es hier keine Toleranz.
    """

    struct Section: Identifiable, Equatable, Sendable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Worum es geht", body: """
        StudGo ist ein privates, quelloffenes Studierendenprojekt und kein \
        Angebot einer Hochschule. Die App zeigt Inhalte aus Stud.IP: \
        Nachrichten, Blubber-Beiträge, Forenbeiträge, Wikiseiten, \
        Ankündigungen und Profile. Diese Inhalte stammen von anderen \
        Angehörigen deiner Hochschule, nicht von uns.
        """),

        Section(title: "Keine Toleranz für anstößige Inhalte", body: """
        Beleidigungen, Hassrede, Diskriminierung, Belästigung, Bedrohungen, \
        sexuell explizite Inhalte und Spam sind in StudGo nicht geduldet — \
        weder in Beiträgen, die du schreibst, noch in solchen, die du \
        weiterträgst. Wer sich so verhält, wird von der Nutzung der App \
        ausgeschlossen.
        """),

        Section(title: "Was du tun kannst", body: """
        Jeder fremde Beitrag lässt sich melden: lange auf ihn tippen und \
        „Beitrag melden“ wählen, oder in der Detailansicht das Menü oben \
        rechts. Personen lassen sich blockieren — ihre Beiträge und \
        Nachrichten verschwinden dann sofort aus deiner Ansicht. Beides \
        findest du auch unter „Melden und Blockieren“ in den Einstellungen. \
        Zusätzlich verdeckt StudGo Beiträge, die auf den eingebauten \
        Wortfilter ansprechen, bis du sie ausdrücklich aufklappst.
        """),

        Section(title: "Was wir tun", body: """
        Jede Meldung erreicht uns unmittelbar. Wir sehen sie uns innerhalb \
        von 24 Stunden an, entfernen gemeldete Inhalte aus der App und \
        schliessen Verfasser aus, die gegen diese Bedingungen verstoßen. \
        Was in Stud.IP selbst passiert, entscheidet deine Hochschule; \
        schwerwiegende Fälle geben wir dorthin weiter.
        """),

        Section(title: "Deine Verantwortung", body: """
        Du bist für das verantwortlich, was du über StudGo schreibst, \
        hochlädst oder versendest, und hältst dich an die Regeln deiner \
        Hochschule. Melde nichts wahrheitswidrig: Wer die Meldefunktion \
        missbraucht, verliert sie.
        """),

        Section(title: "Haftung und Ende", body: """
        StudGo wird ohne Gewähr bereitgestellt; für die Richtigkeit der aus \
        Stud.IP übernommenen Inhalte können wir nicht einstehen. Du kannst \
        die Nutzung jederzeit beenden, indem du dich abmeldest und die App \
        löschst. Wir dürfen dir die Nutzung untersagen, wenn du wiederholt \
        gegen diese Bedingungen verstößt.
        """),

        Section(title: "Kontakt", body: """
        Fragen, Beschwerden und Meldungen: \(AppConfig.moderationMail)
        """),
    ]

    /// Der ganze Text am Stück — für die Weitergabe an den App Store und für
    /// die Prüfungen.
    static var fullText: String {
        sections.map { "\($0.title)\n\n\($0.body)" }.joined(separator: "\n\n")
    }
}
