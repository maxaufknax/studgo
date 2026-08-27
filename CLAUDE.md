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
./tools/swift-lint.sh     # ~8 s — alle 57 Dateien, volle Grammatik
./tools/swift.sh test     # ~10 s — 91 Tests gegen die Logikschicht
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

`Tests/StudGoKitTests/` — swift-testing (`@Test`, `#expect`), 91 Stück.
Schwerpunkt liegt auf dem, was still falsch sein kann: ICS-Zeitzonen,
JSON:API-Eigenheiten von Stud.IP, HTML-Entitäten, PKCE, das Ausrollen des
Wochenplans zu datierten Terminen.

Zwei Regeln aus der Erfahrung:

1. **Zeitzone nie voraussetzen.** `tools/swift.sh` setzt `TZ=Europe/Berlin`,
   der Codemagic-Läufer steht unter **UTC** — ein Test, der die eine oder die
   andere braucht, läuft hier durch und fällt dort um. Zwei Wege, je nachdem
   was geprüft wird:
   * Der Prüfling nimmt einen Kalender entgegen (`Weekday.of(_:in:)`,
     `SemesterContext`)? Dann einen festen mitgeben.
   * Der Prüfling rechnet mit `Calendar.current` (`EventMerge`)? Dann die
     Erwartungswerte **ebenfalls** in `Calendar.current` bauen. Ein in
     Europe/Berlin gebauter Montag 00:00 ist unter UTC der Sonntag davor —
     genau daran sind die ersten `EventMergeTests` gescheitert.
2. **Schlägt ein neuer Test an, erst prüfen, wessen Erwartung falsch ist.**
   Die Überschriftenebenen in `HTMLReader` sind absichtlich umgedreht
   (1 = kleinste Stufe) — das sah zuerst nach einem Fehler aus.

## Codemagic

Zwei Workflows in `codemagic.yaml`:

- **`check`** — bei jedem Push. Lint → StudGoKit-Tests → Simulator-Build ohne
  Signatur. Braucht kein Apple-Konto.

  Der Testschritt endet auf `| tail -40` und **braucht deshalb `pipefail`** —
  ohne ihn ist der Rückgabewert der von `tail`, also immer 0, und
  fehlgeschlagene Tests melden Erfolg. Wer hier eine Pipeline anfügt: daran
  denken.
- **`testflight`** — nur bei Tags `v*`. Baut, signiert, lädt hoch. Meldet
  **nicht** zur Prüfung an (`submit_to_testflight` bleibt aus — siehe die
  Begründung in der Datei; ein laufendes App-Store-Review darf das nicht
  stören).

Mit hinterlegtem Schlüssel läuft die Schleife ohne Weboberfläche:

```bash
git push && ./tools/codemagic.sh build     # stößt an, wartet, zeigt Fehler
./tools/codemagic.sh errors                # Compilerfehler des letzten Laufs
```

## Demo-Modus

Seit 1.5.0 gibt es einen zweiten Betriebszustand: `AuthStore.isDemo`. Er
schaltet in `StudIPClient` **nur den Transport** ab — `get`, `text`, `send`,
`download` und `upload` fragen dann `DemoServer` statt das Netz. Alles danach
ist derselbe Code.

| Datei | Rolle |
| --- | --- |
| `App/Core/DemoData.swift` | das erfundene Konto — Personen, Kurse, Stundenplan, Nachrichten … |
| `App/Core/DemoServer.swift` | baut daraus JSON:API-Antworten und den ICS-Strom |
| `App/Core/DemoStore.swift` | was in der Demo geschrieben wird (nur im Arbeitsspeicher) |

Zwei Dinge daran sind wichtiger, als sie aussehen:

1. **Es ist der einzige Prüfstand, der hier läuft.** `DemoServerTests` geht
   den Weg Antwort → `JSONAPIDocument` → Modell für jede Route durch, auf
   Linux, in Sekunden. Wer eine neue Route in `StudIPClient` aufnimmt, nimmt
   sie am besten gleich in `DemoServer` mit auf — dann ist sie geprüft.
2. **Die Termine entstehen relativ zu heute**, und das Demo-Semester ist so
   gelegt, dass der heutige Tag in seiner Vorlesungszeit liegt. Ohne das
   zeigte die Demo in der vorlesungsfreien Zeit ein zu Recht blasses, leeres
   Raster — richtig, aber als erster Eindruck unbrauchbar.

Die Suite ist `.serialized`: Die schreibenden Prüfungen teilen sich
`DemoStore.shared`.

## Offene Punkte

- `App/Core/PKCE.swift` verwirft den Rückgabewert von `SecRandomCopyBytes`.
  Schlüge der Aufruf fehl, bestünde der Verifier aus Nullbytes und der
  PKCE-Schutz wäre wirkungslos, ohne dass es auffiele. Wie zu reagieren ist
  (Abbruch? Wiederholung?), ist eine offene Entscheidung — `TODO` steht dort.
- Der leere Blubber-Verlauf aus 1.3.0 liess sich von hier aus **nicht**
  nachstellen: Ohne Token gibt die LUH-API auf jede Route 401, und der
  `login --cookie`-Weg von `tools/studip-cli.py` verlangt eine Browsersitzung.
  1.4.0 geht deshalb über drei Wege gleichzeitig an den Verlauf und führt
  eine Spur mit, welche Route was geantwortet hat
  (`BlubberConversation.trail`, sichtbar in der App unter „Warum ist hier
  nichts?"). Bleibt ein Faden im Testflug leer, steht die Ursache dort —
  das ist die eigentliche Rückmeldung, auf die 1.4.0 wartet.
