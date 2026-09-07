import Foundation
import Testing
@testable import StudGoKit

/// Der Wortfilter ist die Stelle, an der ein Fehler doppelt weh tut: Zu
/// grosszügig, und die Richtlinie ist nicht erfüllt; zu streng, und die App
/// verdeckt den halben Vorlesungsplan. Die zweite Hälfte dieser Prüfungen ist
/// deshalb bewusst eine Sammlung harmloser Uni-Wörter.
@Suite("Wortfilter")
struct ContentFilterTests {
    let filter = ContentFilter()

    @Test("Beleidigungen schlagen an")
    func hits() {
        #expect(filter.matches("Du Hurensohn"))
        #expect(filter.matches("was für ein VOLLIDIOT"))
        #expect(filter.matches("fuck this"))
    }

    @Test("Gebeugte Formen schlagen ebenfalls an")
    func inflected() {
        #expect(filter.matches("diese Wichser"))
        #expect(filter.matches("den Wichsern"))
    }

    @Test("Wendungen werden als Ganzes erkannt")
    func phrases() {
        #expect(filter.matches("Geh sterben du Idiot"))
        #expect(filter.matches("KILL YOURSELF"))
        // Die Einzelwörter für sich sind harmlos und dürfen nicht anschlagen.
        #expect(!filter.matches("Bring bitte den Zettel um 14 Uhr vorbei"))
    }

    @Test("Harmlose Uni-Wörter bleiben sichtbar")
    func noFalsePositives() {
        let harmless = [
            "Analysis für Ingenieurinnen und Ingenieure I",
            "Sexualpädagogik im Grundschulunterricht",
            "Klausureinsicht am Donnerstag",
            "Hurenkinder und Schusterjungen im Satzspiegel",
            "Massenspektrometrie",
            "Die Abgabe ist am Freitag",
        ]
        for text in harmless {
            #expect(!filter.matches(text), "fälschlich verdeckt: \(text)")
        }
    }

    @Test("Leerer Text ist kein Treffer")
    func empty() {
        #expect(!filter.matches(""))
    }
}

@Suite("Blockliste")
struct BlocklistTests {
    @Test("Blockieren, prüfen, aufheben")
    func lifecycle() {
        var list = Blocklist()
        #expect(list.isEmpty)
        list.block(id: "u1", name: "Alex Muster")
        #expect(list.contains("u1"))
        #expect(!list.contains("u2"))
        #expect(list.count == 1)
        list.unblock(id: "u1")
        #expect(list.isEmpty)
    }

    @Test("Leere Kennungen werden nicht aufgenommen")
    func ignoresEmpty() {
        var list = Blocklist()
        list.block(id: "   ", name: "Niemand")
        #expect(list.isEmpty)
        #expect(!list.contains(nil))
        #expect(!list.contains(""))
    }

    @Test("Einträge stehen nach Namen sortiert")
    func sorted() {
        var list = Blocklist()
        list.block(id: "b", name: "Zoe Zander")
        list.block(id: "a", name: "Anna Albers")
        #expect(list.entries.map(\.name) == ["Anna Albers", "Zoe Zander"])
    }

    @Test("Ohne Namen steht ein Platzhalter")
    func unnamed() {
        var list = Blocklist()
        list.block(id: "x", name: nil)
        #expect(list.entries.first?.name == "Unbekannte Person")
    }
}

@Suite("Meldung")
struct ModerationReportTests {
    private func report(excerpt: String = "Beispiel", note: String? = nil) -> ModerationReport {
        ModerationReport(kind: .report,
                         reason: .abuse,
                         targetKind: .blubberComment,
                         targetID: "c1",
                         authorID: "u9",
                         authorName: "Alex Muster",
                         excerpt: excerpt,
                         note: note,
                         appVersion: "1.5.2 (26)",
                         reportedAt: Date(timeIntervalSince1970: 0))
    }

    @Test("Langer Auszug wird an einer Wortgrenze gekürzt")
    func trimming() {
        let long = String(repeating: "Wort ", count: 400)
        let trimmed = ModerationReport.trim(long)
        #expect(trimmed.count <= ModerationReport.excerptLimit + 2)
        #expect(trimmed.hasSuffix("…"))
        // Kein abgeschnittenes Wortfragment vor dem Auslassungszeichen.
        #expect(!trimmed.contains("Wor …"))
    }

    @Test("Kurzer Auszug bleibt unangetastet")
    func shortExcerptSurvives() {
        #expect(ModerationReport.trim("  knapp  ") == "knapp")
    }

    @Test("JSON trägt alle Felder, die der Server braucht")
    func encoding() throws {
        let data = try report(note: "  bitte ansehen  ").encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["kind"] as? String == "report")
        #expect(json["reason"] as? String == "abuse")
        #expect(json["targetKind"] as? String == "blubberComment")
        #expect(json["targetID"] as? String == "c1")
        #expect(json["authorID"] as? String == "u9")
        #expect(json["appVersion"] as? String == "1.5.2 (26)")
        // Anmerkung kommt getrimmt an, nicht mit den Leerzeichen der Eingabe.
        #expect(json["note"] as? String == "bitte ansehen")
        #expect(json["reportedAt"] as? String == "1970-01-01T00:00:00Z")
    }

    @Test("Die Rückfall-E-Mail nennt Grund, Ort und Auszug")
    func mailBody() {
        let body = report().mailBody
        #expect(body.contains("Beleidigung oder Hassrede"))
        #expect(body.contains("Blubber-Beitrag"))
        #expect(body.contains("Alex Muster"))
        #expect(body.contains("StudGo 1.5.2 (26)"))
    }

    @Test("Blockierung heisst in der Betreffzeile auch so")
    func blockSubject() {
        let block = ModerationReport(kind: .block, reason: .harassment, targetKind: .person,
                                     targetID: "u9", appVersion: "1.5.2 (26)")
        #expect(block.mailSubject.contains("Blockierung"))
        #expect(block.mailSubject.contains("Belästigung"))
    }

    @Test("Der Versand trägt Schlüssel und JSON im Kopf")
    func requestShape() throws {
        let submitter = ReportSubmitter(endpoint: URL(string: "https://example.invalid/report")!, key: "k")
        let request = try submitter.request(for: report())
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-StudGo-Key") == "k")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody != nil)
    }
}

