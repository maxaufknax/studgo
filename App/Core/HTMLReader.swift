import Foundation

/// Liest die HTML-Teilmenge, die in Stud.IP-Feldern wirklich vorkommt, und
/// setzt sie in dieselben Blöcke um wie die Stud.IP-Auszeichnung.
///
/// **Warum ein eigener Leser und kein Suchen-und-Ersetzen:** Bis 1.2.0 wurden
/// HTML-Tags reihenweise durch Stud.IP-Auszeichnung ersetzt und das Ergebnis
/// noch einmal durch den Auszeichnungsleser geschickt. Das ging bei einfachen
/// Absätzen gut und bei allem anderen schief: Verschachtelte Aufzählungen
/// verloren ihre Ebene, Tabellen zerfielen zu Textwüsten, und ein
/// Ausrufezeichen am Zeilenanfang wurde plötzlich zur Überschrift. Vor allem
/// aber griff der ganze Weg nur, wenn das Feld mit `<!--HTML-->` begann — und
/// genau das tun die aus dem Vorlesungsverzeichnis importierten
/// Beschreibungen der LUH nicht.
///
/// **Warum kein `NSAttributedString(html:)`:** Der WebKit-Importer läuft nur
/// auf dem Hauptlaufwerk, blockiert dort messbar lange, zieht die
/// Schriftgrößen des Dokuments statt der Systemschrift heran und ignoriert die
/// Dynamische Schrift. Für Listenzeilen, die zu Dutzenden gesetzt werden,
/// kommt er nicht in Frage.
///
/// Unterstützt wird, was in den Feldern vorkommt: Absätze, Überschriften,
/// Aufzählungen (auch verschachtelt), Tabellen, Zitate, `<pre>`, Betonungen,
/// Verweise und Zeilenumbrüche. Alles Übrige fällt weg, der Text bleibt.
extension StudipMarkup {
    enum HTMLReader {

        // MARK: - Einstieg

        static func blocks(from raw: String) -> [StudipMarkup.Block] {
            var state = State()
            for token in tokenize(strippingNoise(from: raw)) {
                switch token {
                case .text(let value): state.append(text: value)
                case .tag(let tag): state.handle(tag)
                }
            }
            state.finish()
            return state.blocks
        }

        /// Entfernt, was nie im Text landen darf: Kommentare (darunter der
        /// `<!--HTML-->`-Marker selbst), Skripte, Stilangaben und die
        /// Dokumentdeklaration.
        private static func strippingNoise(from raw: String) -> String {
            var text = raw
            // `(?s)` statt `.dotMatchesLineSeparators`: Der Punkt soll auch
            // Zeilenumbrüche treffen — ein Kommentar oder ein `<script>` geht
            // über mehrere Zeilen. Die Option dafür gibt es aber nur bei
            // `NSRegularExpression.Options`; `String.replacingOccurrences`
            // nimmt `String.CompareOptions`, und dort ist sie nicht enthalten.
            // Der ICU-Ausdruck kennt den Schalter als Präfix im Muster selbst.
            for pattern in ["(?s)<!--.*?-->",
                            "(?s)<script\\b[^>]*>.*?</script\\s*>",
                            "(?s)<style\\b[^>]*>.*?</style\\s*>",
                            "<!DOCTYPE[^>]*>"] {
                text = text.replacingOccurrences(
                    of: pattern, with: "",
                    options: [.regularExpression, .caseInsensitive])
            }
            return text
        }

        // MARK: - Zerlegung

        private struct Tag {
            let name: String
            let isClosing: Bool
            let attributes: [String: String]
        }

        private enum Token {
            case text(String)
            case tag(Tag)
        }

        /// Zerlegt in Text und Tags. Ein `<` ohne passendes `>` — im Fließtext
        /// durchaus möglich („a < b") — bleibt einfach Text.
        private static func tokenize(_ html: String) -> [Token] {
            var tokens: [Token] = []
            var text = ""
            var index = html.startIndex

            while index < html.endIndex {
                guard html[index] == "<", let end = closingBracket(in: html, from: index) else {
                    text.append(html[index])
                    index = html.index(after: index)
                    continue
                }
                let body = String(html[html.index(after: index)..<end])
                guard let tag = parseTag(body) else {
                    // Kein erkennbares Tag: als Text stehen lassen.
                    text.append(contentsOf: html[index...end])
                    index = html.index(after: end)
                    continue
                }
                if !text.isEmpty {
                    tokens.append(.text(text))
                    text = ""
                }
                tokens.append(.tag(tag))
                index = html.index(after: end)
            }

            if !text.isEmpty { tokens.append(.text(text)) }
            return tokens
        }

