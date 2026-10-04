# StudGo

Native iOS-App für **Stud.IP**, eingerichtet auf die Installation unter
`studip.uni-hannover.de`. Kein eigenes Backend: Die App spricht direkt mit
diesem Server, Zugangstoken liegen ausschließlich in der Keychain des Geräts.

Quelloffenes Studierendenprojekt, keine offizielle App der Universität.
Website: [studgo.de](https://studgo.de) · [App Store](https://apps.apple.com/de/app/studgo/id6804845342)

## Funktionen

| Bereich | Inhalt |
| --- | --- |
| **Heute** | Was gerade läuft oder als Nächstes ansteht, mit Countdown; der restliche Tag, die wirklich nächsten Termine - nach Tagen gruppiert, auch mehrere am selben Tag -, ungelesene Nachrichten, neue Ankündigungen; Feiertage stehen am Datum |
| **Plan** | Tag, Woche und Liste: Wochenraster mit Kursfarben und Überschneidungen, Tagesansicht mit Datumsleiste, datierte Terminliste; Feiertage (Niedersachsen) stehen in Tages- und Listenansicht. Eigene Termine gelten ganzjährig; anlegen und ändern führt an die richtige Stelle in Stud.IP. Einzelne Turnusfenster - etwa die Übungsgruppe, die nicht die eigene ist - lassen sich überall ausblenden und in den Einstellungen wiederfinden |
| **Kurse** | Veranstaltungen des laufenden Semesters (umschaltbar) mit Suche; je Kurs Info, Termine, Aushang, Dateien, Teilnehmende und Courseware |
| **Dateien** | Ordner durchblättern, herunterladen, in der Systemvorschau öffnen und teilen |
| **Postfach** | Nachrichten (Posteingang, Gesendet, Suche, Antworten, Verfassen mit Personensuche, Löschen) und **Blubber**: globaler Strom, Direktnachrichten und die Ströme der Veranstaltungen und Studiengruppen in einer Liste; Antippen einer Person öffnet ihr Profil |
| **Campus** | Eigene Zahlen, Aktivitätenstrom, Verzeichnis: Veranstaltungs- und Personensuche, Kontakte, Studiengruppen, Einrichtungen, Ankündigungen, Mensa & Speisepläne (über OpenMensa) - mit Tag- und Wochenansicht und einem Detailblatt je Gericht |
| **Widgets** | Nächster Termin und ungelesene Nachrichten auf Home- und Sperrbildschirm (klein, mittel mit „Danach“, rechteckig, rund, in der Zeile); nach dem Ende eines Termins springt das Widget selbst zum nächsten; antippen führt in den Reiter |
| **Kalender** | Auf Wunsch die nächsten acht Wochen in einem eigenen iOS-Kalender „StudGo“ - damit auch auf Apple Watch, in CarPlay und bei Siri; Stundenplan als Bild teilen |
| **Profil** | Darstellung, Benachrichtigungen, Kalender-Abgleich, Semesterübersicht, Uni-Mail, Zwischenspeicher, Einführung, Datenschutzhinweise, Abmelden |

Die Oberfläche gibt es auf **Deutsch und Englisch** (Gerätesprache); die
Schrift folgt der eingestellten Textgröße. Nach der ersten Anmeldung führt
eine kurze Einführung durch Reiter, Widgets und Erinnerungen.

Anmeldung über **OAuth2 Authorization Code Flow mit PKCE** in einer
`ASWebAuthenticationSession` - das Passwort sieht die App nie.

### Ohne Konto: der Demo-Modus

Die Anmeldung führt über Shibboleth; ohne Uni-Kennung kommt man dort nicht
durch. Auf dem Anmeldebildschirm führt deshalb
**„Demo ohne Anmeldung ansehen"** in eine vollständige Fassung der App mit
erfundenen Beispieldaten - ohne Konto, ohne Netzverbindung.

Technisch ist das kein zweiter Bildschirmsatz: `AuthStore.isDemo` schaltet in
`StudIPClient` allein den Transport ab, `DemoServer` liefert stattdessen
JSON:API-Antworten und einen ICS-Strom mit denselben Feldnamen wie Stud.IP.
Parser, Modelle und Ansichten laufen unverändert - weshalb `DemoServerTests`
den ganzen Weg von der Antwort bis ins Modell auf Linux prüfen kann.

Jede Veranstaltung bekommt eine aus ihrer ID abgeleitete Farbe, die in
Stundenplan, Terminliste und Kursliste dieselbe ist.

### Ohne Empfang

Antworten der API landen in einem Zwischenspeicher auf dem Gerät
(`App/Core/ResponseCache.swift`). Die App startet damit sofort mit dem letzten
Stand statt mit fünf Ladekreiseln, und in der Bahn ohne Netz bleibt sie
benutzbar - gilt seit 1.8.0 auch für den Speiseplan: Ohne Empfang zählt dort
jetzt derselbe alte Stand wie beim Stud.IP-Zugriff, statt mit „nicht geladen“
abzubrechen. Seit 1.8.2 gilt dasselbe, wenn Stud.IP selbst nicht kann
(Überlast, Wartung: 429, 502-504): Der gespeicherte Stand steht da, und die
Sitzung bleibt bestehen. Abgemeldet wird nur, wenn Stud.IP den Token
ausdrücklich zurückweist. „Nach unten ziehen" fragt immer den Server. Beim Abmelden wird der
Zwischenspeicher mit den Tokens zusammen gelöscht - und die Widgets verlieren
ihren Schnappschuss, denn der könnte Termine des alten Kontos tragen.

## Aufbau

```
App/Core        OAuth2, Keychain, JSON:API-Transport, Zwischenspeicher,
                Farb- und Formsprache, Formatierung
App/Models      Domänenmodelle (Attributnamen aus den Stud.IP-6.0-Schemas)
App/Features    SwiftUI-Ansichten
App/Resources   Assets, Datenschutzmanifest, Übersetzungen (de.lproj, en.lproj)
Widgets/        WidgetKit-Erweiterung (Home- und Sperrbildschirm)
docs/           API-Befunde, Funktionsumfang, Codemagic-Anleitung
tools/          Swift-Toolchain im Container, Lint, Codemagic-CLI, Secrets
Tests/          Tests der Logikschicht (swift-testing)
PRIVACY.md      Datenschutzerklärung (Adresse im App Store)
SUPPORT.md      Hilfeseite (Adresse im App Store)
```

Entwickelt wird unter Linux, gebaut auf Codemagic. SwiftUI gibt es hier nicht,
die Logikschicht dagegen kommt ohne Apple-Frameworks aus und lässt sich deshalb
lokal übersetzen und testen - die Swift-Toolchain läuft dafür im Container.

```bash
./tools/swift-lint.sh     # ~8 s - Syntax aller Quellen, auch der Ansichten und Widgets
./tools/swift.sh test     # ~10 s - 194 Tests gegen App/Core, App/Models und die Übersetzungen
```

Beides zusammen fängt ab, was sonst erst nach Minuten bei Codemagic auffiele.

## Bauen

Das Xcode-Projekt wird per [XcodeGen](https://github.com/yonaskolb/XcodeGen)
erzeugt, damit keine binäre `.xcodeproj` im Repo liegt.

```bash
./tools/bootstrap-secrets.sh   # Config/Secrets.xcconfig aus .env erzeugen
xcodegen generate
open StudGo.xcodeproj
```

**Ohne Mac**: Die Pipeline in `codemagic.yaml` baut und lädt nach TestFlight
hoch - Einrichtung in [docs/CODEMAGIC.md](docs/CODEMAGIC.md).

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

## Client-Typ

Der OAuth-Client ist als *public client* registriert (Client 17, von der ZQS
am 24. September 2026 eingerichtet): Der Token-Endpunkt verlangt kein
`client_secret`, PKCE trägt den Anmeldeflow allein (RFC 8252). Der Vorgänger
Client 15 war *confidential* und ist ausgelaufen - Nutzer mit einer unter
Client 15 begonnenen Sitzung melden sich einmal neu an.

## Lizenz

MIT - siehe [LICENSE](LICENSE).
