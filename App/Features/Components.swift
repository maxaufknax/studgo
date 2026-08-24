import Observation
import SwiftUI

/// Ladezustand für die Listenansichten — eine Stelle für Spinner,
/// Fehlermeldung und Leerzustand statt einer Kopie je Ansicht.
@Observable
final class Loadable<Value> {
    var value: Value?
    var errorMessage: String?
    var isLoading = false

    var hasValue: Bool { value != nil }

    @MainActor
    func load(_ operation: @escaping () async throws -> Value) async {
        isLoading = value == nil
        errorMessage = nil
        do {
            value = try await operation()
        } catch {
            // Ein vorhandener Stand bleibt stehen: bei einem gescheiterten
            // Nachladen ist der alte Inhalt mehr wert als eine leere Seite.
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Überlagert eine Liste mit Spinner, Fehler oder Leerhinweis — aber nur,
/// solange nichts anzuzeigen ist. Liegen Daten vor, bleibt sie unsichtbar:
/// ein fehlgeschlagenes Nachladen darf den bereits gezeigten Inhalt nicht
/// hinter einer Fehlermeldung verschwinden lassen.
struct StateOverlay: View {
    let isLoading: Bool
    let errorMessage: String?
    let isEmpty: Bool
    var emptyText: String = "Nichts vorhanden"
    var emptySymbol: String = "tray"
    var retry: (() -> Void)?

    var body: some View {
        if !isEmpty {
            EmptyView()
        } else if isLoading {
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
        } else {
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
            .background(Circle().fill(Tint.color(initials)))
            .accessibilityHidden(true)
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
/// Veranstaltung zu, ohne dass ein Farbschema gepflegt werden müsste.
struct AccentBar: View {
    let seed: String

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Tint.color(seed))
            .frame(width: 4)
            .accessibilityHidden(true)
    }
}

/// Uhrzeitspalte links am Termin: Beginn kräftig, Ende darunter zurückgenommen.
/// Dadurch lassen sich untereinander stehende Termine mit einem Blick
/// zeitlich einordnen, ohne dass die Zeile in Text ertrinkt.
struct TimeColumn: View {
    let start: Date
    let end: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(start, format: .dateTime.hour().minute())
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(end, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: 46, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Format.timeRange(start, end))
    }
}

/// Ein Termin als Listenzeile: Uhrzeit, Kursfarbe, Titel, Ort.
struct EventRow: View {
    let event: CourseEvent
    /// In Tageslisten ist das Datum schon in der Überschrift — dort wäre es
    /// in jeder Zeile Wiederholung.
    var showDay = false
    /// In der Terminliste einer Veranstaltung steht in `title` deren Name.
    /// Dort trägt das Thema der Sitzung die Information.
    var preferTopic = false

    private var headline: String {
        if preferTopic, let topic = event.topic { return topic }
        return event.title
    }

    var body: some View {
        HStack(spacing: 10) {
            TimeColumn(start: event.start, end: event.end)

            AccentBar(seed: event.tintSeed)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(event.isCancelled)
                    .foregroundStyle(event.isCancelled ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                    if showDay {
                        Label(Format.dayShort(event.start), systemImage: "calendar")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if event.isCancelled {
                    Chip(text: "Fällt aus", symbol: "xmark.circle.fill", color: .red)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
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
