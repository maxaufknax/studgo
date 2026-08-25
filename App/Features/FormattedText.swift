import SwiftUI

/// Zeigt einen Stud.IP-Text so an, wie er gemeint ist.
///
/// Der Text wird zerlegt (`StudipMarkup`) und blockweise gesetzt: Absätze,
/// Überschriften, Aufzählungen mit Einzug, Zitate, Quelltext und Tabellen.
/// Vorher lief jede Beschreibung durch `strippingHTML` — das entfernte zwar
/// HTML-Reste, ließ aber die Stud.IP-Auszeichnung stehen und warf bei den
/// HTML-Feldern die Absätze weg.
struct FormattedText: View {
    let raw: String
    /// Grundschriftgrad; Überschriften und Beiwerk richten sich danach.
    var font: Font = .callout
    /// Über wie viele Blöcke hinweg gezeigt wird, bevor gekürzt wird.
    /// `nil` heißt: alles.
    var blockLimit: Int?
    /// Etwas mehr Luft zwischen den Blöcken — für ganze Seiten (Wiki,
    /// Ankündigung) statt für einen Absatz in einer Karte.
    var isDocument = false

    private var blocks: [StudipMarkup.Block] {
        let all = StudipMarkup.blocks(from: raw)
        guard let blockLimit, all.count > blockLimit else { return all }
        return Array(all.prefix(blockLimit))
    }

    private var spacing: CGFloat { isDocument ? 12 : 9 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index], isFirst: index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: StudipMarkup.Block, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                // Eine Überschrift gehört näher an das, was unter ihr steht,
                // als an das, was über ihr endet.
                .padding(.top, isFirst ? 0 : (isDocument ? 8 : 3))

        case .paragraph(let text):
            Text(text)
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let level, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    // Feste Breite: sonst rücken „•" und „10." verschieden
                    // weit ein und die Liste franst links aus.
                    .frame(minWidth: 14, alignment: .trailing)
                Text(text)
                    .font(font)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // Untergeordnete Punkte rücken ein, sonst geht die Gliederung
            // verloren, die HTML über `<ul>` und Stud.IP über die Zahl der
            // Striche ausdrückt.
            .padding(.leading, CGFloat(max(0, level - 1)) * 16)

        case .quote(let text):
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: 3)
                Text(text)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )

        case .rule:
            Divider().padding(.vertical, 1)

        case .table(let rows, let hasHeader):
            MarkupTable(rows: rows, hasHeader: hasHeader, font: font)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline
        case 3: return .subheadline.weight(.semibold)
        default: return .footnote.weight(.semibold)
        }
    }
}

/// Eine Tabelle aus einem Stud.IP-Text.
///
/// **Warum `Grid` und nicht verschachtelte Stacks:** Mit `HStack` je Zeile
/// bestimmt jede Zeile ihre Spaltenbreiten selbst — bei ungleich langen
/// Zellen standen die Spalten sichtbar gegeneinander versetzt, und genau so
/// sah eine Wiki-Tabelle in der App aus. `Grid` richtet alle Zeilen an
/// denselben Spalten aus.
///
/// **Warum waagerecht scrollbar:** Eine Vorlesungsübersicht mit fünf Spalten
/// passt auf kein Telefon. Ohne eigenen Scrollbereich zöge sie die ganze Seite
/// in die Breite; hier bleibt der Rest der Seite an Ort und Stelle.
private struct MarkupTable: View {
    let rows: [[AttributedString]]
    let hasHeader: Bool
    let font: Font

    /// Ab wie vielen Zeichen eine Zelle umbrechen darf statt die Spalte zu
    /// dehnen. Kurze Zellen (Datum, Nummer) bleiben dadurch einzeilig.
    private let wrapWidth: CGFloat = 210

    private var columnCount: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(Array(0..<columnCount), id: \.self) { columnIndex in
                            cell(row: rowIndex, column: columnIndex)
                        }
                    }
                    // Direkt im `Grid` statt in einer `GridRow`: So spannt
                    // die Linie über alle Spalten, ohne dass die Spaltenzahl
                    // noch einmal angegeben werden müsste.
                    if rowIndex < rows.count - 1 { Divider() }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(columnCount > 2 ? .visible : .automatic)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func cell(row: Int, column: Int) -> some View {
        let isHeader = hasHeader && row == 0
        let value = rows.indices.contains(row) && rows[row].indices.contains(column)
            ? rows[row][column]
            : AttributedString("")

        Text(value)
            .font(isHeader ? font.weight(.semibold) : font)
            .foregroundStyle(isHeader ? Color.primary : Color.primary.opacity(0.9))
            .frame(maxWidth: wrapWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(isHeader ? Color(.secondarySystemFill).opacity(0.6) : Color.clear)
            .overlay(alignment: .leading) {
                if column > 0 {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(width: 0.5)
                }
            }
    }
}

/// Ein aufklappbarer Textblock — für Beschreibungen, die eine ganze Seite
/// füllen können und dann alles Übrige aus dem Bild schieben.
struct ExpandableText: View {
    let raw: String
    var font: Font = .callout
    /// Ab wie vielen Zeichen überhaupt gekürzt wird.
    var threshold: Int = 420
    /// Wie viele Blöcke im eingeklappten Zustand stehen bleiben.
    var collapsedBlocks: Int = 3

    @State private var isExpanded = false

    private var isLong: Bool {
        raw.count > threshold || StudipMarkup.blocks(from: raw).count > collapsedBlocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormattedText(raw: raw,
                          font: font,
                          blockLimit: isExpanded || !isLong ? nil : collapsedBlocks)

            if isLong {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Weniger anzeigen" : "Weiterlesen")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Eine einzelne Zeile Stud.IP-Text mit Auszeichnung — für Listenzeilen,
/// Untertitel und alles, wo genau eine Zeile Platz hat.
///
/// Nimmt dem Aufrufer die Entscheidung ab, ob ein Feld HTML enthält: Bis 1.2.0
/// wurden Ordner- und Kursbeschreibungen als schlichtes `Text(...)` gesetzt,
/// und dort standen dann `<p>` und `&auml;` wörtlich im Bild.
struct MarkupLine: View {
    let raw: String
    var font: Font = .caption
    var lineLimit: Int = 2
    var color: Color = .secondary

    var body: some View {
        Text(StudipMarkup.plain(from: raw).replacingOccurrences(of: "\n", with: " "))
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
    }
}
