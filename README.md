# StudGo

Native iOS-App für **Stud.IP an der Leibniz Universität Hannover**.
Kein eigenes Backend: Die App spricht direkt mit `studip.uni-hannover.de`,
Zugangstoken liegen ausschließlich in der Keychain des Geräts.

Quelloffenes Studierendenprojekt, keine offizielle App der Universität.

## Funktionen

| Bereich | Inhalt |
| --- | --- |
| **Heute** | Termine des Tages, die nächsten Veranstaltungen, ungelesene Nachrichten, neue Ankündigungen |
| **Plan** | Stundenplan als Woche und als datierte Terminliste |
| **Kurse** | Veranstaltungen mit Suche; je Kurs Info, Termine, Aushang, Dateien und Teilnehmende |
| **Dateien** | Ordner durchblättern, herunterladen, in der Systemvorschau öffnen und teilen |
| **Nachrichten** | Posteingang und Gesendet, Volltextsuche, Lesen, Antworten, Verfassen mit Personensuche |
| **Mehr** | Profil, Ankündigungen der Uni, Semesterübersicht, Datenschutzhinweise, Abmelden |

Anmeldung über **OAuth2 Authorization Code Flow mit PKCE** in einer
`ASWebAuthenticationSession` — das Passwort sieht die App nie.

## Aufbau

```
App/Core        OAuth2, Keychain, JSON:API-Transport, Formatierung
App/Models      Domänenmodelle (Attributnamen aus den Stud.IP-6.0-Schemas)
App/Features    SwiftUI-Ansichten
App/Resources   Assets, Datenschutzmanifest
docs/           API-Befunde, Codemagic-Anleitung, Schriftverkehr mit der ZQS
tools/          Dev-CLI, Icon-Generator, Secrets-Bootstrap
```

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

Der OAuth-Client der LUH ist als *confidential client* registriert — der
Token-Endpunkt verlangt zwingend das `client_secret`. Für eine App ohne Backend
gehört der Client auf *public* (PKCE-only) umgestellt; eine entsprechende
Anfrage liegt beim E-Learning-Service der ZQS.

Bis dahin wird das Secret über `Config/Secrets.xcconfig` ins Bundle gereicht.
Sobald der Client umgestellt ist, entfällt der Wert ersatzlos —
`AppConfig.clientSecret` ist bereits optional, PKCE läuft ohnehin immer mit.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
