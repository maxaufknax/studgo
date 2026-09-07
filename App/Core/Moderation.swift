import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Warum gemeldet wird

/// Der Grund, den beim Melden jemand angibt.
///
/// Die Liste ist bewusst kurz. Wer melden will, ist meist verärgert und soll
/// nicht erst eine Taxonomie lesen; alles Feinere gehört in die freie
/// Anmerkung.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case abuse
    case harassment
    case sexual
    case violence
    case spam
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .abuse: return "Beleidigung oder Hassrede"
        case .harassment: return "Belästigung oder Mobbing"
        case .sexual: return "Sexueller Inhalt"
        case .violence: return "Gewalt oder Bedrohung"
        case .spam: return "Spam oder Werbung"
        case .other: return "Etwas anderes"
        }
    }

    var hint: String {
        switch self {
        case .abuse: return "Herabwürdigend, diskriminierend, verletzend"
        case .harassment: return "Gezielt gegen eine Person gerichtet"
        case .sexual: return "Sexuell explizit oder anzüglich"
        case .violence: return "Droht Gewalt an oder verherrlicht sie"
        case .spam: return "Werbung, Betrug, Kettenbriefe"
        case .other: return "Passt in keine der Kategorien"
        }
    }
}

/// Woher der gemeldete Inhalt stammt.
///
/// Steht in der Meldung, damit beim Nachsehen klar ist, **wo** in Stud.IP der
/// Beitrag liegt — die IDs allein sagen das nicht.
enum ReportTargetKind: String, Codable, Sendable {
    case blubberComment
    case blubberThread
    case message
    case forumEntry
    case news
    case activity
    case wikiPage
    case person

    var label: String {
        switch self {
        case .blubberComment: return "Blubber-Beitrag"
        case .blubberThread: return "Blubber-Faden"
        case .message: return "Nachricht"
        case .forumEntry: return "Forenbeitrag"
        case .news: return "Ankündigung"
        case .activity: return "Aktivität"
        case .wikiPage: return "Wikiseite"
        case .person: return "Profil"
        }
    }
}

// MARK: - Die Meldung selbst

