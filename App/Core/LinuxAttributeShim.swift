#if !canImport(Darwin)
import Foundation

// Diese Datei ist auf iOS leer: `canImport(Darwin)` trifft dort zu, der ganze
// Inhalt entfällt vor dem Übersetzen. Sie existiert nur, damit sich
// `StudipMarkup` ausserhalb von Xcode übersetzen und prüfen lässt.
//
// `AttributedString` gibt es auch in Linux-Foundation, die Attribute für
// Auszeichnung jedoch nicht: `inlinePresentationIntent` steuert auf Apple
// Foundation bei, `underlineStyle` und `strikethroughStyle` SwiftUI. Hier
// stehen sie als eigener Attributbereich nach — mit denselben Namen, damit
// StudipMarkup unverändert bleibt.
//
// Sie tragen bewusst keine Darstellungslogik: geprüft wird die Frage, *welche*
// Auszeichnung der Parser an welcher Stelle setzt, nicht wie sie aussieht.

public struct InlinePresentationIntent: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let emphasized = InlinePresentationIntent(rawValue: 1 << 0)
    public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 1 << 1)
    public static let code = InlinePresentationIntent(rawValue: 1 << 2)
}

/// Ersatz für `Text.LineStyle`. Nur `.single` kommt in StudipMarkup vor.
public struct ShimLineStyle: Hashable, Codable, Sendable {
    public static let single = ShimLineStyle()
}

extension AttributeScopes {
    public struct StudGoLinuxAttributes: AttributeScope {
        public let inlinePresentationIntent: IntentAttribute
        public let underlineStyle: UnderlineAttribute
        public let strikethroughStyle: StrikethroughAttribute

        public enum IntentAttribute: CodableAttributedStringKey {
            public typealias Value = InlinePresentationIntent
            public static let name = "inlinePresentationIntent"
        }
        public enum UnderlineAttribute: CodableAttributedStringKey {
            public typealias Value = ShimLineStyle
            public static let name = "underlineStyle"
        }
        public enum StrikethroughAttribute: CodableAttributedStringKey {
            public typealias Value = ShimLineStyle
            public static let name = "strikethroughStyle"
        }
    }

    public var studGoLinux: StudGoLinuxAttributes.Type { StudGoLinuxAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.StudGoLinuxAttributes, T>
    ) -> T { self[T.self] }
}
#endif
