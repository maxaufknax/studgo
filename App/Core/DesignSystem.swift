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
        let hues = Palette.current.hues
        return hues[Int(fingerprint(seed) % UInt64(hues.count))]
    }

    /// Kräftige Variante für Text, Symbole und Balken.
    static func color(_ seed: String) -> Color {
        Palette.current.courseColor(hue: hue(seed))
    }

    /// Flächenvariante für Kartenhintergründe — so blass, dass Text darauf
    /// in beiden Erscheinungsbildern lesbar bleibt.
    static func surface(_ seed: String) -> Color {
        Palette.current.courseSurface(hue: hue(seed))
    }

    /// Verlauf aus der Kursfarbe — für Kopfflächen, die mehr tragen sollen
    /// als eine einzelne Fläche.
    static func gradient(_ seed: String) -> LinearGradient {
        let base = hue(seed)
        return LinearGradient(colors: [Palette.current.courseColor(hue: base),
                                       Palette.current.courseColor(hue: base + 22)],
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
