import Foundation
import Testing
@testable import StudGoKit

/// Wann die App um eine App-Store-Bewertung bittet.
///
/// Die Entscheidung ist bewusst pur — kein StoreKit, kein UserDefaults —
/// damit sie hier läuft. Das Limit ist nicht „früh und oft", sondern ein
/// Moment, in dem die Bewertung gut ausfällt: nach Tagen Nutzung, mit
/// Abstand zur letzten Bitte. Das System drosselt ohnehin.
@Suite("Bewertungsbitte")
struct ReviewGateTests {

    @Test("Am ersten Start und in den ersten Tagen wird nicht gebeten")
    func zuFrueh() {
        #expect(ReviewGate.shouldAsk(launches: 1, daysSinceFirstLaunch: 0, lastAskedLaunch: nil) == false)
        #expect(ReviewGate.shouldAsk(launches: 2, daysSinceFirstLaunch: 5, lastAskedLaunch: nil) == false)
        #expect(ReviewGate.shouldAsk(launches: 4, daysSinceFirstLaunch: 1, lastAskedLaunch: nil) == false)
    }

    @Test("Nach vier Starts und drei Tagen wird gebeten")
    func reif() {
        #expect(ReviewGate.shouldAsk(launches: 4, daysSinceFirstLaunch: 3, lastAskedLaunch: nil) == true)
        #expect(ReviewGate.shouldAsk(launches: 12, daysSinceFirstLaunch: 40, lastAskedLaunch: nil) == true)
    }

    @Test("Nach der Bitte erst wieder im Abstand")
    func abstand() {
        #expect(ReviewGate.shouldAsk(launches: 5, daysSinceFirstLaunch: 10, lastAskedLaunch: 4) == false)
        #expect(ReviewGate.shouldAsk(launches: 13, daysSinceFirstLaunch: 10, lastAskedLaunch: 4) == false)
        #expect(ReviewGate.shouldAsk(launches: 14, daysSinceFirstLaunch: 10, lastAskedLaunch: 4) == true)
    }
}
