# Stud.IP LUH — API- & OAuth2-Befunde

Stand: 2026-08-24. Alle Angaben durch direkte Requests gegen den Live-Server verifiziert.

## Server

| | |
| --- | --- |
| Base URL | `https://studip.uni-hannover.de` |
| Stud.IP-Version | **6.0.4** (`GET /jsonapi.php/v1/studip/properties`, ohne Auth abrufbar) |
| JSON:API | `https://studip.uni-hannover.de/jsonapi.php/v1/...` |
| Alte REST-API (`/api.php`) | **404 — abgeschaltet**, deprecated, nicht verwenden |
| Route-Discovery | `GET /jsonapi.php/v1/discovery` → 343 Routen, ohne Auth abrufbar |

## OAuth2-Endpunkte

```
Authorize:  https://studip.uni-hannover.de/dispatch.php/api/oauth2/authorize
Token:      https://studip.uni-hannover.de/dispatch.php/api/oauth2/token
```

Nicht existent (führen zu "No route matches"): `/dispatch.php/oauth2/*`,
`/dispatch.php/api/oauth/*` (ohne die 2), `/.well-known/oauth-authorization-server`.
Es gibt **keine Discovery-Metadaten** — Endpunkte müssen fest verdrahtet werden.

## Client-Registrierung (LUH, von Philipp Schüttlöffel / ZQS-elsa)

| | |
| --- | --- |
| `client_id` | `15` |
| `client_secret` | in `.env`, **nicht im Repo** |
| Redirect-URI | `studgo://oauth/callback` (exakt, wird serverseitig geprüft) |
| Scope | `api` (einziger existierender Scope, voller Zugriff) |

Verifiziert per Kontrolltest:

| Request | Ergebnis |
| --- | --- |
| `client_id=15` + korrekte Redirect-URI | **302 → `/dispatch.php/login`** ✅ Client aktiv |
| falsche Redirect-URI | 500 Fehlerseite |
| `client_id=99999` | 500 Fehlerseite |

## ⚠️ Kernproblem: Client ist als *confidential* registriert

Der Token-Endpunkt **erzwingt das `client_secret`**:

| Token-Request | Antwort |
| --- | --- |
| ohne `client_secret`, nur `code_verifier` (PKCE) | `Client authentication failed` ❌ |
| mit falschem `client_secret` | `Client authentication failed` ❌ |
| mit korrektem `client_secret` | kommt durch die Client-Auth, scheitert erst am Fake-Code ✅ |

Für eine App ohne Backend heißt das: Das Secret müsste ins Binary — es wäre per
`strings`/IPA-Extraktion auslesbar. Das widerspricht RFC 8252 (OAuth für native Apps)
und der Zusage an die Uni ("Tokens nur lokal im Keychain").
→ **Philipp bitten, Client 15 als *public client* (PKCE-only, ohne Secret) umzustellen.**
PKCE wird vom Authorize-Endpunkt bereits akzeptiert (`code_challenge_method=S256`).

Zusatzwunsch für die Entwicklung: zweite Redirect-URI `http://127.0.0.1:8765/callback`
erlaubt den Flow ohne iOS-Gerät zu testen (RFC 8252 §7.3 Loopback).

## Relevante Routen für StudGo

| Feature | Route |
| --- | --- |
| Eigenes Profil | `GET /v1/users/me` |
| Stundenplan | `GET /v1/users/{id}/schedule` |
| Termine | `GET /v1/users/{id}/events`, `.../events.ics` |
| Veranstaltungen | `GET /v1/users/{id}/courses`, `/v1/courses/{id}` |
| Nachrichten | `GET /v1/users/{id}/inbox` / `outbox`, `POST /v1/messages` (senden!) |
| Ankündigungen | `GET /v1/users/{id}/news`, `/v1/studip/news`, `/v1/courses/{id}/news` |
| Dateien | `GET /v1/courses/{id}/folders` → `/v1/folders/{id}/file-refs` → `/v1/file-refs/{id}/content` |
| Forum | `GET /v1/courses/{id}/forum-categories` → `/entries` |
| Semester | `GET /v1/semesters` |
| Avatare | `GET /v1/{courses\|institutes\|users}/{id}/avatar` |

