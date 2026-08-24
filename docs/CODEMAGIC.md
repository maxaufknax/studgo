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
2. **Teams → Integrations → App Store Connect**: neue Integration mit dem Namen
   **`StudGo ASC`** anlegen (dieser Name steht so in `codemagic.yaml`) und
   Issuer ID, Key ID sowie die `.p8`-Datei hinterlegen.
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

## Bauen

| Auslöser | Workflow | Ergebnis |
| --- | --- | --- |
| Push oder Pull Request | `check` | baut für den Simulator, kein Upload — merkt Kompilierfehler früh |
| Tag `v*`, z. B. `v1.0.0` | `testflight` | signierte IPA, Upload nach TestFlight |

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
