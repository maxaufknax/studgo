import Foundation
import Observation

/// Was StudGo an Schutz gegen anstößige Inhalte bereithält, an einer Stelle:
/// die zugestimmten Nutzungsbedingungen, der Wortfilter, die Blockliste und
/// der Weg, auf dem eine Meldung beim Entwickler ankommt.
///
/// **Warum das eine Klasse ist und nicht drei:** Die vier Dinge greifen
/// ineinander. Blockieren *ist* eine Meldung (Richtlinie 1.2 verlangt, dass
/// der Entwickler davon erfährt), und ob ein Beitrag verdeckt wird, hängt
/// gleichzeitig an der Blockliste **und** am Filter. Getrennt lägen die
/// Entscheidungen an drei Orten und drifteten auseinander.
///
/// Alles liegt in `UserDefaults`: Es sind Vorlieben eines Geräts, keine
/// Geheimnisse. Die Blockliste bleibt bewusst **lokal** — Stud.IP kennt keine
/// Blockierung, und ein Serverzustand, den nur StudGo pflegt, wäre eine
/// zweite Wahrheit über Menschen, die dort weiter mitlesen dürfen.
@MainActor
@Observable
final class ModerationStore {
    /// Fassung der Nutzungsbedingungen. **Hochzählen, sobald sich der Text
    /// inhaltlich ändert** — dann wird die Zustimmung erneut eingeholt.
    static let termsVersion = 1

    private enum Key {
        static let terms = "studgo.moderation.termsVersion"
        static let blockedIDs = "studgo.moderation.blockedIDs"
        static let blockedNames = "studgo.moderation.blockedNames"
        static let filter = "studgo.moderation.hidesObjectionable"
    }

    /// Wie eine Meldung ausgegangen ist.
    enum Outcome: Equatable {
        /// Beim Entwickler angekommen.
        case sent
        /// Der Endpunkt war nicht erreichbar — die Ansicht öffnet diese
        /// `mailto:`-Adresse, damit die Meldung trotzdem ankommt.
        case needsMail(URL)
        /// Auch die E-Mail liess sich nicht bauen; nur dann meldet die
        /// Oberfläche einen Fehlschlag.
        case failed(String)
    }

    private let defaults: UserDefaults
    private let submitter: ReportSubmitter
    let filter = ContentFilter()

    private(set) var blocklist: Blocklist
    private(set) var acceptedTermsVersion: Int

    /// Verdeckt Beiträge, auf die der Wortfilter anspricht. Vorgabe **an**:
    /// Wer das nicht will, schaltet es in den Einstellungen ab — umgekehrt
    /// hätte niemand den Schutz, der ihn nicht kennt.
    var hidesObjectionable: Bool {
        didSet { defaults.set(hidesObjectionable, forKey: Key.filter) }
    }

    init(defaults: UserDefaults = .standard, submitter: ReportSubmitter = ReportSubmitter()) {
        self.defaults = defaults
        self.submitter = submitter
        let ids = Set(defaults.stringArray(forKey: Key.blockedIDs) ?? [])
        let names = (defaults.dictionary(forKey: Key.blockedNames) as? [String: String]) ?? [:]
        blocklist = Blocklist(ids: ids, names: names)
        acceptedTermsVersion = defaults.integer(forKey: Key.terms)
        // `object(forKey:)` statt `bool(forKey:)`: Letzteres liefert für einen
        // fehlenden Schlüssel `false` — der Filter wäre bei der ersten
        // Installation aus, obwohl er an sein soll.
        hidesObjectionable = defaults.object(forKey: Key.filter) as? Bool ?? true
    }

    // MARK: - Nutzungsbedingungen

    var hasAcceptedTerms: Bool { acceptedTermsVersion >= Self.termsVersion }

    func acceptTerms() {
        acceptedTermsVersion = Self.termsVersion
        defaults.set(acceptedTermsVersion, forKey: Key.terms)
    }

    // MARK: - Blockieren

    func isBlocked(_ id: String?) -> Bool { blocklist.contains(id) }

    /// Blockiert eine Person **und** meldet den Anlass.
    ///
    /// Die Reihenfolge ist Absicht: Erst wird lokal blockiert (damit die
    /// Beiträge sofort verschwinden, auch wenn das Netz gerade weg ist), dann
    /// geht die Meldung raus.
    func block(id: String,
               name: String?,
               reason: ReportReason = .other,
               targetKind: ReportTargetKind = .person,
               targetID: String? = nil,
               excerpt: String = "",
               note: String? = nil) async -> Outcome {
        blocklist.block(id: id, name: name)
        persistBlocklist()
        return await deliver(ModerationReport(
            kind: .block,
            reason: reason,
            targetKind: targetKind,
            targetID: targetID ?? id,
            authorID: id,
            authorName: name,
            excerpt: excerpt,
            note: note,
            appVersion: Self.appVersion))
    }

    func unblock(id: String) {
        blocklist.unblock(id: id)
        persistBlocklist()
    }

    private func persistBlocklist() {
        defaults.set(Array(blocklist.ids), forKey: Key.blockedIDs)
        defaults.set(blocklist.entries.reduce(into: [String: String]()) { $0[$1.id] = $1.name },
                     forKey: Key.blockedNames)
    }

    // MARK: - Melden

    func report(reason: ReportReason,
                targetKind: ReportTargetKind,
                targetID: String,
                authorID: String? = nil,
                authorName: String? = nil,
                excerpt: String = "",
                note: String? = nil) async -> Outcome {
        await deliver(ModerationReport(
            kind: .report,
            reason: reason,
            targetKind: targetKind,
            targetID: targetID,
            authorID: authorID,
            authorName: authorName,
            excerpt: excerpt,
            note: note,
            appVersion: Self.appVersion))
    }

    private func deliver(_ report: ModerationReport) async -> Outcome {
        do {
            try await submitter.send(report)
            return .sent
        } catch {
            guard let url = Self.mailFallback(for: report) else {
                return .failed("Die Meldung liess sich nicht zustellen. Bitte schreib an \(AppConfig.moderationMail).")
            }
            return .needsMail(url)
        }
    }

    /// Baut die `mailto:`-Adresse für die Rückfallebene.
    ///
    /// Reines Foundation, damit sie sich prüfen lässt — geöffnet wird sie erst
    /// in der Ansicht.
    static func mailFallback(for report: ModerationReport) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConfig.moderationMail
        components.queryItems = [
            URLQueryItem(name: "subject", value: report.mailSubject),
            URLQueryItem(name: "body", value: report.mailBody),
        ]
        return components.url
    }

    // MARK: - Verdecken

    /// Soll dieser Beitrag verdeckt werden — und warum?
    ///
    /// Eine Blockierung wiegt schwerer als der Filter: Wer blockiert ist,
    /// verschwindet ganz, auch wenn der Text harmlos ist.
    func verdict(text: String, authorID: String?) -> Verdict {
        if isBlocked(authorID) { return .blocked }
        if hidesObjectionable, filter.matches(text) { return .filtered }
        return .visible
    }

    enum Verdict: Equatable {
        case visible
        /// Verfasser blockiert — der Beitrag wird gar nicht erst gezeigt.
        case blocked
        /// Wortfilter hat angeschlagen — verdeckt, aber aufklappbar.
        case filtered
    }

    /// Fassung der App, wie sie in der Meldung steht.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
