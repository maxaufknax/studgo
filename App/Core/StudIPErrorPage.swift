import Foundation

/// Stud.IP beantwortet Fehler am OAuth-Endpunkt mit einer vollständigen
/// HTML-Fehlerseite statt mit JSON. Die eigentliche Meldung steht dort in
/// `<div class="messagebox_details"><ul><li>…</li></ul></div>`.
enum StudIPErrorPage {
    static func message(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        guard let details = block(in: html, after: "messagebox_details") else { return nil }
        let items = matches(of: "<li>(.*?)</li>", in: details).map(plainText)
        let text = items.isEmpty ? plainText(details) : items.joined(separator: "\n")
        return text.nilIfEmpty
    }

    /// Schneidet den Text zwischen einer Klassen-Markierung und dem Ende
    /// des zugehörigen Blocks heraus — grob, aber für eine Fehlermeldung genug.
    private static func block(in html: String, after marker: String) -> String? {
        guard let start = html.range(of: marker),
              let openEnd = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let close = html.range(of: "</div>", range: openEnd.upperBound..<html.endIndex)
        else { return nil }
        return String(html[openEnd.upperBound..<close.lowerBound])
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func plainText(_ html: String) -> String {
        html.strippingHTML
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
