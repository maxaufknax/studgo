# Sicherheitsprüfung StudGo 1.9.0

Stand: **2026-11-06**, Fassung 1.9.0. Dieses Dokument hält fest, wie StudGo
Anmeldung, Tokens und Daten auf dem Gerät behandelt - verständlich genug,
dass Anmeldung und Token-Speicherung auch ohne Quelltextkenntnis
nachvollziehbar sind.

Die Prüfung fand am Quelltext statt, nicht am Live-System: Auf dem Server
liegt kein Anmelde-Token, deshalb wurde der OAuth-Ablauf gegen den echten
Stud.IP-Server **nie** vollständig durchlaufen (siehe „Offene Punkte“).
Aussagen über den Server beruhen auf dem Stud.IP-6.0-Quelltext und der
unverbindlich abrufbaren Schnittstellen-Beschreibung (`/studip/properties`,
derzeit Version 6.0.6).

---

## Bedrohungsmodell

Wer könnte was wollen, und was hält StudGo dagegen?

| Perspektive | Ziel | Haltung |
|---|---|---|
| **Finder eines gesperrten Geräts** | Tokens, Nachrichten, Termine, Dateien lesen | Keychain mit `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; Offline-Dateien mit `completeFileProtection` - beide bei gesperrtem Gerät unlesbar. Der Antwort-Zwischenspeicher trägt den iOS-Standardschutz (siehe Befund R1) - bewusst. |
| **Beobachter im Netz** | Tokens, Inhalte abfangen | Nur HTTPS. Der OAuth-Zufall scheitert seit 1.9 nicht mehr still (Befund O1). Der Client ist öffentlich (quelloffen), es gibt kein Client-Geheimnis - PKCE tritt an seine Stelle. |
| **Stud.IP-Betreiber** (Gegenüber, vertrauenswürdig) | - | StudGo vertraut ihm wie die Weboberfläche auch: Die Daten stammen ohnehin von dort. |
| **Andere Apps auf dem Gerät** | Kontodaten lesen | iOS-Sandbox; die App Group `group.de.maxaufknax.studgo.shared` können nur die App und die Widget-Erweiterung lesen. |
| **Apple-Prüfung** | Fehldeutung des Demo-Modus | Der Demo-Modus (`DemoServer`) erklärt sich selbst: vollständige App an erfundenen Daten, ohne Konto. Metadaten und App nennen keine Hochschule. |

Nicht Teil des Modells: ein entriegeltes Gerät in fremder Hand. Dagegen hilft
das Betriebssystem, nicht die App. Ebenfalls gesetzt, nicht zufällig: kein
eigener Push-Server, kein Tracking, keine Analyse-SDKs, keine Werbung.

---

## Datenflüsse

```
Stud.IP (HTTPS, OAuth Authorization Code + PKCE S256)
   │  Tokens bleiben auf dem Gerät: Keychain
   ▼
StudGo-App ── JSON:API-Antworten ──▶ ResponseCache (Caches-Ordner)
   │           Downloads ──────────▶ tmp/StudGo-Downloads/<Datei-ID>/
   │           Offline-Dateien ────▶ Application Support (Backup ausgenommen)
   │           Schnappschuss ──────▶ App Group (Widgets)
   │           Meldungen ──────────▶ Meldestelle (HTTPS, nur Meldungen)
   ▼
