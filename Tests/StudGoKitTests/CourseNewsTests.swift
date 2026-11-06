import Foundation
import Testing
@testable import StudGoKit

/// „Neu in deinen Kursen“ - Auswahl und Formulierung, rein geprüft.
///
/// Dieselbe Logik entscheidet, was auf „Heute“ steht und was die
/// Sammelmitteilung im Hintergrund sagt. Wichtigste Eigenschaft: Nur
/// Dateien, Forum, Wiki und Ankündigungen - der Strom enthält auch
/// Termine und Beigetrete, aber die stehen ohnehin woanders, und eine
/// Mitteilung darüber wäre Lärm.
@Suite("Neu in deinen Kursen")
struct CourseNewsTests {

    private func item(id: String, type: String?, hoursAgo: Double,
                      courseID: String? = "kurs1") -> ActivityItem {
        var attrs = "\"title\": \"Beispiel zu \(id)\", \"content\": \"\", \"verb\": \"created\","
        if let type { attrs += "\"activity-type\": \"\(type)\"," }
        attrs += "\"mkdate\": \"\(Self.stamp(hoursAgo))\""
        let relationships = courseID.map {
            "\"context\": {\"data\": {\"type\": \"courses\", \"id\": \"\($0)\"}}"
        } ?? ""
        let json = """
        {"data": {"type": "activities", "id": "\(id)",
                  "attributes": {\(attrs)},
                  "relationships": {\(relationships)}}}
        """
        let doc = try! JSONAPIDocument(data: Data(json.utf8))
        return ActivityItem(try! doc.first!, actor: nil, context: nil, object: nil)!
    }

    private static func stamp(_ hoursAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date().addingTimeInterval(-hoursAgo * 3600))
    }

    @Test("Nur Dateien, Forum, Wiki und Ankündigungen gelten als neu")
    func nurKursinhalte() {
        let since = Date().addingTimeInterval(-48 * 3600)
        let items = [item(id: "a", type: "documents", hoursAgo: 2),
                     item(id: "b", type: "forum", hoursAgo: 3),
                     item(id: "c", type: "wiki", hoursAgo: 5),
                     item(id: "d", type: "news", hoursAgo: 9),
                     item(id: "e", type: "schedule", hoursAgo: 1),
                     item(id: "f", type: "participants", hoursAgo: 1),
                     item(id: "g", type: nil, hoursAgo: 1)]
        let fresh = CourseNews.fresh(items, since: since)
        #expect(fresh.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test("Nur was seit dem letzten Besuch passiert ist")
    func seitDemBesuch() {
        let visit = Date().addingTimeInterval(-6 * 3600)
        let items = [item(id: "neu", type: "news", hoursAgo: 2),
                     item(id: "alt", type: "news", hoursAgo: 12)]
        let fresh = CourseNews.fresh(items, since: visit)
        #expect(fresh.map(\.id) == ["neu"])
    }

    @Test("Die Liste bleibt in ihrem Rahmen")
    func begrenzt() {
        let since = Date().addingTimeInterval(-48 * 3600)
        let many = (0..<20).map { item(id: "i\($0)", type: "documents", hoursAgo: 1) }
        #expect(CourseNews.fresh(many, since: since, limit: 6).count == 6)
    }

    @Test("Stumme Kurse verschwinden, Kursloses bleibt")
    func stummschaltung() {
        let items = [item(id: "a", type: "news", hoursAgo: 1, courseID: "kurs1"),
                     item(id: "b", type: "news", hoursAgo: 2, courseID: "kurs2"),
                     item(id: "c", type: "news", hoursAgo: 3, courseID: nil)]
        let unmuted = CourseNews.unmuted(items, muted: ["kurs1"])
        #expect(unmuted.map(\.id) == ["b", "c"])
        #expect(CourseNews.unmuted(items, muted: []).count == 3)
    }

    @Test("Ohne Neues gibt es keine Mitteilung")
    func ohneNeuesKeineMitteilung() {
        #expect(CourseNews.summary(for: []) == nil)
    }

    @Test("Eine Sammelmitteilung statt einer Flut")
    func sammelmitteilung() {
        let items = (0..<12).map {
            item(id: "i\($0)", type: "documents", hoursAgo: Double($0) + 1)
        }
        let summary = CourseNews.summary(for: items)!
        #expect(summary.title.contains("12"))
        // Drei Zeilen Rumpf, nicht zwölf.
        #expect(summary.body.split(separator: "\n").count == 3)
    }

    @Test("Eine einzige Neuigkeit trägt ihren eigenen Satz")
    func eineNeuigkeit() {
        let summary = CourseNews.summary(for: [item(id: "a", type: "news", hoursAgo: 1)])!
        #expect(summary.title == "Neu in deinen Kursen")
        #expect(summary.body.contains("Beispiel zu a"))
    }
}