/// Eine Meldung oder Blockierung, so wie sie beim Entwickler ankommt.
///
/// **Warum eine Blockierung dasselbe Format hat:** Die App-Store-Richtlinie
/// 1.2 verlangt, dass eine Blockierung den Entwickler ebenfalls über den
/// Inhalt in Kenntnis setzt. Beides ist also derselbe Vorgang mit
/// unterschiedlichem `kind` — ein Weg, ein Format, eine Ablage.
struct ModerationReport: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case report
        case block
    }

    /// Wie lang ein mitgeschickter Auszug höchstens sein darf.
    ///
    /// Genug, um den Beitrag wiederzuerkennen, und wenig genug, dass keine
    /// halbe Unterhaltung Dritter auf dem Server landet.
    static let excerptLimit = 500

    let kind: Kind
    let reason: ReportReason.RawValue
    let targetKind: ReportTargetKind
    let targetID: String
    let authorID: String?
    let authorName: String?
    let excerpt: String
    let note: String?
    let appVersion: String
    let reportedAt: Date

    init(kind: Kind,
         reason: ReportReason,
         targetKind: ReportTargetKind,
         targetID: String,
         authorID: String? = nil,
         authorName: String? = nil,
         excerpt: String = "",
         note: String? = nil,
         appVersion: String,
         reportedAt: Date = Date()) {
        self.kind = kind
        self.reason = reason.rawValue
        self.targetKind = targetKind
        self.targetID = targetID
        self.authorID = authorID?.nilIfEmpty
        self.authorName = authorName?.nilIfEmpty
        self.excerpt = ModerationReport.trim(excerpt)
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.appVersion = appVersion
        self.reportedAt = reportedAt
    }

    /// Kürzt den Auszug auf `excerptLimit`, ohne mitten im Wort zu enden.
    static func trim(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > excerptLimit else { return clean }
        let cut = clean.prefix(excerptLimit)
        // Bis zum letzten Leerzeichen zurück, damit der Auszug an einer
        // Wortgrenze endet — sonst steht am Ende ein Wortfragment, das im
        // Zweifel etwas anderes bedeutet als das ganze Wort.
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > excerptLimit / 2 {
            return cut[..<space] + " …"
        }
        return cut + "…"
    }

    var reasonLabel: String {
        ReportReason(rawValue: reason)?.label ?? reason
    }

    /// JSON für den Endpunkt. Datum als ISO 8601 — der Server schreibt es
    /// unverändert in seine Ablage.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Rückfallebene E-Mail

    var mailSubject: String {
        let prefix = kind == .block ? "Blockierung" : "Meldung"
        return "StudGo-\(prefix): \(targetKind.label) (\(reasonLabel))"
    }

    /// Der Text der Rückfall-E-Mail.
    ///
    /// Absichtlich dieselben Felder wie im JSON und in derselben Reihenfolge:
    /// Wer beides nebeneinander sieht, muss nicht übersetzen.
    var mailBody: String {
        var lines = [
            "Art: \(kind == .block ? "Blockierung" : "Meldung")",
            "Grund: \(reasonLabel)",
            "Ort: \(targetKind.label)",
            "Kennung: \(targetID)",
        ]
        if let authorName { lines.append("Verfasst von: \(authorName)") }
        if let authorID { lines.append("Kennung der Person: \(authorID)") }
        if !excerpt.isEmpty { lines.append("\nAuszug:\n\(excerpt)") }
        if let note { lines.append("\nAnmerkung:\n\(note)") }
        lines.append("\nApp: StudGo \(appVersion)")
        lines.append("Zeitpunkt: \(ISO8601DateFormatter().string(from: reportedAt))")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Filter

/// Erkennt Beiträge, die niemand ungefragt sehen sollte.
///
/// **Wortgrenzen statt Teilzeichenketten** — der ganze Trick steckt darin.
/// Ein Filter, der einfach `contains` fragt, verdeckt „Analysis" wegen der
/// ersten vier Buchstaben und „Sexualpädagogik" sowieso; an einer Universität
/// wären das täglich Fehlalarme. Deshalb wird der Text in Wörter zerlegt und
/// nur ein **ganzes** Wort gilt als Treffer. Mehrwortige Wendungen stehen
/// getrennt in `phrases` und werden auf der normalisierten Fassung gesucht.
struct ContentFilter: Sendable {
    /// Einzelwörter. Kleingeschrieben, ohne Beugung — geprüft wird gegen den
    /// Wortstamm **und** gegen ein paar geläufige Endungen (siehe `matches`).
    static let defaultTerms: Set<String> = [
        // Beleidigungen (deutsch)
        "hurensohn", "wichser", "fotze", "missgeburt", "spast", "spasti",
        "schwuchtel", "vollidiot", "arschloch", "drecksau", "hure", "nutte",
        // Beleidigungen (englisch)
        "fuck", "fucker", "motherfucker", "bitch", "cunt", "whore", "retard",
        "faggot", "nigger",
        // Herabwürdigung von Gruppen
        "untermensch", "volksverräter", "judensau", "kanake", "neger",
        // Drohungen
        "abstechen", "abknallen", "aufschlitzen",
    ]

    /// Wendungen, die erst zusammen etwas bedeuten. Werden auf dem
    /// normalisierten Text (kleingeschrieben, Satzzeichen weg) gesucht.
    static let defaultPhrases: [String] = [
        "bring dich um", "bringt euch um", "geh sterben", "kill yourself",
        "ich töte dich", "ich bringe dich um",
    ]

    let terms: Set<String>
    let phrases: [String]

    init(terms: Set<String> = ContentFilter.defaultTerms,
         phrases: [String] = ContentFilter.defaultPhrases) {
        self.terms = terms
        self.phrases = phrases
    }

    /// Endungen, die an einen Stamm treten dürfen, ohne dass er ein anderes
    /// Wort wird — „wichser" → „wichsern", „hure" → „huren".
    private static let suffixes = ["", "s", "n", "en", "er", "ern", "in", "innen"]

    /// Zerlegt in Wörter: alles, was kein Buchstabe und keine Ziffer ist,
    /// trennt. Umlaute bleiben Buchstaben, Bindestriche trennen.
    static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Enthält der Text etwas, das verdeckt gehören könnte?
    func matches(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let normalized = text.lowercased()
        for phrase in phrases where normalized.contains(phrase) { return true }
        for word in ContentFilter.words(in: text) {
            if terms.contains(word) { return true }
            // Zusammensetzungen und Beugungen: „arschlöcher" fängt der
            // Stammvergleich nicht, „arschlochs" schon.
            for term in terms where word.count > term.count {
                for suffix in ContentFilter.suffixes where !suffix.isEmpty {
                    if word == term + suffix { return true }
                }
            }
        }
        return false
    }
}

// MARK: - Blockliste

/// Wen jemand blockiert hat.
///
/// Reine Mengenlogik, damit sie ohne Speicher und ohne Oberfläche prüfbar
/// bleibt. Wo die Menge liegt, entscheidet `ModerationStore`.
struct Blocklist: Equatable, Sendable {
    private(set) var ids: Set<String>
    /// Nur zur Anzeige: Kennung → zuletzt gesehener Name.
    private(set) var names: [String: String]

    init(ids: Set<String> = [], names: [String: String] = [:]) {
        self.ids = ids
        self.names = names
    }

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func contains(_ id: String?) -> Bool {
        guard let id = id?.nilIfEmpty else { return false }
        return ids.contains(id)
    }

    mutating func block(id: String, name: String?) {
        guard let id = id.nilIfEmpty else { return }
        ids.insert(id)
        if let name = name?.nilIfEmpty { names[id] = name }
    }

    mutating func unblock(id: String) {
        ids.remove(id)
        names.removeValue(forKey: id)
    }

    /// Blockierte, nach Anzeigename sortiert — die Reihenfolge der
    /// Einstellungsliste.
    var entries: [(id: String, name: String)] {
        ids.map { (id: $0, name: names[$0] ?? "Unbekannte Person") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Versand

/// Schickt Meldungen an den Endpunkt des Entwicklers.
///
/// Der Schlüssel im Kopf ist **kein Geheimnis** — er steckt in einer
/// quelloffenen App und hält nur zufälligen Lärm ab. Ernsthaften Missbrauch
/// bremst der Server, nicht die App.
struct ReportSubmitter: Sendable {
    enum Failure: Error, Equatable {
        case network(String)
        case server(Int)
    }

    let endpoint: URL
    let key: String
    let session: URLSession

    init(endpoint: URL = AppConfig.reportEndpoint,
         key: String = AppConfig.reportKey,
         session: URLSession = .shared) {
        self.endpoint = endpoint
        self.key = key
        self.session = session
    }

    func request(for report: ModerationReport) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-StudGo-Key")
        request.httpBody = try report.encoded()
        request.timeoutInterval = 20
        return request
    }

    /// Wirft, wenn die Meldung **nicht** angekommen ist — der Aufrufer
    /// schaltet dann auf die E-Mail-Rückfallebene um.
    func send(_ report: ModerationReport) async throws {
        let request = try self.request(for: report)
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { throw Failure.server(code) }
    }
}