Widget-Erweiterung (liest nur den Schnappschuss; selbst kein Netz)
```

Was StudGo **nie** tut: Tokens an Dritte senden, ein eigenes Backend für
Stud.IP-Daten betreiben, Mitteilungen über einen Server verteilen (iOS
stellt sie lokal zu), Bewegungs- oder Nutzungsprofile anlegen.

---

## Befunde

Legende: **geprüft** = regelkonform vorgefunden · **gefunden** = Abweichung
· **geändert** = in 1.9 behoben.

| Nr. | Bereich | Befund | Status |
|---|---|---|---|
| O1 | OAuth-Zufall | Der Rückgabewert von `SecRandomCopyBytes` wurde ignoriert: Schlug der Aufruf fehl, bestand der PKCE-Verifier aus 48 Nullbytes - wirkungsloser Schutz, ohne dass es auffiele. | gefunden → **geändert** (1.9): `SystemRandomNumberGenerator`; er kann nicht still scheitern, sondern bricht ab |
| O2 | OAuth-Ablauf | Authorization Code Flow + PKCE (S256), `state`-Prüfung gegen den Rückruf, `ASWebAuthenticationSession`, Abbruch sauber abgefangen. | geprüft |
| O3 | Web-Sitzung | `prefersEphemeralWebBrowserSession` wahlweise (Einstellung, Voreinstellung: teilen): Der Handel - die geteilte Safari-Sitzung meldet auch die Stud.IP-Seiten vor, die die Schnittstelle nicht kann (Eintragen, Profilbild, Prüfungsverwaltung); die flüchtige Sitzung hinterlässt keinen Cookie, verlangt dafür jede dieser Seiten erneut. Beide Seiten stehen in Preferences/WebSheet, damit die Wahl informiert bleibt. | geprüft |
| K1 | Keychain-Speicherung | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` - nur dieses Gerät, nur nach erstem Entsperren. Kein Mitschreiben in den iCloud-Schlüsselbund. | geprüft |
| K2 | Keychain-Aufräumen | Löschen am Sitzungsende - jede Art: Knopf in den Einstellungen, abgelaufene Erneuerung, Eintritt in die Demo. | geprüft |
| K3 | Wettlauf Erneuern/Abmelden | `AuthStore` zählt eine **Sitzungs-Generation** hoch: Lief eine Token-Erneuerung über das Abmelden hinweg, verwirft sie ihr Ergebnis, statt den frischen Token nach dem Abmelden wieder in die Keychain zu schreiben - sonst wäre beim nächsten Start wieder jemand angemeldet. | gefunden → **geändert** (1.9) |
| K4 | Passive Instanz | `AuthStore(passive: true)` (Hintergrundlauf) meldet **nie** ab und löscht nichts: Antwortete der Server nachts mit einem Fehler, stand sonst morgens die Anmeldung da, ohne dass jemand davor saß. Die passive Instanz vergisst nur ihren eigenen Stand im Arbeitsspeicher; ob eine Sitzung endet, entscheidet die Oberfläche. Feste Regel, dokumentiert in `AuthStore`. | geprüft |
| R1 | ResponseCache | Standard-Dateischutz: nach erstem Entsperren lesbar. Bewusst in Kauf genommen: Die App wird ohnehin nur bedient, also entsperrt, und der Zwischenspeicher soll offline sofort Antwort geben; ein stärkerer Schutz brächte nur Nachteile ohne belegte Bedrohung. Inhalt: JSON:API-Antworten (Termine, Nachrichtentitel und -inhalte, Foren- und Wiki-Beiträge). Schlüssel: SHA256 je Anfrage, maxAge 300 s, geleert am Sitzungsende. | geprüft, bewusst akzeptiert |
| D1 | Downloads | tmp/StudGo-Downloads, seit 1.9 ein Unterordner je Datei-ID, damit gleichnamige Kursdateien („Loesung.pdf“ in zwei Übungsordnern) einander nicht überschreiben - bis 1.9 zeigte die Vorschau still die falsche Datei. Geleert am Sitzungsende. | gefunden → **geändert** (1.9) |
| D2 | Offline-Dateien | Application Support, **vom Backup ausgenommen**, `completeFileProtection` (bei gesperrtem Gerät unlesbar), Manifest `Manifest.json`, geleert am Sitzungsende. | geprüft |
| A1 | Kontodaten am Sitzungsende | Bis 1.8 blieben Blockliste, ausgeblendete Termine, Mitteilungs-Merker und die Annahme der Nutzungsbedingungen liegen - das nächste Konto auf demselben Gerät hätte sie gesehen. Zentral gelöst: `AccountState` sammelt die kontogebundenen Schlüssel, räumt sie am Sitzungsende weg und meldet den Speichern (`dataDidReset`); ein Test sorgt dafür, dass neue Schlüssel dort eingetragen werden. | gefunden → **geändert** (1.9) |
| A2 | Mitteilungen am Sitzungsende | Bis 1.9 blieben geplante und zugestellte Mitteilungen des vorigen Kontos auf dem Sperrbildschirm, wenn eine Sitzung von selbst endete (abgelaufener Token, 401). Jetzt räumt jede Form des Sitzungsendes auch die Mitteilungen weg. | gefunden → **geändert** (1.9) |
| M1 | Sperrbildschirm-Inhalte | Mitteilungen zeigen Absender und Betreff wie die Mail-App. Sie entstehen rein lokal (kein Push-Server), iOS stellt sie zu. Verdeckte Vorschauen sind eine iOS-Geräteeinstellung, die jede Person selbst setzen kann; StudGo richtet sich nach der System-Mail-App. | geprüft, bewusst so (offener Punkt 2) |
| W1 | Widget-Schnappschuss | App Group `group.de.maxaufknax.studgo.shared`: Termin-Titel und Räume der nächsten 7 Tage, Ungelesen-Zahl, seit 1.9 Namen und Preise des heutigen Mensa-Tages. Nur App und Widget-Erweiterung können die Gruppe lesen (iOS-Regel). Widgets fragen **nie** selbst das Netz ab - sie lesen, was die App hinterlegt hat, und wissen anhand `updatedAt`, wie frisch das ist. Geleert am Sitzungsende. Format abwärtskompatibel (optionale Felder, `WidgetSnapshotTests`). | geprüft |
| L1 | Deep Links `studgo://` | Nur Reiter-Routing (heute/postfach/plan/kurse/campus/termin) plus `oauth/callback` über die `ASWebAuthenticationSession`. Deep Links lösen **keine** authentifizierten Aktionen aus - sie öffnen Ansichten, mehr nicht. | geprüft |
| B1 | WebSheet | Der In-App-Safari (`SFSafariViewController`) läuft im eigenen Prozess: StudGo sieht weder die Sitzung noch die Eingaben. Im Demo-Modus steht eine Weiche mit Erklärung statt der Anmeldung - niemand landet auf einem Anmeldebildschirm, den er ohne Konto nicht bedienen kann. | geprüft |
| E1 | Meldestelle (studgo-reports) | FastAPI; nur gelesen. Der App-Schlüssel ist kein Geheimnis (quelloffener Client), er hält nur Lärm ab. Ratenbremse 30/Stunde zählt `X-Real-IP` nur flüchtig im RAM - die Adresse kommt nicht in die Akte; Feldlängen begrenzt; Aufbewahrung 365 Tage mit Selbstlöschen; nginx reicht `X-Real-IP` durch (Resolver-Fix aus Commit `b4e09a7`, live aktiv). Meldungen klingeln nur für `.report`-Anliegen, nie für Blockierungen. | geprüft |

