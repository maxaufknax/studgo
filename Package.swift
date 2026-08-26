// swift-tools-version: 6.0
import PackageDescription

// StudGoKit ist kein zweites Zuhause für den Code, sondern eine Linse auf ihn:
// Das Ziel übersetzt die Dateien dort, wo sie liegen — in App/Core und
// App/Models. Nichts wird verschoben, project.yml bleibt unberührt, und
// Xcode baut die App weiterhin genau wie vorher.
//
// Der Grund für diesen Zuschnitt statt einer echten Abspaltung: SwiftUI gibt
// es auf Linux nicht, ein Umbau auf ein eigenes Modul liesse sich hier also
// nicht zu Ende prüfen — man merkte den Bruch erst bei Codemagic, also genau
// dort, wo dieser Aufbau Läufe sparen soll. Die Linse bringt denselben Nutzen
// (übersetzen und testen in Sekunden) ohne dieses Risiko.
//
// Aufgenommen wird, was ohne Apple-Frameworks auskommt. Bekommt eine dieser
// Dateien später ein `import SwiftUI`, scheitert `./tools/swift.sh build` —
// das ist beabsichtigt und die eigentliche Schutzwirkung.
let package = Package(
    name: "StudGoKit",
    // Auf Linux wirkungslos, auf Codemagic entscheidend: ohne Angabe
    // baut SwiftPM gegen eine sehr alte macOS-Fassung, und Aufrufe wie
    // `URL.host()` (ab macOS 13) sind dort nicht verfügbar.
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        // Ersetzt CryptoKit ausserhalb von Apple-Systemen.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "StudGoKit",
            dependencies: [
                // Nur ausserhalb von Apple gebraucht: dort steht CryptoKit
                // im System. Ohne diese Bedingung bauten macOS-Läufe auf
                // Codemagic swift-crypto samt BoringSSL mit, ohne es je
                // zu benutzen — mehrere Minuten für nichts.
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ],
            path: "App",
            exclude: [
                "Features/",
                "Resources/",
                "StudGoApp.swift",
                "Core/AuthStore.swift",
                "Core/BackgroundSync.swift",
                "Core/DesignSystem.swift",
                "Core/KeychainStore.swift",
                "Core/Notifications.swift",
                "Core/OAuthService.swift",
                "Core/Preferences.swift",
                "Core/QuickLookPreview.swift",
                "Core/Theme.swift",
                "Core/WebSheet.swift",
            ],
            sources: [
                "Core/AppConfig.swift",
                "Core/EventMerge.swift",
                "Core/Formatting.swift",
                "Core/HTMLReader.swift",
                "Core/ICSParser.swift",
                "Core/JSONAPI.swift",
                "Core/PKCE.swift",
                "Core/LinuxAttributeShim.swift",
                "Core/ResponseCache.swift",
                "Core/SchedulePlan.swift",
                "Core/SemesterContext.swift",
                "Core/StudIPClient.swift",
                "Core/StudIPClient+Blubber.swift",
                "Core/StudIPClient+Campus.swift",
                "Core/StudIPClient+Files.swift",
                "Core/StudIPErrorPage.swift",
                "Core/StudipMarkup.swift",
                "Core/TokenSet.swift",
                "Core/Weekday.swift",
                "Core/WebLinks.swift",
                "Models/CampusModels.swift",
                "Models/Models.swift",
            ],
            // Wie in project.yml (SWIFT_VERSION 5.0): derselbe Sprachmodus,
            // sonst meldet SwiftPM Nebenläufigkeitsfehler, die Xcode nie sieht.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StudGoKitTests",
            dependencies: [
                "StudGoKit",
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ],
            path: "Tests/StudGoKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