        /// Das `>`, das dieses Tag schließt — Anführungszeichen im
        /// Attributwert werden übersprungen, sonst risse ein `title="a > b"`
        /// das Tag mitten entzwei.
        private static func closingBracket(in html: String, from start: String.Index) -> String.Index? {
            var index = html.index(after: start)
            var quote: Character?
            while index < html.endIndex {
                let character = html[index]
                if let open = quote {
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    return index
                } else if character == "<" {
                    // Ein zweites `<` vor dem `>`: das erste war Text.
                    return nil
                }
                index = html.index(after: index)
            }
            return nil
        }

        private static func parseTag(_ body: String) -> Tag? {
            var content = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            if content.hasSuffix("/") { content.removeLast() }

            let isClosing = content.hasPrefix("/")
            if isClosing { content.removeFirst() }

            let name = String(content.prefix { !$0.isWhitespace }).lowercased()
            guard !name.isEmpty,
                  name.range(of: "^[a-z][a-z0-9]*$", options: .regularExpression) != nil
            else { return nil }

            return Tag(name: name,
                       isClosing: isClosing,
                       attributes: isClosing ? [:] : attributes(in: String(content.dropFirst(name.count))))
        }

        private static func attributes(in body: String) -> [String: String] {
            guard !body.isEmpty,
                  let regex = try? NSRegularExpression(
                    pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))")
            else { return [:] }

