import SwiftUI

/// Zeigt einen Stud.IP-Text so an, wie er gemeint ist.
///
/// Vorher lief jede Beschreibung durch `strippingHTML`: Das entfernte zwar
/// HTML-Reste, ließ aber die Stud.IP-Auszeichnung stehen — im Kurstext stand
/// dann wörtlich `**Achtung**` und `- Punkt`, Absätze verschmolzen zu einem
/// Block und Verweise waren nicht anzutippen. Hier wird der Text stattdessen
/// zerlegt (`StudipMarkup`) und blockweise gesetzt.
struct FormattedText: View {
    let raw: String
    /// Grundschriftgrad; Überschriften und Beiwerk richten sich danach.
    var font: Font = .callout
    /// Über wie viele Blöcke hinweg gezeigt wird, bevor gekürzt wird.
    /// `nil` heißt: alles.
    var blockLimit: Int?

    private var blocks: [StudipMarkup.Block] {
        let all = StudipMarkup.blocks(from: raw)
        guard let blockLimit, all.count > blockLimit else { return all }
        return Array(all.prefix(blockLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: StudipMarkup.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

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
                Text(text)
                    .font(font)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // Untergeordnete Punkte rücken ein, sonst geht die Gliederung
            // verloren, die Stud.IP über die Zahl der Striche ausdrückt.
            .padding(.leading, CGFloat(max(0, level - 1)) * 14)

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
                    .padding(9)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )

        case .rule:
            Divider().padding(.vertical, 1)

        case .table(let rows):
            // Waagerecht scrollbar: eine Stud.IP-Tabelle sprengt sonst jede
            // Telefonbreite und würde die ganze Seite mitziehen.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(rows[rowIndex].indices, id: \.self) { cellIndex in
                                Text(rows[rowIndex][cellIndex])
                                    .font(rowIndex == 0 ? font.weight(.semibold) : font)
                                    .frame(minWidth: 92, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                            }
                        }
                        .background(rowIndex.isMultiple(of: 2)
                                    ? Color(.secondarySystemFill).opacity(0.35)
                                    : Color.clear)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill).opacity(0.5))
            )
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
                Button(isExpanded ? "Weniger anzeigen" : "Weiterlesen") {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
