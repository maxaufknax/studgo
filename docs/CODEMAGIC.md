# Bauen ohne Mac — Codemagic einrichten

StudGo wird auf Codemagics macOS-Maschinen gebaut und direkt nach TestFlight
hochgeladen. Ein eigener Mac ist dafür nicht nötig.

## Einmalige Vorbereitung bei Apple

1. **Apple Developer Program** — Mitgliedschaft muss aktiv sein (99 €/Jahr).
2. **Bundle-ID registrieren**: `com.maxpaasch.studgo`
   (Developer Portal → Identifiers → App IDs → App).
   Keine besonderen Capabilities nötig — StudGo braucht weder Push noch
   App Groups noch iCloud.
3. **App in App Store Connect anlegen**: Plattform iOS, Name „StudGo",
   Sprache Deutsch, Bundle-ID von oben, SKU frei wählbar.
4. **App Store Connect API-Key erzeugen**: Users and Access → Integrations →
   App Store Connect API → Team Keys → „+", Rolle **App Manager**.
   Die `.p8`-Datei wird nur einmal zum Download angeboten. Notiere dazu
   **Issuer ID** und **Key ID**.

## Einrichtung bei Codemagic

1. Repository verbinden (GitHub-App autorisieren, `maxaufknax/studgo` auswählen).
2. **App-Store-Connect-Schlüssel in Codemagic hinterlegen.** Der Weg ist
   tiefer verschachtelt, als man erwartet:

   > Codemagic → **Teams** → *dein Konto bzw. Team* → **Integrations** →
   > **App Store Connect** → **Manage keys** → **+ Add key**

   Dort ausfüllen: **Name**, Issuer ID, Key ID und die `.p8`-Datei. Der
   **Name** ist das Feld, das `codemagic.yaml` sucht.

   **Für dieses Konto ist das bereits erledigt**: Es existiert der Schlüssel
   `PocketADM ASC key`, und genau der steht in `codemagic.yaml`. Ein
   App-Store-Connect-API-Key gehört zum **Apple-Entwicklerkonto**, nicht zu
   einer einzelnen App — derselbe Schlüssel bedient PocketADM und StudGo. Der
   Name ist bloß ein Etikett.

   Ihn deshalb **nicht umbenennen**: PocketADMs `codemagic.yaml` verweist ihn
   ebenfalls über den Namen und würde stumm brechen.

   Zwei Fallen dabei:

   - Auch ohne Team gibt es in Codemagic einen Eintrag **„Personal Account"**
     unter *Teams* — dort liegen die Integrationen eines Einzelkontos. Wer nur
     in den App-Einstellungen sucht, findet die Stelle nicht.
   - Der Schlüssel muss **in demselben Team liegen wie die App**. Ist das
     Repository unter „Personal Account" verbunden, der Schlüssel aber in einem
     echten Team hinterlegt (oder umgekehrt), meldet der Build weiterhin
     `does not exist` — obwohl der Schlüssel sichtbar existiert.

   Einen App-Store-Connect-API-Key bei **Apple** zu erzeugen genügt nicht; er
   muss zusätzlich in Codemagic eingetragen werden. Das sind zwei getrennte
   Schritte.
3. **App settings → Environment variables**: Gruppe **`studip_oauth`** anlegen mit

   | Variable | Wert | Secure |
   | --- | --- | --- |
   | `STUDIP_CLIENT_ID` | `15` | nein |
   | `STUDIP_CLIENT_SECRET` | das Secret aus der Mail der ZQS | **ja** |

   Die Werte landen zur Bauzeit in `Config/Secrets.xcconfig`; im Repo steht das
   Secret nirgends.
4. Optional: `APP_STORE_APPLE_ID` (die numerische Apple-ID der App aus App Store
   Connect) als weitere Variable. Ist sie gesetzt, zählt die Pipeline die
   Build-Nummer automatisch von der letzten TestFlight-Version hoch.

## Reihenfolge

Der Workflow **`check`** braucht **nichts** von alldem — keine Integration, keine
Variablengruppe, keinen Apple-Account. Er lässt sich sofort starten und zeigt
innerhalb weniger Minuten, ob die App überhaupt kompiliert. Erst für
`testflight` sind die Punkte oben nötig.

Startet man `testflight`, bevor die Integration angelegt ist, bricht der Build
sofort ab — **noch bevor eine einzige Zeile Code angefasst wird**. Solche
Abbrüche sagen nichts über die App aus.

