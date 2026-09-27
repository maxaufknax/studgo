import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Modelle

/// Eine Mensa des Studentenwerks. OpenMensa führt sie mit einer festen
/// Kennung je Einrichtung - Hannover trägt die Kennungen 6 bis 17.
struct Canteen: Identifiable, Equatable, Hashable, Codable {
    let id: Int
    let name: String
    let city: String
    let address: String?
}

/// Ein geplanter Tag einer Mensa. `closed` sagt, ob sie An diesem Tag
/// geschlossen hat - OpenMensa plant nur Tage, für die ein Plan vorliegt.
struct CanteenDay: Identifiable, Equatable, Codable {
    let date: String
    let closed: Bool

    var id: String { date }
}

/// Ein Gericht auf dem Speiseplan.
struct MensaMeal: Identifiable, Equatable, Codable {
    let id: Int
    let name: String
    let category: String
    /// Preise je Gruppe. `students` ist der, der auf dem Plan steht.
    let prices: [String: Double?]
    /// Kennzeichnungen: „vegan", „vegetarisch", Allergene, Zusatzstoffe.
    let notes: [String]

    var studentPrice: Double? {
        prices["students"].flatMap { $0 }
    }

    /// Preisspalten von OpenMensa - Kennung → Klartext, wie die Mensa selbst
    /// gruppiert. Das Gericht-Blatt zeigt alle, die Zeile in der Liste nur
    /// den Studierendenpreis.
    private static let priceGroups: [(key: String, label: String)] = [
        ("students", "Studierende"),
        ("employees", "Beschäftigte"),
        ("pupils", "Schüler:innen"),
        ("others", "Gäste"),
    ]

    /// Alle Preise, die der Plan nennt - „Studierende 2,30 €, Gäste 4,10 €".
    var priceRows: [(label: String, price: Double)] {
        Self.priceGroups.compactMap { group in
            prices[group.key].flatMap { $0 }.map { (group.label, $0) }
        }
    }

    var isVegan: Bool { notes.contains("vegan") }
    var isVegetarian: Bool { notes.contains { $0.lowercased().contains("vegetar") } }

    /// Allergene und Zusatzstoffe - alles außer der reinen Ernährungsform.
    var additives: [String] {
        notes.filter { $0.lowercased() != "vegan" && !$0.lowercased().contains("vegetar") }
    }

    /// Der Studierendenpreis als Zeile - „2,00 €".
    var priceLabel: String? {
        studentPrice.map { String(format: "%.2f €", $0) }
    }
}

// MARK: - Die Quelle

/// Speisepläne der Hannoveraner Mensen über [OpenMensa](https://openmensa.org).
///
/// **Warum ein eigener Dienst und nicht Stud.IP:** Die Mensapläne liegen
/// nicht in Stud.IP, und das Studentenwerk veröffentlicht sie selbst nur als
/// Webseite. OpenMensa sammelt die Pläne der deutschen Mensen als offene
/// Daten - ohne Schlüssel, ohne Anmeldung:
/// `GET /api/v2/canteens/{id}/days/{YYYY-MM-DD}/meals` liefert Gerichte,
/// Preise je Gruppe und Kennzeichnungen. Anfragen gehen mit der IP-Adresse
/// des Geräts an `openmensa.org`; weitergegeben wird nichts (siehe
/// PRIVACY.md).
///
/// Im Demo-Modus kommt der Plan aus `DemoData` - dann verlässt nichts das
/// Gerät, auch keine Anfrage an OpenMensa.
struct MensaSource {
    var isDemo = false

    /// Der eigentliche Netzaufruf - als austauschbares Stück, damit sich der
    /// Offlineweg („Verbindung reißt ab, was gilt dann?") ohne Netz prüfen
    /// lässt: `MensaSourceTests` setzt hier eine stets scheiternde Funktion
    /// ein und einen Cache mit abgelaufenem Eintrag.
    var transport: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = Self.perform
    /// Eintrag aus dem Zwischenspeicher, mit Alter. Die Vorgaben greifen auf
    /// denselben `ResponseCache` zu wie der Stud.IP-Zugriff.
    var cachedEntry: @Sendable (String) -> (data: Data, age: TimeInterval)? = ResponseCache.load(for:)
    /// Antwort in den Zwischenspeicher legen.
    var persist: @Sendable (Data, String) -> Void = ResponseCache.store(_:for:)

