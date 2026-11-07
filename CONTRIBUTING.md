# Mitarbeiten

Fehlerberichte und Pull Requests sind willkommen. StudGo ist ein kleines
Projekt mit klaren Meinungen - je kürzer und je näher am Stil der App eine
Änderung ist, desto schneller landet sie.

## Die Regeln des Stacks, mit Absicht

- Eine native SwiftUI-App, kein eigenes Backend: Die App spricht direkt mit
  `studip.uni-hannover.de`. Alles, was einen Server zwischen App und Stud.IP
  schaltet, ist hier fehl am Platz.
- Abhängigkeiten sind ein Kostenpunkt. Eine neue Package sollte begründen,
  warum der Standard sie nicht ersetzen kann.
- Texte in der App reden mit einer Person, nicht mit einem Konfigurationsmenü:
  keine Ausrufezeichen, keine Marketingsprache, keine Emoji.
- UI und Logik sind getrennt: Die Logikschicht kommt ohne Apple-Frameworks aus
  und läuft deshalb unter Linux im Container - so bleibt sie testbar.

## Vor dem Pull Request laufen lassen

```bash
./tools/swift-lint.sh     # ~8 s  Syntax aller Quellen, auch Ansichten und Widgets
./tools/swift.sh test     # ~10 s Tests der Logikschicht und der Übersetzungen
```

Beides zusammen fängt ab, was sonst erst Minuten später bei Codemagic auffiele.
Wer darf: `./tools/bootstrap-secrets.sh` erzeugt `Config/Secrets.xcconfig` aus
`.env` (Format: `Config/Secrets.example.xcconfig`), `xcodegen generate` baut
das Projekt.

## Was ein Pull Request erzählen sollte

Ein kurzer Absatz, was sich ändert und welche Situation es nötig gemacht hat -
und wie du es geprüft hast: Welche Tests liefen, was hast du von Hand am
Bildschirm nachgesehen? "Sah richtig aus" ist keine Prüfung.

## Wo was liegt

| Pfad | |
| --- | --- |
| `App/Core` | OAuth2, Keychain, JSON:API-Transport, Zwischenspeicher |
| `App/Models` | Domänenmodelle aus den Stud.IP-6.0-Schemas |
| `App/Features` | SwiftUI-Ansichten |
| `Widgets/` | WidgetKit-Erweiterung für Home- und Sperrbildschirm |
| `docs/` | API-Befunde, Funktionsumfang, Sicherheitsprüfung, Codemagic |
| `tools/` | Swift-Toolchain im Container, Lint, Stud.IP-CLI |
| `Tests/` | Tests der Logikschicht (swift-testing) |

Sicherheitsbedenken gehören zu [SECURITY.md](SECURITY.md), nicht in ein
öffentliches Issue. Hilfe zum Umgang mit der App steht in
[SUPPORT.md](SUPPORT.md).
