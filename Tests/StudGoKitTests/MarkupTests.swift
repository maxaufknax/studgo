import Foundation
import Testing
@testable import StudGoKit

/// Stud.IP liefert Beschreibungen in zwei Welten: eigener Auszeichnung
/// (`**fett**`, `- Liste`) und HTML aus dem Vorlesungsverzeichnis. Beides
/// landet in denselben Feldern, und der Leser muss selbst erkennen, was
/// vorliegt. Diese Tests halten fest, wo die Grenze verläuft.
@Suite("Textauszeichnung")
struct MarkupTests {

    // MARK: - Erkennung

    @Test("HTML wird an geschlossenen Tags erkannt")
    func htmlErkennung() {
        #expect(StudipMarkup.isHTML("<p>Ein Absatz</p>"))
        #expect(StudipMarkup.isHTML("<!--HTML--> danach egal was"))
        #expect(StudipMarkup.isHTML("Zeile eins<br>Zeile zwei"))
        // Ein Kleinerzeichen im Fließtext ist kein HTML.
        #expect(!StudipMarkup.isHTML("Für alle n < 10 gilt:"))
        #expect(!StudipMarkup.isHTML("**Wichtig:** Bitte anmelden"))
    }

    // MARK: - Klartext

    @Test("HTML wird zu Klartext")
    func htmlZuKlartext() {
        let plain = StudipMarkup.plain(from: "<p>Vorlesung <b>Analysis I</b> f&auml;llt aus.</p>")
        #expect(plain == "Vorlesung Analysis I fällt aus.")
    }

    @Test("Entitäten werden aufgelöst")
    func entitaeten() {
        #expect(StudipMarkup.plain(from: "<p>Gr&ouml;&szlig;e &amp; Ma&szlig;</p>") == "Größe & Maß")
        #expect(StudipMarkup.plain(from: "<p>10&nbsp;&euro; &ndash; g&uuml;nstig</p>")
                == "10\u{00a0}€ – günstig")
    }

    @Test("Stud.IP-Auszeichnung verschwindet im Klartext")
    func studipAuszeichnung() {
        #expect(StudipMarkup.plain(from: "**Wichtig:** bitte anmelden") == "Wichtig: bitte anmelden")
        #expect(StudipMarkup.plain(from: "%%kursiv%% gesetzt") == "kursiv gesetzt")
    }

    @Test("Absätze werden zu Zeilen, nicht zu Brei")
    func absaetze() {
        let plain = StudipMarkup.plain(from: "<p>Erster Absatz</p><p>Zweiter Absatz</p>")
        #expect(plain == "Erster Absatz\nZweiter Absatz")
    }

    @Test("Leerer und reiner Weissraum-Text ergibt nichts")
    func leer() {
        #expect(StudipMarkup.plain(from: "") == "")
        #expect(StudipMarkup.plain(from: "   \n  ") == "")
        #expect(StudipMarkup.blocks(from: "").isEmpty)
    }

    // MARK: - Blockstruktur

    @Test("Überschriftenebenen werden umgedreht")
    func ueberschriften() {
        // HTML zählt aufsteigend (h1 ist die größte Stufe), Stud.IPs
        // Blockmodell absteigend (1 ist die kleinste). `blocks` dreht das um.
        // Ohne Test sieht man die Umkehrung erst an falsch gesetzten Titeln.
        func ebene(_ tag: String) -> Int? {
            let blocks = StudipMarkup.blocks(from: "<\(tag)>Titel</\(tag)>")
            guard case .heading(let level, _) = blocks.first else { return nil }
            return level
        }
        #expect(ebene("h1") == 4)
        #expect(ebene("h2") == 3)
        #expect(ebene("h3") == 2)
        // Ab h4 ist unten angekommen — kleiner wird es nicht.
        #expect(ebene("h4") == 1)
        #expect(ebene("h6") == 1)
    }

    @Test("Überschrift und Absatz bleiben getrennte Blöcke")
    func ueberschriftUndAbsatz() {
        let blocks = StudipMarkup.blocks(from: "<h2>Organisatorisches</h2><p>Text</p>")
        #expect(blocks.count == 2)
        guard case .heading(_, let titel) = blocks[0] else {
            Issue.record("Erster Block ist keine Überschrift: \(blocks[0])"); return
        }
        #expect(String(titel.characters) == "Organisatorisches")
        guard case .paragraph(let absatz) = blocks[1] else {
            Issue.record("Zweiter Block ist kein Absatz: \(blocks[1])"); return
        }
        #expect(String(absatz.characters) == "Text")
    }

    @Test("Listen werden zu einzelnen Einträgen")
    func listen() {
        let blocks = StudipMarkup.blocks(from: "<ul><li>Erstens</li><li>Zweitens</li></ul>")
        let eintraege = blocks.compactMap { block -> String? in
            guard case .listItem(_, _, let text) = block else { return nil }
            return String(text.characters)
        }
        #expect(eintraege == ["Erstens", "Zweitens"])
    }

    @Test("Tabellen behalten Zeilen und Spalten")
    func tabellen() {
        let html = "<table><tr><th>Tag</th><th>Zeit</th></tr><tr><td>Mo</td><td>10:15</td></tr></table>"
        let blocks = StudipMarkup.blocks(from: html)
        guard case .table(let rows, _) = blocks.first(where: { if case .table = $0 { return true }; return false }) else {
            Issue.record("Keine Tabelle gefunden in \(blocks)"); return
        }
        #expect(rows.count == 2)
        #expect(rows[0].map { String($0.characters) } == ["Tag", "Zeit"])
        #expect(rows[1].map { String($0.characters) } == ["Mo", "10:15"])
    }

    @Test("Skript- und Stilblöcke landen nicht im Text")
    func skripteRaus() {
        let plain = StudipMarkup.plain(from: "<p>Sichtbar</p><script>alert('nein')</script>")
        #expect(!plain.contains("alert"))
        #expect(plain.contains("Sichtbar"))
    }
}