Der Name in `codemagic.yaml` muss **exakt** dem Schlüssel in Codemagic
entsprechen, Groß- und Kleinschreibung sowie Leerzeichen inklusive. Weicht
etwas ab, immer die YAML-Zeile anpassen — nie den Schlüssel umbenennen, an dem
andere Projekte hängen.

## Fehlermeldungen und was dahintersteckt

Die Einrichtung hat vier Tore. Sie melden sich einzeln, jedes kostet sonst
einen Build-Durchlauf — deshalb besser alle vier vorher abhaken.

| Meldung | Ursache | Abhilfe |
| --- | --- | --- |
| `App Store Connect integration "…" does not exist` | Schlüssel in Codemagic nicht angelegt, anders benannt, oder in einem anderen Team als die App | Schritt 2 oben — Name in `codemagic.yaml` an den tatsächlichen anpassen, nicht umgekehrt |
| `Group studip_oauth does not exist` | Variablengruppe fehlt | Schritt 3 oben |
| `No suitable application records were found` / Upload scheitert | App-Datensatz in App Store Connect fehlt | App dort anlegen (Plattform iOS, Bundle-ID `com.maxpaasch.studgo`) |
| `Bundle identifier ... not found` beim Signieren | Bundle-ID im Developer Portal nicht registriert | Identifiers → App IDs → App anlegen |
| `Cannot save Signing Certificates without certificate private key` | Das Skript ging den **manuellen** Signierweg (`keychain initialize` + `fetch-signing-files --create`), der zusätzlich `CERTIFICATE_PRIVATE_KEY` verlangt | Behoben: Die Pipeline nutzt jetzt `environment.ios_signing` (siehe unten) |

### Signierung läuft automatisch

`codemagic.yaml` enthält

```yaml
environment:
  ios_signing:
    distribution_type: app_store
    bundle_identifier: com.maxpaasch.studgo
```

Damit besorgt Codemagic Zertifikat und Provisioning-Profil selbst über den
ASC-Schlüssel und legt beides in den Schlüsselbund der Baumaschine. Im Skript
bleibt nur `xcode-project use-profiles`, und zwar **nach** `xcodegen generate`.

Ein `CERTIFICATE_PRIVATE_KEY` wird dafür **nicht** gebraucht — der ist nur beim
manuellen Weg nötig. Und ihn bei jedem Lauf neu zu erzeugen wäre keine Lösung,
sondern ein Problem: Apple erlaubt nur wenige Verteilzertifikate je Konto, und
dieses Kontingent teilt sich StudGo mit PocketADM.

Vor dem ersten `testflight`-Lauf sollten also **alle vier** stehen: Schlüssel in
Codemagic, Variablengruppe, Bundle-ID im Developer Portal, App-Datensatz in
App Store Connect.

## Bauen

| Auslöser | Workflow | Voraussetzungen | Ergebnis |
| --- | --- | --- | --- |
| Push oder Pull Request | `check` („1 · Build-Prüfung") | keine | baut für den Simulator, kein Upload — merkt Kompilierfehler früh |
| Tag `v*`, z. B. `v1.0.0` | `testflight` („2 · TestFlight") | alles oben | signierte IPA, Upload nach TestFlight |

```bash
git tag v1.0.0
git push origin v1.0.0
```

Der erste `testflight`-Lauf legt über `app-store-connect fetch-signing-files
--create` automatisch Distributionszertifikat und Provisioning-Profil an.

## Nach dem ersten Upload

Sobald in App Store Connect eine TestFlight-Gruppe existiert, kann in
`codemagic.yaml` unter `publishing.app_store_connect` der auskommentierte Block
`beta_groups` aktiviert werden — dann verteilt Codemagic jede Version direkt an
die Gruppe, statt sie nur hochzuladen.

Für die App-Store-Prüfung (nicht für TestFlight) wird zusätzlich gebraucht:
Datenschutzangaben („keine Daten erfasst" — passend zu
`App/Resources/PrivacyInfo.xcprivacy`), Screenshots, eine Support-URL und ein
Hinweis für die Prüfenden, dass für die Anmeldung ein Stud.IP-Konto der Leibniz
Universität Hannover nötig ist. **Ein Testkonto muss beigelegt werden**, sonst
kommt die Ablehnung nach Richtlinie 2.1 — Apple kann sich sonst nicht anmelden.
