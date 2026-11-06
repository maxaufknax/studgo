import Foundation

/// „Neu in deinen Kursen“ - die Auswahl, reine Logik ohne Apple-Frameworks.
///
/// **Woher das kommt:** `activityStream` sammelt, was in den belegten
/// Veranstaltungen passiert - neue Dateien, Forenbeiträge, Wikiseiten,
/// Ankündigungen. Genau diese Vier interessieren hier; der Strom enthält
/// auch Termine und Teilnehmende, aber die stehen ohnehin auf „Heute“.
///
/// **Dieselbe Auswahl an zwei Stellen:** Der Bereich auf „Heute“ zeigt sie
/// beim Öffnen der App - das ist der verlässliche Teil, weil ein iOS-
/// Hintergrundlauf nie garantiert ist. Der Hintergrundlauf kann daraus
/// zusätzlich eine Mitteilung machen (standardmäßig aus). Beide laufen über
/// diese Funktionen, damit sie dasselbe darunter verstehen.
enum CourseNews {

    /// Die Aktivitätsarten, die „Neu in deinen Kursen“ meint - abgeleitet
    /// aus dem Provider-Klassennamen von Stud.IP (`activity-type`).
    static let interestingTypes: Set<String> = ["documents", "forum", "wiki", "news"]

    /// Die Arten, die eine Mitteilung im Hintergrund rechtfertigen - dieselben
    /// wie in der Ansicht: Wer die Ansicht stummschaltet, meint die Mitteilung.
    static let alertingTypes: Set<String> = interestingTypes

    /// Wie weit der Bereich auf „Heute“ zurückblickt, wenn noch kein Besuch
    /// vermerkt ist (erste Nutzung, nach Abmelden und neuem Anmelden). Ein Tag
    /// ist genug, um den Abschnitt zu füllen, und wenig genug, um nicht alles
    /// Geschehene als neu zu verkaufen.
    static var fallbackHorizon: TimeInterval { 24 * 3600 }

    /// Wählt aus dem Strom aus, was seit `since` Neues in den Kursen ist -
    /// nur die fraglichen Arten, nur Einträge mit Zeitstempel danach,
    /// jüngste zuerst.
    static func fresh(_ items: [ActivityItem], since: Date, limit: Int = 8) -> [ActivityItem] {
        Array(items
            .filter { alertingTypes.contains($0.activityType ?? "") }
            .filter { ($0.createdAt ?? .distantPast) > since }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(limit))
    }

    /// Wirft Einträge aus gemessenen Veranstaltungen heraus - die
    /// Stummschaltung pro Kurs.
    ///
    /// Einträge ohne Kursbezug (die gibt es im Strom) bleiben: Sie zu
    /// verwerfen hätte dasselbe geleistet wie ein Missverständnis dessen,
    /// was „stumm“ verspricht.
    static func unmuted(_ items: [ActivityItem], muted: Set<String>) -> [ActivityItem] {
        items.filter { item in
            guard let courseID = item.courseID else { return true }
            return !muted.contains(courseID)
        }
    }

    /// Der Text der Sammelmitteilung im Hintergrundlauf.
    ///
    /// **Eine Mitteilung statt zwanzig** (Muster `maxAlerts`, nur radikaler):
    /// Der Strom fasst ohnehin zusammen; wer über Nacht fünf Dateien bekommt,
    /// will eine Zeile am Sperrbildschirm, keine Liste. Der Titel nennt die
    /// Zahl, der Rumpf die ersten drei Sätze - mehr passt ohnehin nicht in
    /// eine Mitteilung.
    ///
    /// `nil` heißt: nichts zu melden.
    static func summary(for fresh: [ActivityItem]) -> (title: String, body: String)? {
        guard !fresh.isEmpty else { return nil }
        let title = fresh.count == 1
            ? String(localized: "Neu in deinen Kursen")
            : String(localized: "\(fresh.count) Neuigkeiten in deinen Kursen")
        let sentences = fresh.prefix(3).map { $0.title }
        let body = sentences.joined(separator: "\n")
        return (title, body)
    }
}