/// Die Prüfungen des Speichers laufen gegen eine eigene `UserDefaults`-Ablage,
/// damit sie nichts hinterlassen. Der Endpunkt zeigt absichtlich ins Leere:
/// Genau dann muss die E-Mail-Rückfallebene greifen.
@Suite("Meldespeicher", .serialized)
@MainActor
struct ModerationStoreTests {
    private func makeStore() -> (ModerationStore, UserDefaults, String) {
        let name = "studgo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let submitter = ReportSubmitter(endpoint: URL(string: "http://127.0.0.1:9/report")!, key: "test")
        return (ModerationStore(defaults: defaults, submitter: submitter), defaults, name)
    }

    @Test("Ohne Zustimmung gilt sie als nicht erteilt, danach hält sie")
    func terms() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!store.hasAcceptedTerms)
        store.acceptTerms()
        #expect(store.hasAcceptedTerms)
        // Ein zweiter Speicher auf derselben Ablage erbt die Zustimmung.
        let again = ModerationStore(defaults: defaults)
        #expect(again.hasAcceptedTerms)
    }

    @Test("Der Filter ist bei der ersten Installation an")
    func filterDefaultsOn() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(store.hidesObjectionable)
        store.hidesObjectionable = false
        #expect(!ModerationStore(defaults: defaults).hidesObjectionable)
    }

    @Test("Blockierte verschwinden sofort, auch ohne Netz")
    func blockingHidesInstantly() async {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let outcome = await store.block(id: "u9", name: "Alex Muster", reason: .harassment)
        // Der Endpunkt ist nicht erreichbar — die Meldung geht per E-Mail raus.
        guard case .needsMail(let url) = outcome else {
            Issue.record("erwartet wurde die E-Mail-Rückfallebene, kam: \(outcome)")
            return
        }
        #expect(url.scheme == "mailto")
        #expect(store.isBlocked("u9"))
        #expect(store.verdict(text: "völlig harmlos", authorID: "u9") == .blocked)
        // Und die Blockierung überlebt den Neustart.
        #expect(ModerationStore(defaults: defaults).isBlocked("u9"))
    }

    @Test("Aufheben gibt die Person wieder frei")
    func unblocking() async {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        _ = await store.block(id: "u9", name: "Alex Muster")
        store.unblock(id: "u9")
        #expect(!store.isBlocked("u9"))
        #expect(store.verdict(text: "harmlos", authorID: "u9") == .visible)
    }

    @Test("Das Urteil unterscheidet blockiert, gefiltert und sichtbar")
    func verdicts() async {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(store.verdict(text: "Klausur am Freitag", authorID: "u1") == .visible)
        #expect(store.verdict(text: "Du Hurensohn", authorID: "u1") == .filtered)
        store.hidesObjectionable = false
        #expect(store.verdict(text: "Du Hurensohn", authorID: "u1") == .visible)
        // Eine Blockierung wiegt schwerer als der abgeschaltete Filter.
        _ = await store.block(id: "u1", name: nil)
        #expect(store.verdict(text: "Klausur am Freitag", authorID: "u1") == .blocked)
    }

    @Test("Die Rückfall-E-Mail führt an die Meldeadresse")
    func mailFallbackAddress() {
        let report = ModerationReport(kind: .report, reason: .spam, targetKind: .message,
                                      targetID: "m1", appVersion: "1.5.2 (26)")
        let url = ModerationStore.mailFallback(for: report)
        #expect(url?.absoluteString.contains(AppConfig.moderationMail) == true)
        #expect(url?.absoluteString.contains("subject=") == true)
    }
}

/// Die Nutzungsbedingungen sind eine Zusage an Apple **und** an die Leute, die
/// die App benutzen. Diese Prüfungen halten fest, dass die vier Sätze, auf die
/// es bei Richtlinie 1.2 ankommt, nicht stillschweigend verschwinden.
@Suite("Nutzungsbedingungen")
struct TermsTests {
    @Test("Der Text sagt Null Toleranz zu")
    func zeroTolerance() {
        let text = Terms.fullText.lowercased()
        #expect(text.contains("keine toleranz") || Terms.summary.lowercased().contains("keine toleranz"))
        #expect(text.contains("ausgeschlossen"))
    }

    @Test("Melden, Blockieren und Filter sind beschrieben")
    func mechanisms() {
        let text = Terms.fullText.lowercased()
        #expect(text.contains("melden"))
        #expect(text.contains("blockieren"))
        #expect(text.contains("wortfilter"))
    }

    @Test("Die Frist von 24 Stunden steht drin")
    func deadline() {
        #expect(Terms.fullText.contains("24 Stunden"))
    }

    @Test("Eine Kontaktadresse steht drin")
    func contact() {
        #expect(Terms.fullText.contains(AppConfig.moderationMail))
    }

    @Test("Jeder Abschnitt hat Überschrift und Inhalt")
    func wellFormed() {
        #expect(Terms.sections.count >= 5)
        for section in Terms.sections {
            #expect(!section.title.isEmpty)
            #expect(section.body.count > 40, "zu dünn: \(section.title)")
        }
    }
}
