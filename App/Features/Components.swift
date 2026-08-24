import Observation
import SwiftUI

/// Ladezustand für die Listenansichten — eine Stelle für Spinner,
/// Fehlermeldung und Leerzustand statt einer Kopie je Ansicht.
@Observable
final class Loadable<Value> {
    var value: Value?
    var errorMessage: String?
    var isLoading = false

    @MainActor
    func load(_ operation: @escaping () async throws -> Value) async {
        isLoading = value == nil
        errorMessage = nil
        do {
            value = try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Überlagert eine Liste mit Spinner, Fehler oder Leerhinweis — je nachdem,
/// was gerade zutrifft. Liegen Daten vor, bleibt sie unsichtbar.
struct StateOverlay: View {
    let isLoading: Bool
    let errorMessage: String?
    let isEmpty: Bool
    var emptyText: String = "Nichts vorhanden"
    var emptySymbol: String = "tray"
    var retry: (() -> Void)?

    var body: some View {
        if isLoading {
            ProgressView()
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Nicht geladen", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                if let retry {
                    Button("Erneut versuchen", action: retry)
                }
            }
        } else if isEmpty {
            ContentUnavailableView(emptyText, systemImage: emptySymbol)
        }
    }
}

/// Kreis mit Initialen — Stud.IP-Avatare erfordern einen zweiten
/// authentifizierten Request pro Person, das lohnt in Listen nicht.
struct InitialsBadge: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .accessibilityHidden(true)
    }

    /// Farbe aus den Initialen ableiten, damit dieselbe Person immer
    /// dieselbe Farbe bekommt.
    private var color: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .teal, .orange, .pink, .green]
        let hash = initials.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

/// Zeile mit Symbol, Titel und Zusatzinfo — die Grundform fast aller Listen.
struct RowLabel<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let detail {
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            trailing
        }
    }
}

extension RowLabel where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil, detail: String? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, detail: detail) { EmptyView() }
    }
}

/// Farbiger Balken links am Eintrag — ordnet Termine visuell ihrer
/// Veranstaltung zu, ohne dass ein Farbschema gepflegt werden muss.
struct AccentBar: View {
    let seed: String

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Self.color(for: seed))
            .frame(width: 4)
            .accessibilityHidden(true)
    }

    static func color(for seed: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .teal, .orange, .pink, .green, .mint]
        let hash = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        return palette[abs(hash) % palette.count]
    }
}

/// Segmentierter Umschalter über einer Liste. Im Inhalt statt in der Toolbar —
/// dort verdrängt er sonst den Navigationstitel.
struct SegmentedHeader<Selection: Hashable & Identifiable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
