import SwiftUI
import UIKit

/// Maße und Farben der App an einer Stelle — damit Karten, Abstände und
/// Rundungen überall gleich aussehen, ohne dass die Werte in jeder Ansicht
/// erneut auftauchen.
enum Design {
    static let cardCorner: CGFloat = 16
    static let chipCorner: CGFloat = 8
    static let cardPadding: CGFloat = 14
    static let rowGap: CGFloat = 12
    /// Haarlinie am Kartenrand. Bei aktivem Dunkelmodus liegt eine Karte sonst
    /// fast tonlos auf dem Untergrund und die Gliederung verschwindet.
    static let hairline: CGFloat = 0.5
}

/// Die Farben des Logos.
///
/// Sie kommen aus der Bilddatei
/// (`App/Resources/Assets.xcassets/AppLogo.imageset`) und nicht aus dem
/// gewählten Thema: Anmeldebildschirm und App-Symbol sollen aussehen wie das
/// Logo, unabhängig davon, welche Farbwelt jemand später einstellt.
enum Brand {
    /// Der Untergrund des Logos.
    static let night = Color(red: 10 / 255, green: 14 / 255, blue: 34 / 255)
    /// Das kräftige Blau am unteren Ende des Verlaufs im App-Symbol.
    static let deep = Color(red: 33 / 255, green: 130 / 255, blue: 220 / 255)
    /// Das Blau der Wortmarke, #38B6FF.
    static let blue = Color(red: 56 / 255, green: 182 / 255, blue: 255 / 255)

    static var gradient: LinearGradient {
        LinearGradient(colors: [night, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Das Logo als Kachel mit abgerundeten Ecken.
///
/// Die Bilddatei ist quadratisch und trägt ihren eigenen dunklen Untergrund —
/// beschnitten wie ein App-Symbol sieht sie überall gleich aus, auch auf
/// hellem Grund.
struct AppLogoView: View {
    var size: CGFloat = 96
    var cornerRadius: CGFloat = 22

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel("StudGo")
    }
}

/// Jede Veranstaltung bekommt eine eigene, dauerhaft gleiche Farbe.
///
/// Die Farbe wird aus der ID abgeleitet statt gespeichert: derselbe Kurs ist
/// dadurch in Stundenplan, Terminliste und Kursliste immer gleich eingefärbt,
/// ohne dass es dafür eine Verwaltung bräuchte. Aus welchem Vorrat an
/// Farbtönen gezogen wird, bestimmt das gewählte Thema — siehe `AppTheme`.
enum Tint {
    /// FNV-1a. `hashValue` verbietet sich hier: Swift salzt ihn pro
    /// Programmstart neu, die Farbe eines Kurses wechselte dann bei jedem
    /// App-Start.
    private static func fingerprint(_ seed: String) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return value
    }

    private static func hue(_ seed: String) -> Double {
        let hues = Palette.shared.current.hues
        return hues[Int(fingerprint(seed) % UInt64(hues.count))]
    }

    /// Kräftige Variante für Text, Symbole und Balken.
    static func color(_ seed: String) -> Color {
        Palette.shared.current.courseColor(hue: hue(seed))
    }

    /// Flächenvariante für Kartenhintergründe — so blass, dass Text darauf
    /// in beiden Erscheinungsbildern lesbar bleibt.
    static func surface(_ seed: String) -> Color {
        Palette.shared.current.courseSurface(hue: hue(seed))
    }

    /// Verlauf aus der Kursfarbe — für Kopfflächen, die mehr tragen sollen
    /// als eine einzelne Fläche.
    static func gradient(_ seed: String) -> LinearGradient {
        let base = hue(seed)
        let palette = Palette.shared.current
        return LinearGradient(colors: [palette.courseColor(hue: base),
                                       palette.courseColor(hue: base + 22)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }
}

/// Karte mit weichem Hintergrund — die Grundform der neuen Übersichten.
struct CardBackground: ViewModifier {
    var fill: Color = Color(.secondarySystemGroupedBackground)

    func body(content: Content) -> some View {
        content
            .padding(Design.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                    .fill(fill)
            )
            // Haarlinie plus ein Hauch Schatten: Im Dunkelmodus unterscheidet
            // sich `secondarySystemGroupedBackground` kaum vom Untergrund, und
            // ohne Kante zerfloss die Seite zu einer einzigen grauen Fläche.
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.30), lineWidth: Design.hairline)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    func card(_ fill: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        modifier(CardBackground(fill: fill))
    }
}

/// Kleine Beschriftung in einer Kapsel — für Kursnummer, Art, Raum.
struct Chip: View {
    let text: String
    var symbol: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Design.chipCorner, style: .continuous)
                .fill(color.opacity(0.13))
        )
    }
}

/// Umgangssprachliche Zeitangabe für den nächsten Termin.
enum Countdown {
    /// "läuft gerade" während des Termins, sonst "in 25 Min" / "in 3 Std".
    static func text(start: Date, end: Date, now: Date = Date()) -> String {
        if now >= start && now <= end {
            let remaining = Int(end.timeIntervalSince(now) / 60)
            return remaining <= 1 ? "endet gleich" : "läuft — noch \(remaining) Min"
        }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes < 0 { return "vorbei" }
        if minutes < 1 { return "jetzt gleich" }
        if minutes < 60 { return "in \(minutes) Min" }

        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "in \(hours) Std" : "in \(hours) Std \(rest) Min"
        }
        let days = hours / 24
        return days == 1 ? "morgen" : "in \(days) Tagen"
    }
}
