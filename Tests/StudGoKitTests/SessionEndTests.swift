import Foundation
import Testing
@testable import StudGoKit

/// Was das Ende einer Sitzung auf dem Gerät hinterlassen darf - und was nicht.
///
/// PRIVACY.md („Deine Rechte“) verspricht: Abmelden löscht die Daten des
/// Kontos vollständig. Bis 1.9 stimmte das nur für Tokens und Zwischenspeicher;
/// Blockliste, ausgeblendete Termine und Meldemerker blieben liegen. Diese
/// Suite prüft die reine Seite davon: Schlüssel, Rücksetzung, Downloads. Die
/// Apple-Seite (Keychain, Mitteilungen, Kalender, Widgets) bleibt der Prüfung
/// auf dem Gerät überlassen.
@Suite("Sitzungsende")
@MainActor
struct SessionEndTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "studgo.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// Ein Termin aus der ICS-Presse, wie ihn der echte Kalender liefert.
    private func termin(_ id: String, kurs: String? = nil) -> CourseEvent {
        let event = ICSParser.Event(uid: "Stud.IP-SEM-\(id)", summary: "Übung",
                                    description: nil, location: nil, categories: nil,
                                    start: Date(), end: Date().addingTimeInterval(3600),
                                    isAllDay: false)
        return CourseEvent(ics: event, courseID: kurs)
    }

    @Test("Alle kontogebundenen Schlüssel verschwinden, Anzeige-Einstellungen bleiben")
    func removesAccountKeys() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        // Jeder Schlüssel bekommt einen Wert, wie ihn eine echte Sitzung
        // hinterlassen würde.
        for key in AccountState.accountBoundKeys {
            defaults.set("wert", forKey: key)
        }
        defaults.set("bleibt", forKey: "studgo.theme")
        defaults.set(13, forKey: "studgo.mensa.canteen")

        AccountState.removeFrom(defaults)

        for key in AccountState.accountBoundKeys {
            #expect(defaults.object(forKey: key) == nil, "blieb liegen: \(key)")
        }
        #expect(defaults.object(forKey: "studgo.theme") as? String == "bleibt")
        #expect(defaults.integer(forKey: "studgo.mensa.canteen") == 13)
    }

    @Test("Blockliste und Nutzungsbedingungen gehen, der Wortfilter bleibt")
    func moderationReset() async throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        // Die Blockliste liegt direkt in der Ablage, wie der Speicher sie
        // schreibt - Blockieren über die Schnittstelle des Speichers schickt
        // immer eine Meldung los, das gehört nicht in diesen Test.
        defaults.set(["dozentin"], forKey: AccountState.Key.blockedIDs)
        defaults.set(["dozentin": "Erika Mustermann"], forKey: AccountState.Key.blockedNames)
        let submitter = ReportSubmitter(endpoint: URL(string: "http://127.0.0.1:9/report")!, key: "test")
        let store = ModerationStore(defaults: defaults, submitter: submitter)

        #expect(store.isBlocked("dozentin"))
        store.acceptTerms()
        store.hidesObjectionable = false

        store.resetForSessionEnd()

        #expect(!store.hasAcceptedTerms)
        #expect(!store.isBlocked("dozentin"))
        // Reine Einstellung dieses Geräts - unangetastet.
        #expect(!store.hidesObjectionable)
        // Ein neuer Speicher auf derselben Ablage erbt nichts vom Konto.
        let fresh = ModerationStore(defaults: defaults)
        #expect(!fresh.hasAcceptedTerms)
        #expect(!fresh.isBlocked("dozentin"))
    }

    @Test("Ausgeblendete Termine gehen, die Umschaltung bleibt")
    func hiddenEventsReset() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HiddenEventsStore(defaults: defaults)

        let event = termin("termin1")
        store.hide(event)
        store.showsHiddenEvents = true

        store.resetForSessionEnd()

        #expect(!store.isHidden(event))
        #expect(store.showsHiddenEvents)
        // Ein neuer Speicher auf derselben Ablage sieht nichts mehr.
        #expect(!HiddenEventsStore(defaults: defaults).isHidden(event))
    }

    @Test("Die Benachrichtigung zum Sitzungsende erreicht die lebenden Speicher")
    func notificationResetsStores() async throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let submitter = ReportSubmitter(endpoint: URL(string: "http://127.0.0.1:9/report")!, key: "test")
        let moderation = ModerationStore(defaults: defaults, submitter: submitter)
        let hidden = HiddenEventsStore(defaults: defaults)

        let event = termin("termin1")
        hidden.hide(event)
        moderation.acceptTerms()

        // So ruft es der `AuthStore`: erst die Schlüssel löschen, dann die
        // lebenden Speicher verständigen.
        AccountState.removeFrom(defaults)
        NotificationCenter.default.post(name: AccountState.dataDidReset, object: nil)
        // Der Beobachter springt in eine Aufgabe auf dem Hauptaktor - kurz
        // warten, bis sie gelaufen ist.
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(!hidden.isHidden(event))
        #expect(!moderation.hasAcceptedTerms)
    }

    @Test("Der Downloadordner wird geleert")
    func downloadsCleared() throws {
        let url = try StudIPClient.storeForPreview(Data("%PDF-test".utf8), as: "probeklausur.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))

        StudIPClient.clearDownloads()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
