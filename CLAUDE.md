# StudGo — Arbeitsweise

Nativer SwiftUI-Client für das Stud.IP der LUH. Entwickelt wird auf einem
Linux-Homeserver, gebaut auf Codemagic. Diese Datei beschreibt, was davon
**hier** geht und was nicht.

## Die Grundregel

SwiftUI und UIKit gibt es auf Linux nicht und wird es nie geben. Der Code ist
deshalb in zwei Hälften geteilt:

| | wo | lokal prüfbar |
| --- | --- | --- |
| **Logik** — API, Parser, Modelle | `App/Core`, `App/Models` | ja: übersetzen **und** testen |
| **Ansichten** | `App/Features` | nur Syntax, kein Typprüfen |

Vor jedem Commit, in dieser Reihenfolge:

```bash
./tools/swift-lint.sh     # ~8 s — alle 54 Dateien, volle Grammatik
./tools/swift.sh test     # ~10 s — 51 Tests gegen die Logikschicht
```

Beides zusammen fängt den Großteil dessen ab, was sonst erst nach Minuten bei
Codemagic auffällt. Was danach noch scheitert, sind Typfehler in den Ansichten
— dafür ist der CI-Lauf da.

## Werkzeuge

| Befehl | Zweck |
| --- | --- |
| `./tools/swift.sh test` | Tests von StudGoKit |
| `./tools/swift.sh build` | nur übersetzen |
| `./tools/swift.sh -- swiftc -parse <datei>` | beliebiger Toolchain-Aufruf |
| `./tools/swift-lint.sh [pfad]` | Syntaxprüfung, auch der SwiftUI-Dateien |
| `./tools/codemagic-setup.sh` | einmalig: API-Schlüssel hinterlegen |
| `./tools/codemagic.sh build` | Build anstoßen und bis zum Ende verfolgen |
| `./tools/codemagic.sh errors` | Compilerfehler des letzten Builds |
| `./tools/bootstrap-secrets.sh` | `Config/Secrets.xcconfig` aus `.env` |

Die Toolchain läuft im Container (`swift:6.2-noble`); auf dem Host ist kein
Swift installiert und soll auch keiner hin. `SWIFT_IMAGE=…` schaltet um.

## StudGoKit ist eine Linse, kein zweites Zuhause

`Package.swift` übersetzt die Dateien **dort, wo sie liegen** — nichts wurde
nach `Sources/` verschoben, `project.yml` ist unberührt, Xcode baut die App
unverändert.

Das ist Absicht: eine echte Abspaltung in ein Modul verlangte, jeden von den
Ansichten benutzten Typ `public` zu machen. Ob das gelingt, liesse sich hier
nicht prüfen — man merkte den Bruch erst bei Codemagic, also genau dort, wo
dieser Aufbau Läufe sparen soll.

**Neue Datei in `App/Core` oder `App/Models`?** In `Package.swift` entweder
unter `sources` aufnehmen (wenn sie ohne Apple-Frameworks auskommt) oder unter
`exclude`. Fehlt sie in beiden Listen, warnt SwiftPM.

Draussen bleiben und warum:

| Datei | Grund |
| --- | --- |
| `AuthStore`, `KeychainStore` | Security (Schlüsselbund) |
| `Notifications`, `BackgroundSync` | UserNotifications, BackgroundTasks |
| `OAuthService` | AuthenticationServices |
| `Preferences`, `Theme`, `DesignSystem`, `WebSheet`, `QuickLookPreview` | SwiftUI/UIKit |

## Zwei Stellen, an denen Linux nachhilft

Beide sind auf iOS wirkungslos — dort greift der jeweils andere Zweig.

- **`App/Core/LinuxAttributeShim.swift`** — die ganze Datei steht in
  `#if !canImport(Darwin)`. Sie nennt `inlinePresentationIntent`,
  `underlineStyle` und `strikethroughStyle` nach, die auf Apple-Systemen von
  Foundation und SwiftUI kommen. Ohne sie liesse sich `StudipMarkup` hier
  nicht übersetzen.
- **`import`-Weichen** in `StudipMarkup` (SwiftUI), `StudIPClient*`
  (FoundationNetworking) und `PKCE`/`ResponseCache` (CryptoKit → swift-crypto).

Kommt in einer Datei aus der Linse ein neues Apple-Framework dazu, scheitert
`./tools/swift.sh build`. Das ist die Schutzwirkung, nicht der Defekt: dann
entweder eine Weiche setzen oder die Datei aus dem Paket nehmen.

## Tests

`Tests/StudGoKitTests/` — swift-testing (`@Test`, `#expect`), 51 Stück.
Schwerpunkt liegt auf dem, was still falsch sein kann: ICS-Zeitzonen,
JSON:API-Eigenheiten von Stud.IP, HTML-Entitäten, PKCE.

Zwei Regeln aus der Erfahrung:

1. **Kalender und Zeitzone immer als Parameter setzen**, nie `.current`
   erwarten. `tools/swift.sh` setzt `TZ=Europe/Berlin`, aber ein Test, der
   das braucht, ist ein zerbrechlicher Test.
2. **Schlägt ein neuer Test an, erst prüfen, wessen Erwartung falsch ist.**
   Die Überschriftenebenen in `HTMLReader` sind absichtlich umgedreht
   (1 = kleinste Stufe) — das sah zuerst nach einem Fehler aus.

## Codemagic

Zwei Workflows in `codemagic.yaml`:

- **`check`** — bei jedem Push. Lint → StudGoKit-Tests → Simulator-Build ohne
  Signatur. Braucht kein Apple-Konto.
- **`testflight`** — nur bei Tags `v*`. Baut, signiert, lädt hoch. Meldet
  **nicht** zur Prüfung an (`submit_to_testflight` bleibt aus — siehe die
  Begründung in der Datei; ein laufendes App-Store-Review darf das nicht
  stören).

Mit hinterlegtem Schlüssel läuft die Schleife ohne Weboberfläche:

```bash
git push && ./tools/codemagic.sh build     # stößt an, wartet, zeigt Fehler
./tools/codemagic.sh errors                # Compilerfehler des letzten Laufs
```

## Offene Punkte

- `App/Core/PKCE.swift` verwirft den Rückgabewert von `SecRandomCopyBytes`.
  Schlüge der Aufruf fehl, bestünde der Verifier aus Nullbytes und der
  PKCE-Schutz wäre wirkungslos, ohne dass es auffiele. Wie zu reagieren ist
  (Abbruch? Wiederholung?), ist eine offene Entscheidung — `TODO` steht dort.
- `./tools/codemagic.sh` ist gegen die Codemagic-API geschrieben, aber noch
  nie mit einem echten Schlüssel gelaufen. Erster Lauf mit wachem Auge.
