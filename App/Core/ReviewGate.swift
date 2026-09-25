import Foundation

/// Wann die App um eine App-Store-Bewertung bittet.
///
/// **Die Regel von Apple dazu:** Der Systemdialog darf nicht auf einen Knopf
/// oder in einen Ablauf gezwungen werden, und das System zeigt ihn ohnehin
/// höchstens dreimal im Jahr — ein vierter Aufruf verhallt ungehört. Das
/// Limit istalso nicht „früh und oft fragen", sondern „an einem Moment fragen,
/// in dem die Bewertung gut ausfällt": nach einigen Tagen Nutzung, nicht am
/// ersten Start, und mit Abstand zur letzten Bitte.
///
/// Die Entscheidung steht hier — pur und ohne StoreKit — damit sie auf
/// Linux mitgeprüft wird; das Bitten selbst liegt bei `ReviewPrompt` in den
/// Ansichten.
enum ReviewGate {
    /// Erste Bitte ab diesem Startzähler. Vier Starts heißen: Wer die App
    /// dreimal wieder aufschlägt, benutzt sie wirklich.
    static let firstAsk = 4
    /// So viele Starts zwischen zwei Bitten.
    static let interval = 10
    /// So viele Tage seit dem ersten Start, bevor überhaupt gefragt wird.
    /// Am ersten Tag kennt niemand die App, und eine voreilige Bitte wirkt
    /// wie ein Bettelbrief.
    static let minimumDays = 3

    /// Ob jetzt eine gute Stelle für die Bitte ist.
    ///
    /// - Parameters:
    ///   - launches: Wie oft die App seit dem ersten Start geöffnet wurde.
    ///   - daysSinceFirstLaunch: Tage seit dem ersten Start.
    ///   - lastAskedLaunch: Der Startzähler, bei dem zuletzt gebeten wurde —
    ///     `nil`, wenn noch nie.
    static func shouldAsk(launches: Int,
                          daysSinceFirstLaunch: Int,
                          lastAskedLaunch: Int?) -> Bool {
        guard launches >= firstAsk, daysSinceFirstLaunch >= minimumDays else { return false }
        guard let lastAskedLaunch else { return true }
        return launches - lastAskedLaunch >= interval
    }
}
