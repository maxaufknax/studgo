import Foundation
// SwiftUI steuert `underlineStyle` und `strikethroughStyle` bei. Auf
// Linux übernimmt das LinuxAttributeShim.swift — siehe dort.
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Wandelt Stud.IP-Texte in darstellbare Blöcke um.
///
/// **Warum das nötig ist:** Stud.IP speichert Beschreibungen, Ankündigungen,
/// Forenbeiträge und Wikiseiten *nicht* als HTML, sondern in einer eigenen
/// Textauszeichnung (`lib/classes/StudipCoreFormat.php`) — `**fett**`,
/// `%%kursiv%%`, `- Liste`, `!Überschrift`, `[Text]https://…`. Nur wenn ein
/// Feld mit dem Marker `<!--HTML-->` beginnt, ist der Inhalt laut Stud.IP
/// echtes HTML (`Markup::isHtml`, `HTML_MARKER_REGEXP`).
///
/// **Und warum der Marker allein nicht reicht:** In der Praxis steht in den
/// Feldern der LUH reihenweise HTML *ohne* Marker — Beschreibungen, die aus
/// dem Vorlesungsverzeichnis importiert oder aus einem Textverarbeiter
/// eingefügt wurden, tragen `<p>…</p>` und `&auml;` im Klartext. Stud.IP
/// selbst zeigt so ein Feld ebenfalls falsch an; in einer App fällt es nur
/// mehr auf. Deshalb entscheidet hier nicht der Marker allein, sondern
/// zusätzlich der Augenschein (`looksLikeHTML`).
///
/// Wer beides übersieht, zeigt dem Leser entweder die Sternchen und
/// Prozentzeichen im Klartext oder — wie bis 1.2.0 — die nackten `<p>`-Tags
/// und `&auml;`-Entitäten.
enum StudipMarkup {

    // MARK: - Blockmodell

    /// Ein Absatz im Ergebnis. Inline-Auszeichnungen stecken im
    /// `AttributedString`, die Gliederung dagegen im Fall.
    enum Block {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        /// `marker` ist entweder ein Aufzählungszeichen oder eine Nummer.
        case listItem(level: Int, marker: String, text: AttributedString)
        case quote(AttributedString)
        case code(String)
        case rule
        /// Erste Zeile ist die Kopfzeile, wenn `hasHeader` gesetzt ist.
        case table(rows: [[AttributedString]], hasHeader: Bool)
    }

    // MARK: - Einstieg

