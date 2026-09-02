import Observation
import SwiftUI
import UIKit

/// Farbwelt der App.
///
/// Ein Thema legt drei Dinge fest: die **Akzentfarbe** (Schaltflächen,
/// Auswahl, Tab-Leiste), die **Kurspalette** (aus der jede Veranstaltung ihre
/// dauerhafte eigene Farbe zieht) und die **Kopfzeilen-Verlaufsfarben** der
/// großen Karten. Alles Übrige bleibt bei den Systemfarben — dadurch stimmen
/// Hell- und Dunkelmodus in jedem Thema, ohne dass jede Fläche einzeln
/// gepflegt werden müsste.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case signature
    case ocean
    case forest
    case sunset
    case berry
    case midnight
    case graphite
    case contrast

    var id: String { rawValue }

    var name: String {
        switch self {
        case .signature: return "StudGo Blau"
        case .ocean: return "Ozean"
        case .forest: return "Waldgrün"
        case .sunset: return "Sonnenuntergang"
        case .berry: return "Beere"
        case .midnight: return "Mitternacht"
        case .graphite: return "Graphit"
        case .contrast: return "Hoher Kontrast"
        }
    }

    var blurb: String {
        switch self {
        case .signature: return "Das Blau der Wortmarke"
        case .ocean: return "Türkis und Petrol, ruhig und kühl"
        case .forest: return "Sattes Grün mit warmen Zweitfarben"
        case .sunset: return "Orange, Koralle, Abendrot"
        case .berry: return "Magenta und Violett"
        case .midnight: return "Tiefes Indigo, besonders nachts"
        case .graphite: return "Zurückhaltend, fast einfarbig"
        case .contrast: return "Kräftige Farben, dickere Konturen"
        }
    }

    // MARK: - Akzent

    /// Farbton/Sättigung/Helligkeit der Akzentfarbe, getrennt für hell und dunkel.
    /// Im Dunkelmodus wird jede Akzentfarbe aufgehellt und entsättigt — sonst
    /// wirkt sie auf schwarzem Grund wie ein Loch statt wie eine Farbe.
    private var accentSpec: (hue: Double, light: (Double, Double), dark: (Double, Double)) {
        switch self {
        // 202° ist der Farbton der Wortmarke (#38B6FF). Im Hellmodus
        // abgedunkelt, sonst wäre Text darauf nicht mehr zu lesen.
        case .signature:  return (202, (0.90, 0.66), (0.72, 0.98))
        case .ocean:    return (186, (0.95, 0.58), (0.60, 0.88))
        case .forest:   return (150, (0.85, 0.50), (0.55, 0.80))
        case .sunset:   return (18,  (0.88, 0.85), (0.62, 0.95))
        case .berry:    return (322, (0.78, 0.72), (0.52, 0.92))
        case .midnight: return (250, (0.72, 0.68), (0.55, 0.92))
        case .graphite: return (215, (0.18, 0.42), (0.14, 0.82))
        case .contrast: return (212, (1.00, 0.72), (0.85, 1.00))
        }
    }

    var accent: Color {
        let spec = accentSpec
        return Color(UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let (s, b) = dark ? spec.dark : spec.light
            return UIColor(hue: CGFloat(spec.hue / 360), saturation: CGFloat(s),
                           brightness: CGFloat(b), alpha: 1)
        })
    }

    // MARK: - Kurspalette

    /// Farbtöne, aus denen die Veranstaltungsfarben gezogen werden.
    ///
    /// Jedes Thema bringt eine eigene Auswahl mit, damit die Kursfarben zum
    /// Akzent passen statt daneben zu stehen. Das Gelb-Grün-Band zwischen 40°
    /// und 140° ist überall ausgespart — dort wird jede Sättigung entweder
    /// blass oder grell.
    var hues: [Double] {
        switch self {
        case .signature:
            return [202, 218, 232, 248, 262, 280, 300, 322, 344, 8, 25, 188]
        case .ocean:
            return [186, 196, 172, 158, 206, 220, 234, 250, 300, 326, 348, 16]
        case .forest:
            return [150, 162, 138, 176, 190, 205, 262, 288, 320, 345, 22, 34]
        case .sunset:
            return [18, 32, 4, 345, 326, 300, 272, 248, 206, 188, 168, 44]
        case .berry:
            return [322, 336, 348, 300, 282, 262, 244, 210, 188, 166, 12, 28]
        case .midnight:
            return [250, 264, 236, 278, 296, 316, 336, 208, 190, 172, 352, 20]
        case .graphite:
            return [215, 225, 205, 235, 245, 195, 260, 185, 275, 175, 290, 165]
        case .contrast:
            return [212, 265, 300, 336, 8, 28, 152, 176, 194, 240, 320, 350]
        }
    }

    /// Wie kräftig die Kursfarben ausfallen. „Graphit" nimmt sich bewusst
    /// zurück, „Hoher Kontrast" legt zu.
    private var courseIntensity: (light: (Double, Double), dark: (Double, Double)) {
        switch self {
        case .graphite: return ((0.34, 0.52), (0.26, 0.86))
        case .contrast: return ((0.95, 0.62), (0.72, 0.98))
        default:        return ((0.78, 0.72), (0.58, 0.95))
        }
    }

    /// Wie blass die Flächenvariante ist — der Untergrund von Karten und
    /// Stundenplanblöcken.
    private var surfaceIntensity: (light: (Double, Double), dark: (Double, Double)) {
        switch self {
        case .graphite: return ((0.10, 0.965), (0.16, 0.24))
        case .contrast: return ((0.42, 0.955), (0.55, 0.30))
        case .midnight: return ((0.26, 0.970), (0.46, 0.26))
        default:        return ((0.30, 0.970), (0.42, 0.28))
        }
    }

    func courseColor(hue: Double) -> Color {
        let spec = courseIntensity
        return Color(UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let (s, b) = dark ? spec.dark : spec.light
            return UIColor(hue: CGFloat(hue / 360), saturation: CGFloat(s),
                           brightness: CGFloat(b), alpha: 1)
        })
    }

    func courseSurface(hue: Double) -> Color {
        let spec = surfaceIntensity
        return Color(UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let (s, b) = dark ? spec.dark : spec.light
            return UIColor(hue: CGFloat(hue / 360), saturation: CGFloat(s),
                           brightness: CGFloat(b), alpha: 1)
        })
    }

    /// Zwei Töne für die Verlaufsflächen der großen Kopfkarten.
    var headerGradient: [Color] {
        let spec = accentSpec
        let second = spec.hue + (self == .graphite ? 12 : 34)
        return [gradientStop(hue: spec.hue, shift: 0), gradientStop(hue: second, shift: 0.08)]
    }

    private func gradientStop(hue: Double, shift: Double) -> Color {
        let spec = accentSpec
        return Color(UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let (s, b) = dark ? spec.dark : spec.light
            return UIColor(hue: CGFloat(hue.truncatingRemainder(dividingBy: 360) / 360),
                           saturation: CGFloat(min(1, s + shift)),
                           brightness: CGFloat(dark ? b * 0.72 : b),
                           alpha: 1)
        })
    }
}