            var found: [String: String] = [:]
            let range = NSRange(body.startIndex..., in: body)
            for match in regex.matches(in: body, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: body) else { continue }
                let value = (2...4)
                    .compactMap { Range(match.range(at: $0), in: body) }
                    .first
                    .map { String(body[$0]) } ?? ""
                found[String(body[keyRange]).lowercased()] = value
            }
            return found
        }

        // MARK: - Zustandsmaschine

        /// Sammelt Fließtext in `buffer` und schließt ihn beim nächsten
        /// Blockwechsel als passenden `Block` ab.
        private struct State {
            var blocks: [StudipMarkup.Block] = []
            var buffer = ""

            /// Offene Aufzählungen — Länge ist die Verschachtelungstiefe.
            var lists: [(ordered: Bool, counter: Int)] = []
            /// Ebene und Art des gerade offenen `<li>`.
            var listItem: (level: Int, marker: String)?
            var headingLevel: Int?
            var quoteDepth = 0
            var preDepth = 0

            /// Zeilen und Zellen einer Tabelle, solange eine offen ist.
            var tableRows: [[String]] = []
            var tableRow: [String] = []
            var inTable = false
            var inCell = false
            var tableHasHeader = false

            /// Offene Verweise als (Ziel, Textanfang im Puffer).
            var anchors: [(href: String, start: Int)] = []

            // MARK: Text

            mutating func append(text: String) {
                guard !text.isEmpty else { return }
                if preDepth > 0 {
                    buffer += text
                    return
                }
                // Zeilenumbrüche und Einzüge der Quelle sind in HTML
                // bedeutungslos; ohne dieses Zusammenziehen stünde in jedem
                // Absatz die Zeilenaufteilung der Datenbank.
                let collapsed = text.replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ",
                                                          options: .regularExpression)
                guard collapsed != " " || !buffer.isEmpty else { return }
                buffer += collapsed
            }

            private mutating func appendMarker(_ marker: String) {
                buffer += marker
            }

            // MARK: Tags

            mutating func handle(_ tag: Tag) {
                switch tag.name {
                case "br":
                    if !tag.isClosing { buffer += "\n" }

                case "hr":
                    if !tag.isClosing {
                        flush()
                        blocks.append(.rule)
                    }

                case "p", "div", "section", "article", "header", "footer", "figure", "figcaption":
                    flush()

                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flush()
                    if tag.isClosing {
                        headingLevel = nil
                    } else {
                        let digit = Int(tag.name.dropFirst()) ?? 3
                        // Stud.IP zählt umgekehrt: 1 ist die kleinste Stufe.
                        headingLevel = max(1, 5 - min(4, digit))
                    }

                case "ul", "ol":
                    flush()
                    if tag.isClosing {
                        if !lists.isEmpty { lists.removeLast() }
                    } else {
                        lists.append((ordered: tag.name == "ol", counter: 0))
                    }

                case "li":
                    flush()
                    if tag.isClosing {
                        listItem = nil
                    } else {
                        let level = max(1, lists.count)
                        if lists.isEmpty {
                            listItem = (level: 1, marker: "•")
                        } else {
                            lists[lists.count - 1].counter += 1
                            let current = lists[lists.count - 1]
                            listItem = (level: level,
                                        marker: current.ordered ? "\(current.counter)." : "•")
                        }
                    }

                case "blockquote":
                    flush()
                    quoteDepth = tag.isClosing ? max(0, quoteDepth - 1) : quoteDepth + 1

                case "pre":
                    flush()
                    preDepth = tag.isClosing ? max(0, preDepth - 1) : preDepth + 1

                case "table":
                    flush()
                    if tag.isClosing {
                        closeTable()
                    } else {
                        closeTable()
                        inTable = true
                    }

                case "tr":
                    guard inTable else { break }
                    if tag.isClosing {
                        closeCell()
                        if !tableRow.isEmpty { tableRows.append(tableRow) }
                        tableRow = []
                    } else {
                        closeCell()
                        tableRow = []
                    }

                case "td", "th":
                    guard inTable else { break }
                    if tag.isClosing {
                        closeCell()
                    } else {
                        closeCell()
                        inCell = true
                        buffer = ""
                        if tag.name == "th" && tableRows.isEmpty { tableHasHeader = true }
                    }

                case "b", "strong": appendMarker("**")
                case "i", "em": appendMarker("%%")
                case "u", "ins": appendMarker("__")
                case "code", "tt", "kbd", "samp", "var": appendMarker("##")
                case "del", "s", "strike": appendMarker(tag.isClosing ? "-}" : "{-")

                case "a":
                    if tag.isClosing {
                        closeAnchor()
                    } else if let href = tag.attributes["href"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
                              !href.hasPrefix("#") {
                        anchors.append((href: href, start: buffer.count))
                    }

                case "img":
                    // Bilder liegen hinter derselben Anmeldung wie die API und
                    // ließen sich in einer Textzeile ohnehin nicht laden. Wo
                    // eine Bildbeschreibung gepflegt ist, tritt sie an die
                    // Stelle des Bildes; sonst fällt es ersatzlos weg.
                    if !tag.isClosing, let alt = tag.attributes["alt"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
                        buffer += " %%\(alt)%% "
                    }

                default:
                    break
                }
            }

            // MARK: Abschließen

            /// Schließt den Puffer als Block ab — abhängig davon, worin er
            /// entstanden ist.
            mutating func flush() {
                // In einer Tabellenzelle gibt es keine Blöcke: Ein `<p>` darin
                // trennt Wörter, mehr nicht — ohne dieses Leerzeichen klebten
                // sie aneinander.
                if inCell {
                    if !buffer.isEmpty && !buffer.hasSuffix(" ") { buffer += " " }
                    return
                }
                closeAllAnchors()

                let raw = preDepth > 0
                    ? buffer.trimmingCharacters(in: .newlines)
                    : buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = ""
                guard !raw.isEmpty else { return }

                if preDepth > 0 {
                    blocks.append(.code(StudipMarkup.decodeEntities(raw)))
                    return
                }

                let text = StudipMarkup.inline(raw, studipSyntax: false)
                if let level = headingLevel {
                    blocks.append(.heading(level: level, text: text))
                } else if let item = listItem {
                    blocks.append(.listItem(level: item.level, marker: item.marker, text: text))
                } else if quoteDepth > 0 {
                    blocks.append(.quote(text))
                } else {
                    blocks.append(.paragraph(text))
                }
            }

            private mutating func closeCell() {
                guard inCell else { return }
                closeAllAnchors()
                tableRow.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = ""
                inCell = false
            }

            private mutating func closeTable() {
                closeCell()
                if !tableRow.isEmpty { tableRows.append(tableRow) }
                tableRow = []
                if !tableRows.isEmpty {
                    // Zeilen auf gleiche Zellenzahl bringen: ein `colspan`
                    // ließe die Spalten sonst gegeneinander verrutschen.
                    let width = tableRows.map(\.count).max() ?? 0
                    let padded = tableRows.map { row in
                        row + Array(repeating: "", count: width - row.count)
                    }
                    blocks.append(.table(rows: padded.map { $0.map { StudipMarkup.inline($0, studipSyntax: false) } },
                                         hasHeader: tableHasHeader))
                }
                tableRows = []
                tableHasHeader = false
                inTable = false
            }

            private mutating func closeAnchor() {
                guard let anchor = anchors.popLast() else { return }
                let start = min(anchor.start, buffer.count)
                let index = buffer.index(buffer.startIndex, offsetBy: start)
                let label = String(buffer[index...])
                    .replacingOccurrences(of: "[", with: "(")
                    .replacingOccurrences(of: "]", with: ")")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = String(buffer[..<index])
                // Ohne Beschriftung trägt die Adresse selbst — sonst stünde
                // dort ein antippbares Nichts.
                buffer += label.isEmpty ? anchor.href : "[\(label)]\(anchor.href)"
            }

            private mutating func closeAllAnchors() {
                while !anchors.isEmpty { closeAnchor() }
            }

            mutating func finish() {
                closeTable()
                flush()
            }
        }
    }
}
