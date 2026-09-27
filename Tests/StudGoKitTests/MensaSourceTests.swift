import Foundation
// HTTPURLResponse sitzt auf Linux in einem eigenen Modul.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import StudGoKit

/// Der Offlineweg des Speiseplans.
///
/// Der Anlass ist ein Widerspruch aus der 1.7.0: Der Stud.IP-Zugriff zeigte
/// ohne Empfang jeden alten Cache-Stand („Ohne Empfang“, siehe README), der
/// Speiseplan dagegen brach mit „nicht geladen“ ab. Hier prüft der Satz,
/// dass derselbe Vertrag jetzt für beide gilt - Transport und Cache sind
/// dafür austauschbar eingesetzt.
@Suite("MensaSource ohne Empfang")
struct MensaSourceTests {

    static let calendar = Calendar.current

    /// Ein Speiseplan-Tag, dessen ISO-Form die Tests kennen.
    static func tag(_ jahr: Int, _ monat: Int, _ tag: Int) -> Date {
        calendar.date(from: DateComponents(year: jahr, month: monat, day: tag))!
    }

    /// Der Schlüssel, unter dem `MensaSource` den Tag führt.
    static func schluessel(fuer id: Int, am tag: Date) -> String {
        "https://openmensa.org/api/v2/canteens/\(id)/days/\(MensaSource.iso(tag))/meals"
    }

    static let plan = Data("""
    [{"id": 1, "name": "Nudelauflauf", "category": "Essen",
       "prices": {"students": 2.30, "employees": 3.80, "pupils": 2.60, "others": 4.60},
       "notes": ["vegetarisch", "Sellerie"]}]
    """.utf8)

    /// Ein Cache im Kleinen - Einträge samt Alter, wie `ResponseCache` sie
    /// führt, nur ohne Platte: Der Satz prüft die Entscheidung, nicht das
    /// Dateisystem.
    final class ProbeCache: @unchecked Sendable {
        var eintraege: [String: (data: Data, age: TimeInterval)] = [:]
    }

    /// Zählt Aufrufe nebenläufig - die Transportclosures laufen außerhalb
    /// des Hauptakors, ein schlichtes `var` wäre dort eine Warnung (im
    /// Swift-6-Modus ein Fehler).
    final class Zaehler: @unchecked Sendable {
        private(set) var stand = 0
        func hoch() { stand += 1 }
    }

    /// Eine Quelle, die nie eine Verbindung bekommt - jede Anfrage scheitert
    /// wie ohne Empfang.
    static func offlineQuelle(cache: ProbeCache) -> MensaSource {
        MensaSource(
            isDemo: false,
            transport: { _ in throw URLError(.notConnectedToInternet) },
            cachedEntry: { key in cache.eintraege[key] },
            persist: { data, key in cache.eintraege[key] = (data, 0) })
    }

    // MARK: - Ohne Empfang

    @Test("Abgelaufener Cache-Stand gilt ohne Verbindung - wie beim Stud.IP-Zugriff")
    func alterStandOhneEmpfang() async throws {
        let cache = ProbeCache()
        cache.eintraege[Self.schluessel(fuer: 6, am: Self.tag(2026, 10, 1))] =
            (Self.plan, ResponseCache.maxAge + 3600)

        let quelle = Self.offlineQuelle(cache: cache)
        let gerichte = try await quelle.meals(of: 6, on: Self.tag(2026, 10, 1))

        #expect(gerichte.count == 1)
        #expect(gerichte.first?.name == "Nudelauflauf")
    }

    @Test("Ohne Cache-Stand bleibt nur die Meldung „offline“")
    func ohneCache() async {
        let quelle = Self.offlineQuelle(cache: ProbeCache())

        do {
            _ = try await quelle.meals(of: 6, on: Self.tag(2026, 10, 1))
            Issue.record("Der Transport scheitert - hier darf nichts herauskommen.")
        } catch let fehler as APIError {
            #expect({ if case .offline = fehler { return true }; return false }())
        } catch {
            Issue.record("Unerwarteter Fehler: \(error)")
        }
    }

    @Test("Ein Serverfehler bleibt ein Fehler - der Plan wäre falsch, nicht alt")
    func serverfehler() async {
        let cache = ProbeCache()
        cache.eintraege[Self.schluessel(fuer: 6, am: Self.tag(2026, 10, 1))] =
            (Self.plan, ResponseCache.maxAge + 3600)

        let adresse = URL(string: "https://openmensa.org/api/v2/canteens/6/days/2026-10-01/meals")!
        let antwort = HTTPURLResponse(url: adresse, statusCode: 500,
                                      httpVersion: nil, headerFields: nil)!
        let quelle = MensaSource(
            isDemo: false,
            transport: { _ in (Data("[]".utf8), antwort) },
            cachedEntry: { key in cache.eintraege[key] },
            persist: { _, _ in })

        do {
            _ = try await quelle.meals(of: 6, on: Self.tag(2026, 10, 1))
            Issue.record("500 darf nicht durchgehen.")
        } catch let fehler as APIError {
            #expect({ if case .http(500, _) = fehler { return true }; return false }())
        } catch {
            Issue.record("Unerwarteter Fehler: \(error)")
        }
    }

    // MARK: - Mit Empfang

    @Test("Frischer Cache-Stand fragt nicht nach")
    func frischerCache() async throws {
        let cache = ProbeCache()
        cache.eintraege[Self.schluessel(fuer: 6, am: Self.tag(2026, 10, 1))] =
            (Self.plan, 0)

        let angefragt = Zaehler()
        let quelle = MensaSource(
            isDemo: false,
            transport: { _ in
                angefragt.hoch()
                throw URLError(.notConnectedToInternet)
            },
            cachedEntry: { key in cache.eintraege[key] },
            persist: { _, _ in })

        let gerichte = try await quelle.meals(of: 6, on: Self.tag(2026, 10, 1))
        #expect(gerichte.count == 1)
        #expect(angefragt.stand == 0)
    }

    @Test("Eine neue Antwort landet im Cache und gilt beim zweiten Mal")
    func antwortWirdBehalten() async throws {
        let cache = ProbeCache()
        let adresse = URL(string: "https://openmensa.org/api/v2/canteens/6/days/2026-10-01/meals")!
        let antwort = HTTPURLResponse(url: adresse, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!
        let lieferungen = Zaehler()
        let quelle = MensaSource(
            isDemo: false,
            transport: { _ in
                lieferungen.hoch()
                return (Self.plan, antwort)
            },
            cachedEntry: { key in cache.eintraege[key] },
            persist: { data, key in cache.eintraege[key] = (data, 0) })

        _ = try await quelle.meals(of: 6, on: Self.tag(2026, 10, 1))
        _ = try await quelle.meals(of: 6, on: Self.tag(2026, 10, 1))
        #expect(lieferungen.stand == 1)
    }

    // MARK: - Details der Gerichte

    @Test("Alle Preigruppen, nicht nur der Studierendenpreis")
    func preigruppen() throws {
        let gericht = try JSONDecoder().decode([MensaMeal].self, from: Self.plan).first!

        #expect(gericht.priceRows.count == 4)
        #expect(gericht.priceRows.first?.label == "Studierende")
        #expect(gericht.priceRows.first?.price == 2.30)
        #expect(gericht.isVegetarian)
        #expect(!gericht.isVegan)
        #expect(gericht.additives == ["Sellerie"])
    }
}