    private static let root = URL(string: "https://openmensa.org/api/v2")!
    /// Die Hannoveraner Mensen stehen mit dem Namen der Stadt in der Liste;
    /// alles andere dieser einen Hochschule brauchte niemand.
    private static let city = "Hannover"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    // MARK: - Zugriff

    /// Alle Mensen am Hochschulort - sortiert, wie sie im Menü stehen sollen:
    /// die große Hauptmensa zuerst, danach der Rest nach Name.
    func canteens() async throws -> [Canteen] {
        if isDemo { return DemoData.canteens.map(Canteen.init) }
        let all: [Canteen] = try await get("canteens")
        return all
            .filter { $0.city == Self.city }
            .sorted { $0.id < $1.id }
    }

    /// Die geplanten Tage einer Mensa - die nächsten, die OpenMensa kennt.
    func days(of canteenID: Int) async throws -> [CanteenDay] {
        if isDemo {
            return (0..<7).map { offset in
                CanteenDay(date: Self.iso(DemoData.days(offset)),
                           closed: Self.isWeekend(DemoData.days(offset)))
            }
        }
        return try await get("canteens/\(canteenID)/days")
    }

    /// Die Gerichte eines Tages. Ohne Plan antwortet OpenMensa mit 204 -
    /// hier heißt das schlicht: geschlossen oder nichts geplant.
    func meals(of canteenID: Int, on date: Date) async throws -> [MensaMeal] {
        if isDemo { return DemoData.meals(for: date).map(MensaMeal.init) }
        return try await get("canteens/\(canteenID)/days/\(Self.iso(date))/meals")
    }

    // MARK: - Transport

    /// Holt und behält: Frische Antworten landen im `ResponseCache`, und
    /// ohne Netz zählt auch ein älterer Stand - dasselbe Versprechen wie beim
    /// Stud.IP-Zugriff, nur ohne Anmeldung („Ohne Empfang", siehe README).
    ///
    /// **Der Fehler, den es hier nicht mehr gibt:** Bis 1.7.0 warf diese
    /// Stelle bei jedem Verbindungsfehler - der Stud.IP-Zugriff zeigte
    /// unterdessen jeden alten Cache-Stand, der Speiseplan brach ab. Ohne
    /// Empfang stand dann „nicht geladen" statt des Plans von gestern.
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let address = Self.root.appendingPathComponent(path)
        let key = address.absoluteString

        if let hit = cachedEntry(key), hit.age < ResponseCache.maxAge,
           let fresh = try? JSONDecoder().decode(T.self, from: hit.data) {
            return fresh
        }

        var request = URLRequest(url: address)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, http) = try await transport(request)
            // 204: kein Plan für diesen Tag - die leere Liste, kein Fehler.
            guard http.statusCode != 204 else {
                return try JSONDecoder().decode(T.self, from: Data("[]".utf8))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.http(http.statusCode, nil)
            }
            persist(data, key)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Ohne Verbindung zählt jeder gespeicherte Stand, auch ein alter -
            // ein Serverfehler (5xx) dagegen bleibt einer: Der Plan wäre dann
            // womöglich falsch, nicht nur alt.
            guard error.isConnectivityFailure else { throw error }
            if let hit = cachedEntry(key),
               let stale = try? JSONDecoder().decode(T.self, from: hit.data) {
                return stale
            }
            throw APIError.offline
        }
    }

    /// Der Standardtransport: eine Anfrage über die eigene Sitzung.
    private static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Keine HTTP-Antwort")
        }
        return (data, http)
    }

    // MARK: - Datumsformate

    /// `2026-09-28` - OpenMensa fragt Tage in ISO ab.
    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(date)
    }
}

// MARK: - Demo-Brücke

private extension Canteen {
    init(_ canteen: DemoData.DemoCanteen) {
        self.init(id: canteen.id, name: canteen.name, city: "Hannover", address: nil)
    }
}

private extension MensaMeal {
    init(_ meal: DemoData.DemoMeal) {
        self.init(id: meal.id, name: meal.name, category: meal.category,
                  prices: ["students": meal.price], notes: meal.notes)
    }
}