Vollständige Liste: `curl -s .../v1/discovery | jq`.

## Dev-Tooling

`tools/studip-cli.py` — PKCE-Flow, Token-Refresh und authentifizierte API-Calls
von der Kommandozeile (`login`, `refresh`, `whoami`, `get <pfad>`).

## Fehlerformate

Zwei verschiedene, beide werden im Client behandelt:

- **JSON:API** (`/jsonapi.php/...`): `{"errors":[{"status","title","detail"}]}`
- **OAuth2** (`/dispatch.php/api/oauth2/...`): komplette **HTML-Fehlerseite**,
  die Meldung steckt in `<div class="messagebox_details"><ul><li>…</li></ul></div>`.
  Ausgewertet von `App/Core/StudIPErrorPage.swift` bzw. `studip_error()` im Dev-CLI.

## Paginierung

`page[limit]` und `page[offset]` (auch unkodiert akzeptiert), Gesamtzahl in
`meta.page.total`, Cursor-Links unter `links.first|next|last`.

## Fallstricke: Endpunkte liefern andere Typen als der Name vermuten lässt

Aus den Route-Implementierungen (`lib/classes/JsonApi/Routes/`) verifiziert —
diese drei Punkte kosten sonst leicht einen halben Tag:

| Endpunkt | Liefert tatsächlich |
| --- | --- |
| `GET /v1/users/{id}/schedule` | **gemischt**: selbst angelegte `schedule-entries` *und* die Turnustermine belegter Veranstaltungen als `seminar-cycle-dates`. Wer nur auf `schedule-entries` prüft, bekommt einen leeren Stundenplan. Raumangabe steckt nur bei `seminar-cycle-dates` im Attribut `locations` (Array von Raumnamen). |
| `GET /v1/users/{id}/events` | `calendar-events` (aus `CalendarDateAssignment`), **nicht** `course-events`. Fenster ist fest **midnight heute → +2 Wochen**; weitere Zeiträume nur über `filter[timestamp]` (Unix-Sekunden) in Folgeanfragen. Kein `is-cancelled`. |
| `GET /v1/courses/{id}/events` | `course-events` (`CourseDate` + `CourseExDate`), **mit** `is-cancelled`. |

Weitere Filter: `/v1/users/{id}/schedule` nimmt `filter[timestamp]` zur
Semesterwahl (Standard: laufendes Semester), `/v1/users` nimmt
`filter[search]` mit **mindestens drei Zeichen**.

## Schreibende Aufrufe

```jsonc
// POST /v1/messages
{"data":{"type":"messages",
         "attributes":{"subject":"…","message":"…"},
         "relationships":{"recipients":{"data":[{"type":"users","id":"…"}]}}}}

// PATCH /v1/messages/{id} — als gelesen markieren
{"data":{"type":"messages","id":"…","attributes":{"is-read":true}}}
```

Betreff und Text dürfen nicht leer sein, `recipients` muss mindestens einen
Nutzer enthalten — sonst antwortet Stud.IP mit einem Validierungsfehler.

## Dateien herunterladen

`GET /v1/file-refs/{id}/content` liefert die **rohen Bytes** (kein JSON:API),
Bearer-Token wie überall im Header. Weg dorthin:
`/v1/courses/{id}/folders` → `/v1/folders/{id}/folders` und
`/v1/folders/{id}/file-refs` → `/v1/file-refs/{id}/content`.

## Schema-Quellen

Alle Attributnamen stammen aus dem Stud.IP-Quellcode, offen abrufbar ohne Token:

```bash
G=https://gitlab.studip.de/api/v4/projects/34/repository
curl -s "$G/tree?path=lib/classes/JsonApi/Schemas&ref=6.0&per_page=100" | jq -r '.[].name'
curl -s "$G/files/lib%2Fclasses%2FJsonApi%2FSchemas%2FUser.php/raw?ref=6.0"
```

Branch `6.0` entspricht der an der LUH installierten Version.