---

## Die Anmeldung, im Klartext

1. StudGo erzeugt je Anmeldung zwei Zufallswerte: den **state** (erkennt
   den Rückruf als den eigenen) und den **PKCE-Verifier** nebst der daraus
   abgeleiteten Prüfsumme, der Challenge. Beide entstehen seit 1.9 mit dem
   Zufallsgenerator der Standardbibliothek, der bei Versagen abbricht,
   statt heimlich Nullen zu liefern (O1).
2. Die Anmeldung öffnet in einer `ASWebAuthenticationSession` - die
   Hochschul-Anmeldung (Shibboleth) sieht StudGo nicht; zurück in die App
   kommt nur der Code-Rückruf auf `studgo://`.
3. Beim Rückruf prüft StudGo den `state` und tauscht Code + Verifier über
   HTTPS gegen das Token-Paar (Zugriff, Erneuerung).
4. Die Tokens wandern in die **Keychain dieses einen Geräts**
   (`AfterFirstUnlockThisDeviceOnly`, kein iCloud-Schlüsselbund). Sie
   verlassen das Gerät nie wieder - die Erneuerung läuft direkt gegen den
   Token-Endpunkt des Stud.IP-Servers. Erneuerungen sind über alle
   Instanzen der App hinweg koordiniert, weil der Server alte Tokens bei
   jeder Erneuerung ungültig macht.
5. Abmelden - oder ein Sitzungsende aus beliebigem Grund - löscht:
   Keychain, Zwischenspeicher, Downloads, Offline-Dateien,
   kontogebundene Einstellungen, Widget-Schnappschuss, Kalender
   „StudGo“ und alle geplanten und zugestellten Mitteilungen (A1, A2).

---

## Offene Punkte

Nichts davon blockiert die Veröffentlichung; alles bleibt hier sichtbar.

1. **Live-Prüfung aller 1.9-Routen mangels Token ausgeblieben.** Der
   komplette OAuth-Ablauf gegen den echten Server ist am Quelltext geprüft,
   nie mit echtem Konto durchlaufen. Dasselbe gilt für die neuen
   1.9-Stud.IP-Routen (Statusgruppen `status-groups`, Aktivitätenstrom mit
   `filter[start]`, Größe der `events.ics`). Mit dem ersten
   TestFlight-Build zu erledigen.
2. **Vorschauen auf dem Sperrbildschirm** (M1): bewusste Entscheidung,
   passend zur Mail-App; versteckte Vorschauen bleiben eine
   iOS-Geräteeinstellung. Nicht geändert.
3. **Basisschutz des ResponseCache** (R1): akzeptierter Befund mit
   Begründung oben. Wer ihn trotzdem anheben wollte, wäre mit
   `completeFileProtection` in einem Satz drin - der Preis wäre, dass der
   Zwischenspeicher bei gesperrtem Gerät unlesbar und die App dort
   offline leer wäre.
4. **Keine eigene Behandlung eines zweiten Faktors**: Die Hochschule
   setzt ihren eigenen Shibboleth-Login ein, einschließlich etwaiger
   zweiter Faktoren. StudGo führt durch diesen hindurch und kann ihn
   weder umgehen noch braucht es eigene Logik dafür.

---

*Keine Hochschul-Namen in App oder Metadaten; der bestehende Suchbegriff
„Hannover“ blieb unangetastet. Dieses Dokument verlässt das Repository
nicht.*