    /// Erkennt, ob HTML oder Stud.IP-Auszeichnung vorliegt, und zerlegt den
    /// Text entsprechend.
    static func blocks(from raw: String) -> [Block] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return isHTML(text) ? HTMLReader.blocks(from: text) : blocksFromMarkup(text)
    }

    /// Reiner Text ohne jede Auszeichnung — für Vorschauzeilen in Listen,
    /// wo nur eine Zeile Platz hat.
    static func plain(from raw: String) -> String {
        blocks(from: raw)
            .map { block -> String in
                switch block {
                case .heading(_, let text), .paragraph(let text), .quote(let text):
                    return String(text.characters)
                case .listItem(_, let marker, let text):
                    return "\(marker) \(String(text.characters))"
                case .code(let text): return text
                case .rule: return ""
                case .table(let rows, _):
                    return rows.map { $0.map { String($0.characters) }.joined(separator: " · ") }
                        .joined(separator: "\n")
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML oder nicht? Zwei Wege führen zu „ja".
    static func isHTML(_ text: String) -> Bool {
        hasHTMLMarker(text) || looksLikeHTML(text)
    }

    /// `<!--HTML-->` am Anfang ist Stud.IPs eigenes Kennzeichen.
    static func hasHTMLMarker(_ text: String) -> Bool {
        text.range(of: "^\\s*<!--\\s*HTML.*?-->",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Der Augenschein: ein *geschlossenes* oder eindeutig leeres Tag aus dem
    /// HTML-Grundwortschatz.
    ///
    /// Bewusst eng gefasst. Stud.IP-Auszeichnung kennt kein `<`-Tag, wohl aber
    /// das Kleiner-als-Zeichen — `a < b` oder `<3` dürfen nicht plötzlich als
    /// HTML gelten und ihre Zeilenumbrüche verlieren. Ein `</p>` oder ein
    /// `<br />` dagegen entsteht in Fließtext nicht aus Versehen.
    static func looksLikeHTML(_ text: String) -> Bool {
        let pattern = "</(p|div|li|ul|ol|table|tr|td|th|span|strong|em|b|i|u|a|h[1-6]|pre|code|blockquote)\\s*>"
            + "|<(br|hr|img)\\b[^>]*/?>"
            + "|<(p|div|ul|ol|li|table|tr|td|th|blockquote|h[1-6])(\\s[^>]*)?>"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Stud.IP-Auszeichnung

    private static func blocksFromMarkup(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !joined.isEmpty else { return }
            blocks.append(.paragraph(inline(joined)))
        }

        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")[...]

        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // [code] / [pre] — bis zum schließenden Gegenstück wörtlich.
            if let opener = ["[code", "[pre"].first(where: { trimmed.lowercased().hasPrefix($0) }) {
                flushParagraph()
                let closing = opener == "[code" ? "[/code]" : "[/pre]"
                let body = collectBlock(openingLine: trimmed, closing: closing, from: &lines)
                blocks.append(.code(body))
                continue
            }

            // Leerzeile beendet den Absatz.
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Waagerechte Linie: `--` bis `--9`, allein auf der Zeile.
            if trimmed.range(of: "^--\\d?$", options: .regularExpression) != nil {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            // Überschrift: je mehr Ausrufezeichen, desto größer.
            if let match = trimmed.range(of: "^!{1,4}", options: .regularExpression) {
                flushParagraph()
                let bangs = trimmed.distance(from: match.lowerBound, to: match.upperBound)
                let content = String(trimmed[match.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    blocks.append(.heading(level: max(1, 5 - bangs), text: inline(content)))
                }
                continue
            }

            // Aufzählung: `-` ungeordnet, `=` nummeriert, Zeichenzahl = Ebene.
            if let bullet = listPrefix(of: trimmed) {
                flushParagraph()
                blocks.append(.listItem(level: bullet.level,
                                        marker: bullet.ordered ? "\(counter(for: bullet.level, in: blocks))." : "•",
                                        text: inline(bullet.content)))
                continue
            }

            // Tabelle: `|Zelle|Zelle|`
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 2 {
                flushParagraph()
                var rows: [[AttributedString]] = [tableRow(trimmed)]
                while let next = lines.first?.trimmingCharacters(in: .whitespaces),
                      next.hasPrefix("|"), next.hasSuffix("|") {
                    rows.append(tableRow(next))
                    lines = lines.dropFirst()
                }
                blocks.append(.table(rows: rows, hasHeader: rows.count > 1))
                continue
            }

            // Zitat: [quote]…[/quote], ein- oder mehrzeilig.
            if trimmed.lowercased().hasPrefix("[quote") {
                flushParagraph()
                let body = collectBlock(openingLine: trimmed, closing: "[/quote]", from: &lines)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { blocks.append(.quote(inline(body))) }
                continue
            }

            paragraph.append(line)
        }

        flushParagraph()
        return blocks
    }

    /// Sammelt den Inhalt zwischen einem öffnenden und einem schließenden Tag.
    ///
    /// Der Fall, an dem eine naive Fassung scheitert: Öffnendes und
    /// schließendes Tag stehen auf **derselben** Zeile (`[quote]Text[/quote]`).
    /// Wer nur die Folgezeilen nach dem Schluss absucht, findet ihn nie und
    /// schluckt den ganzen Rest des Textes ins Zitat.
    private static func collectBlock(openingLine: String,
                                     closing: String,
                                     from lines: inout ArraySlice<String>) -> String {
        var body: [String] = []

        // Was hinter dem öffnenden Tag in derselben Zeile steht, zählt mit.
        var head = ""
        if let start = openingLine.range(of: "]") {
            head = String(openingLine[start.upperBound...])
        }
        if let end = head.range(of: closing, options: .caseInsensitive) {
            // Schon auf dieser Zeile zu Ende.
            return String(head[..<end.lowerBound])
        }
        if !head.isEmpty { body.append(head) }

        while let next = lines.first {
            lines = lines.dropFirst()
            if let end = next.range(of: closing, options: .caseInsensitive) {
                let tail = String(next[..<end.lowerBound])
                if !tail.trimmingCharacters(in: .whitespaces).isEmpty { body.append(tail) }
                break
            }
            body.append(next)
        }
        return body.joined(separator: "\n")
    }

    /// Wie viele nummerierte Punkte auf derselben Ebene schon vorausgingen.
    private static func counter(for level: Int, in blocks: [Block]) -> Int {
        var count = 1
        for block in blocks.reversed() {
            guard case .listItem(let itemLevel, let marker, _) = block else { break }
            guard itemLevel == level else {
                if itemLevel < level { break }
                continue
            }
            guard marker.hasSuffix(".") else { break }
            count += 1
        }
        return count
    }

    private static func listPrefix(of line: String) -> (level: Int, ordered: Bool, content: String)? {
        guard let first = line.first, first == "-" || first == "=" else { return nil }
        let markers = line.prefix { $0 == first }
        // Nach den Zeichen muss ein Leerzeichen stehen — sonst wäre `--- Text`
        // aus einer Trennlinie und `-kursiv-` aus einer Betonung eine Liste.
        let rest = line.dropFirst(markers.count)
        guard rest.hasPrefix(" ") else { return nil }
        let content = rest.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (level: markers.count, ordered: first == "=", content: content)
    }

    private static func tableRow(_ line: String) -> [AttributedString] {
        line.dropFirst().dropLast()
            .components(separatedBy: "|")
            .map { inline($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - Entitäten

    /// Löst HTML-Entitäten auf.
    ///
    /// Läuft **auch** über Text ohne HTML: `&auml;` und `&nbsp;` stehen in
    /// Stud.IP-Feldern auch dann, wenn ringsherum kein einziges Tag vorkommt —
    /// die Weboberfläche schreibt sie beim Speichern hinein. In der App stand
    /// dort wörtlich „Lehramtsstudieng&auml;nge".
    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var text = input
        let simple: [(String, String)] = [
            ("&nbsp;", "\u{00a0}"), ("&auml;", "ä"), ("&ouml;", "ö"), ("&uuml;", "ü"),
            ("&Auml;", "Ä"), ("&Ouml;", "Ö"), ("&Uuml;", "Ü"), ("&szlig;", "ß"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#039;", "'"), ("&#39;", "'"),
            ("&lt;", "<"), ("&gt;", ">"), ("&ndash;", "–"), ("&mdash;", "—"),
            ("&hellip;", "…"), ("&euro;", "€"), ("&bdquo;", "„"), ("&ldquo;", "“"),
            ("&rdquo;", "”"), ("&laquo;", "«"), ("&raquo;", "»"), ("&deg;", "°"),
            ("&sbquo;", "‚"), ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&middot;", "·"),
            ("&bull;", "•"), ("&dagger;", "†"), ("&trade;", "™"), ("&copy;", "©"),
            ("&reg;", "®"), ("&plusmn;", "±"), ("&times;", "×"), ("&divide;", "÷"),
            ("&frac12;", "½"), ("&frac14;", "¼"), ("&sup2;", "²"), ("&sup3;", "³"),
            ("&rarr;", "→"), ("&larr;", "←"), ("&harr;", "↔"), ("&shy;", ""),
        ]
        for (entity, replacement) in simple {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = decodeNumericEntities(text)
        // Zuletzt, sonst würde `&amp;lt;` zweimal aufgelöst.
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        guard input.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);")
        else { return input }
        var text = input
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: text),
                  let flagRange = Range(match.range(at: 1), in: text),
                  let digitRange = Range(match.range(at: 2), in: text) else { continue }
            let isHex = !text[flagRange].isEmpty
            let digits = String(text[digitRange])
            guard let value = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value) else { continue }
            text.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return text
    }

    // MARK: - Inline-Auszeichnung

    /// Betonungen, Links und Adressen innerhalb einer Zeile.
    ///
    /// `studipSyntax: false` schaltet die einzeichigen Kurzformen (`*Wort*`,
    /// `%Wort%`, `#Wort#`) ab. Aus HTML gewonnener Text bringt seine Betonung
    /// als doppelte Marker mit, die der Leser dort nie selbst geschrieben hat;
    /// ein Prozentzeichen im Fließtext („%-Angabe") darf ihn dann nicht
    /// kursiv setzen.
    static func inline(_ raw: String, studipSyntax: Bool = true) -> AttributedString {
        var text = decodeEntities(raw)

        // `[nop]…[/nop]` schaltet die Auszeichnung ab — der Inhalt bleibt roh.
        if studipSyntax {
            text = text.replacingOccurrences(of: "\\[nop\\](.*?)\\[/nop\\]", with: "$1",
                                             options: [.regularExpression, .caseInsensitive])
        }

        var result = AttributedString()
        var pending = ""

        func flushPending() {
            guard !pending.isEmpty else { return }
            result.append(styled(pending, studipSyntax: studipSyntax))
            pending = ""
        }

        // Zuerst Links und Adressen aus dem Text lösen, damit deren Inhalt
        // nicht als Betonung missdeutet wird (`https://a_b_c` etwa).
        for piece in splitLinks(text) {
            switch piece {
            case .text(let value):
                pending += value
            case .link(let label, let url):
                flushPending()
                var chunk = styled(label, studipSyntax: studipSyntax)
                chunk.link = url
                chunk.underlineStyle = .single
                result.append(chunk)
            }
        }

        flushPending()
        return result
    }

    private enum Piece {
        case text(String)
        case link(label: String, url: URL)
    }

    /// Zerlegt eine Zeile in Text und Verweise. Stud.IP kennt `[Text]url`,
    /// nackte Adressen und `[Text]mail@example.org`.
    private static func splitLinks(_ text: String) -> [Piece] {
        let pattern = "(?:\\[([^\\n\\]]+)\\])?"
            + "((?:[a-zA-Z][a-zA-Z0-9+.-]*://[^\\s<>\"]+)"
            + "|(?:www\\.[^\\s<>\"]+)"
            + "|(?:[\\w.!#%+-]+@[A-Za-z0-9-]+\\.[A-Za-z0-9.-]{2,}))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.text(text)] }

        var pieces: [Piece] = []
        var cursor = text.startIndex
        let range = NSRange(text.startIndex..., in: text)

        for match in regex.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text),
                  let targetRange = Range(match.range(at: 2), in: text) else { continue }
            if cursor < whole.lowerBound {
                pieces.append(.text(String(text[cursor..<whole.lowerBound])))
            }
            var target = String(text[targetRange])
            // Satzzeichen am Ende gehören zum Satz, nicht zur Adresse.
            while let last = target.last, ".,;:!?)".contains(last) {
                target.removeLast()
            }
            let label = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? target
            guard let url = normalizedURL(target) else {
                pieces.append(.text(String(text[whole])))
                cursor = whole.upperBound
                continue
            }
            pieces.append(.link(label: label, url: url))
            // Was das Kürzen der Satzzeichen wieder freigegeben hat, ist Text.
            let consumed = text.index(targetRange.lowerBound, offsetBy: target.count)
            if consumed < whole.upperBound {
                pieces.append(.text(String(text[consumed..<whole.upperBound])))
            }
            cursor = whole.upperBound
        }

        if cursor < text.endIndex { pieces.append(.text(String(text[cursor...]))) }
        return pieces.isEmpty ? [.text(text)] : pieces
    }

    private static func normalizedURL(_ target: String) -> URL? {
        if target.contains("://") { return URL(string: target) }
        if target.contains("@") && !target.contains(" ") { return URL(string: "mailto:\(target)") }
        if target.hasPrefix("www.") { return URL(string: "https://\(target)") }
        return nil
    }

    /// Setzt fett, kursiv, unterstrichen, Festbreite und durchgestrichen —
    /// jeweils in der ausführlichen und der einfachen Schreibweise.
    private static func styled(_ raw: String, studipSyntax: Bool = true) -> AttributedString {
        var text = raw
        var result = AttributedString()

        // Reihenfolge zählt: die doppelten Zeichen zuerst, sonst frisst die
        // einfache Form (`*Wort*`) die Hälfte eines `**Satz**`.
        var rules: [(pattern: String, apply: (inout AttributedString) -> Void)] = [
            ("\\*\\*(.+?)\\*\\*", { $0.inlinePresentationIntent = .stronglyEmphasized }),
            ("%%(.+?)%%", { $0.inlinePresentationIntent = .emphasized }),
            ("__(.+?)__", { $0.underlineStyle = .single }),
            ("##(.+?)##", { $0.inlinePresentationIntent = .code }),
            ("\\{-(.+?)-\\}", { $0.strikethroughStyle = .single }),
        ]
        if studipSyntax {
            rules += [
                ("(?<![\\w*])\\*([^\\s*][^*]*?)\\*(?![\\w*])", { $0.inlinePresentationIntent = .stronglyEmphasized }),
                ("(?<![\\w%])%([^\\s%][^%]*?)%(?![\\w%])", { $0.inlinePresentationIntent = .emphasized }),
                ("(?<![\\w#])#([^\\s#][^#]*?)#(?![\\w#])", { $0.inlinePresentationIntent = .code }),
            ]
        }

        // Der Text wird einmal von links nach rechts abgearbeitet: an jeder
        // Stelle gewinnt die Regel, die am frühesten greift.
        while !text.isEmpty {
            var best: (range: Range<String.Index>, inner: Range<String.Index>,
                       apply: (inout AttributedString) -> Void)?

            for rule in rules {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let whole = Range(match.range, in: text),
                      let inner = Range(match.range(at: 1), in: text) else { continue }
                if best == nil || whole.lowerBound < best!.range.lowerBound {
                    best = (whole, inner, rule.apply)
                }
            }

            guard let hit = best else {
                result.append(AttributedString(text))
                break
            }

            if hit.range.lowerBound > text.startIndex {
                result.append(AttributedString(String(text[text.startIndex..<hit.range.lowerBound])))
            }
            var chunk = AttributedString(String(text[hit.inner]))
            hit.apply(&chunk)
            result.append(chunk)
            text = String(text[hit.range.upperBound...])
        }

        return result
    }
}