/// Hell, dunkel oder wie das System.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "Automatisch"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Gewählte Darstellung, dauerhaft gesichert.
///
/// Die Werte liegen zusätzlich in `Palette` gespiegelt: `Tint` wird aus jeder
/// Zeile der App gerufen und käme sonst ohne Environment nicht an das aktive
/// Thema heran.
@MainActor
@Observable
final class ThemeStore {
    private enum Key {
        static let theme = "studgo.theme"
        static let appearance = "studgo.appearance"
        static let compact = "studgo.compactRows"
    }

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Key.theme)
            Palette.shared.current = theme
        }
    }

    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Dichtere Listen für alle, die lieber mehr auf den Bildschirm bekommen.
    var isCompact: Bool {
        didSet { UserDefaults.standard.set(isCompact, forKey: Key.compact) }
    }

    /// Name des aktiven Themas, ohne dass der Aufrufer den Store braucht —
    /// für Zeilen, die das Thema nur benennen statt es zu ändern.
    static var currentName: String { Palette.shared.current.name }

    init() {
        let defaults = UserDefaults.standard
        let storedTheme = defaults.string(forKey: Key.theme).flatMap(AppTheme.init(rawValue:))
        let storedAppearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:))
        theme = storedTheme ?? .signature
        appearance = storedAppearance ?? .system
        isCompact = defaults.bool(forKey: Key.compact)
        Palette.shared.current = theme
    }
}

/// Spiegel des aktiven Themas für Aufrufer ohne Environment.
///
/// `Tint.color(_:)` steckt in Dutzenden von Zeilen tief in Listen; das Thema
/// dorthin durchzureichen hieße, jede dieser Ansichten um einen Parameter zu
/// erweitern. Stattdessen hält `Palette` den aktuellen Stand, und `ThemeStore`
/// schreibt ihn bei jeder Änderung fort.
///
/// **Warum eine beobachtbare Klasse und kein `static var`:** Als schlichte
/// statische Eigenschaft merkte SwiftUI nichts von der Änderung. Wer in der
/// Farbwahl ein anderes Thema antippte, sah die Vorschau darunter unverändert
/// — sie las zwar `Tint.color(…)`, hing aber an keinem beobachteten Wert und
/// wurde deshalb nicht neu gezeichnet. Erst nach einmal Zurück und wieder
/// Hinein baute SwiftUI die Ansicht neu auf und die Farben stimmten. Als
/// `@Observable` wird jeder Lesezugriff aus einem `body` heraus verzeichnet,
/// und die Umstellung schlägt sofort in der ganzen App durch.
@Observable
final class Palette {
    static let shared = Palette()

    /// Nur vom `ThemeStore` beschrieben, und der lebt auf dem MainActor.
    var current: AppTheme = .signature

    private init() {}
}
