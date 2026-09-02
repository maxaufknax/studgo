# StudGo

Native iOS-App für **Stud.IP**, eingerichtet auf die Installation unter
`studip.uni-hannover.de`. Kein eigenes Backend: Die App spricht direkt mit
diesem Server, Zugangstoken liegen ausschließlich in der Keychain des Geräts.

Quelloffenes Studierendenprojekt, keine offizielle App der Universität.

## Funktionen

| Bereich | Inhalt |
| --- | --- |
| **Heute** | Was gerade läuft oder als Nächstes ansteht, mit Countdown; der restliche Tag, die nächsten Termine, ungelesene Nachrichten, neue Ankündigungen |
| **Plan** | Tag, Woche und Liste: Wochenraster mit Kursfarben und Überschneidungen, Tagesansicht mit Datumsleiste, datierte Terminliste. Eigene Termine gelten ganzjährig; anlegen und ändern führt an die richtige Stelle in Stud.IP |
| **Kurse** | Veranstaltungen des laufenden Semesters (umschaltbar) mit Suche; je Kurs Info, Termine, Aushang, Dateien und Teilnehmende |
| **Dateien** | Ordner durchblättern, herunterladen, in der Systemvorschau öffnen und teilen |
| **Postfach** | Nachrichten (Posteingang, Gesendet, Suche, Antworten, Verfassen mit Personensuche) und **Blubber**: globaler Strom, Direktnachrichten und die Ströme der Veranstaltungen und Studiengruppen in einer Liste |
| **Campus** | Eigene Zahlen, Aktivitätenstrom, Verzeichnis: Veranstaltungs- und Personensuche, Kontakte, Studiengruppen, Einrichtungen, Ankündigungen |
| **Profil** | Darstellung, Benachrichtigungen, Semesterübersicht, Uni-Mail, Zwischenspeicher, Datenschutzhinweise, Abmelden |

Anmeldung über **OAuth2 Authorization Code Flow mit PKCE** in einer
`ASWebAuthenticationSession` — das Passwort sieht die App nie.

### Ohne Konto: der Demo-Modus

Die Anmeldung führt über Shibboleth; ohne Uni-Kennung kommt man dort nicht
durch. Auf dem Anmeldebildschirm führt deshalb
**„Demo ohne Anmeldung ansehen"** in eine vollständige Fassung der App mit
erfundenen Beispieldaten — ohne Konto, ohne Netzverbindung.

Technisch ist das kein zweiter Bildschirmsatz: `AuthStore.isDemo` schaltet in
`StudIPClient` allein den Transport ab, `DemoServer` liefert stattdessen
JSON:API-Antworten und einen ICS-Strom mit denselben Feldnamen wie Stud.IP.
Parser, Modelle und Ansichten laufen unverändert — weshalb `DemoServerTests`
den ganzen Weg von der Antwort bis ins Modell auf Linux prüfen kann.

Jede Veranstaltung bekommt eine aus ihrer ID abgeleitete Farbe, die in
Stundenplan, Terminliste und Kursliste dieselbe ist.

### Ohne Empfang

Antworten der API landen in einem Zwischenspeicher auf dem Gerät
(`App/Core/ResponseCache.swift`). Die App startet damit sofort mit dem letzten
Stand statt mit fünf Ladekreiseln, und in der Bahn ohne Netz bleibt sie
benutzbar. „Nach unten ziehen" fragt immer den Server. Beim Abmelden wird der
Zwischenspeicher mit den Tokens zusammen gelöscht.

## Aufbau

```
App/Core        OAuth2, Keychain, JSON:API-Transport, Zwischenspeicher,
                Farb- und Formsprache, Formatierung
App/Models      Domänenmodelle (Attributnamen aus den Stud.IP-6.0-Schemas)
App/Features    SwiftUI-Ansichten
App/Resources   Assets, Datenschutzmanifest
docs/           API-Befunde, Codemagic-Anleitung, Schriftverkehr mit der ZQS
tools/          Swift-Toolchain im Container, Lint, Codemagic-CLI, Secrets
Tests/          Tests der Logikschicht (swift-testing)
PRIVACY.md      Datenschutzerklärung (Adresse im App Store)
SUPPORT.md      Hilfeseite (Adresse im App Store)
```

Entwickelt wird unter Linux, gebaut auf Codemagic. SwiftUI gibt es hier nicht,
die Logikschicht dagegen kommt ohne Apple-Frameworks aus und lässt sich deshalb
lokal übersetzen und testen — die Swift-Toolchain läuft dafür im Container.

```bash
./tools/swift-lint.sh     # ~8 s — Syntax aller Quellen, auch der Ansichten
./tools/swift.sh test     # ~10 s — 91 Tests gegen App/Core und App/Models
```

Beides zusammen fängt ab, was sonst erst nach Minuten bei Codemagic auffiele.
Einzelheiten in [CLAUDE.md](CLAUDE.md).

## Bauen

Das Xcode-Projekt wird per [XcodeGen](https://github.com/yonaskolb/XcodeGen)
erzeugt, damit keine binäre `.xcodeproj` im Repo liegt.

```bash
./tools/bootstrap-secrets.sh   # Config/Secrets.xcconfig aus .env erzeugen
xcodegen generate
open StudGo.xcodeproj
```

**Ohne Mac**: Die Pipeline in `codemagic.yaml` baut und lädt nach TestFlight
hoch — Einrichtung in [docs/CODEMAGIC.md](docs/CODEMAGIC.md).

`.env` und `Config/Secrets.xcconfig` sind bewusst nicht eingecheckt;
`Config/Secrets.example.xcconfig` zeigt das Format.

## API erkunden

```bash
./tools/studip-cli.py login          # PKCE-Flow im Browser, Token holen
./tools/studip-cli.py whoami
./tools/studip-cli.py get /v1/users/me
```

Alle verifizierten Endpunkte, Attributnamen und Fehlerformate stehen in
[docs/API-NOTES.md](docs/API-NOTES.md).

## Offener Punkt: Client-Typ

Der OAuth-Client ist als *confidential client* registriert — der
Token-Endpunkt verlangt zwingend das `client_secret`. Für eine App ohne Backend
gehört der Client auf *public* (PKCE-only) umgestellt; eine entsprechende
Anfrage liegt beim E-Learning-Service der ZQS.

Bis dahin wird das Secret über `Config/Secrets.xcconfig` ins Bundle gereicht.
Sobald der Client umgestellt ist, entfällt der Wert ersatzlos —
`AppConfig.clientSecret` ist bereits optional, PKCE läuft ohnehin immer mit.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
