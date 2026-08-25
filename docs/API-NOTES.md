# Stud.IP LUH — API- & OAuth2-Befunde

Stand: 2026-08-25. Alle Angaben durch direkte Requests gegen den Live-Server
sowie gegen die Schema- und Route-Quellen von Stud.IP 6.0 verifiziert.

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

## ⚠️ Anfrageparameter: Stud.IP prüft streng — falsche Parameter = 400

Jede Route erbt von `JsonApiController`. Dessen Konstruktor lässt einen
`QueryChecker` über die Anfrage laufen, **bevor** die Route überhaupt
ausgeführt wird. Maßgeblich sind vier Listen in der jeweiligen Routenklasse:

```php
protected $allowUnrecognizedParams = false;   // unbekannte Parameter -> 400
protected $allowedIncludePaths     = null;    // null = alle erlaubt
protected $allowedSortFields       = [];      // [] = gar keins erlaubt
protected $allowedPagingParameters = [];      // [] = kein page[...] erlaubt
protected $allowedFilteringParameters = [];   // [] = kein filter[...] erlaubt
```

**Leeres Array heißt: nichts erlaubt.** Wer an eine solche Route ein
`page[limit]` hängt, bekommt

```json
{"errors":[{"status":"400","title":"Bad Request",
            "detail":"Page parameter limit is not allowed."}]}
```

Das ist genau der Fehler, an dem die **Wochenansicht des Stundenplans** lange
hing: `/v1/users/{id}/schedule` wird von `UserScheduleShow` bedient — einer
*Show*-Route ohne jede Seitenaufteilung. `StudIPClient.schedule(for:)` schickte
trotzdem `page[limit]=500`, der Server lehnte ab, und die Ansicht blieb leer.
Der Endpunkt liefert ohnehin immer den vollständigen Semesterplan; die
Seitenangabe war nie nötig.

Merkregel: **`…Show`-Routen und Index-Routen ohne eigenes
`$allowedPagingParameters` vertragen kein `page[...]`.** Im Zweifel gilt die
Tabelle unten — sie ist aus dem Stud.IP-Quelltext erzeugt, nicht geraten:

```bash
G=https://gitlab.studip.de/api/v4/projects/34/repository
curl -sL "$G/archive.tar.gz?sha=6.0&path=lib/classes/JsonApi" | tar xz
# dann RouteMap.php gegen Routes/**/*.php auswerten (Vererbung mitlesen:
# InboxShow erbt sein Paging von BoxController)
```

### Erlaubte Parameter der von StudGo benutzten Routen

| Route | `page[…]` | `filter[…]` |
| --- | --- | --- |
| `GET /users/me` | **nein** | – |
| `GET /users/{id}` | **nein** | – |
| `GET /users` | `offset`, `limit` | `search` |
| `GET /users/{id}/courses` | `offset`, `limit` | `semester` |
| `GET /courses/{id}` | **nein** | – |
| `GET /courses` | `offset`, `limit` | `q`, `fields`, `semester`, `category`, `scope_choose`, `range_choose`, `df` |
| `GET /users/{id}/schedule` | **nein** | `timestamp` |
| `GET /users/{id}/events` | `offset`, `limit` | `timestamp` |
| `GET /courses/{id}/events` | `offset`, `limit` | – |
| `GET /semesters` | `offset`, `limit` | `current`, `timestamp` |
| `GET /sem-types` | `offset`, `limit` | – |
| `GET /courses/{id}/memberships` | `offset`, `limit` | `permission` |
| `GET /users/{id}/course-memberships` | `offset`, `limit` | – |
| `GET /course-memberships/{id}` | **nein** | – |
| `PATCH /course-memberships/{id}` | **nein** | – |
| `GET /users/{id}/inbox` | `offset`, `limit` | `unread` |
| `GET /users/{id}/outbox` | `offset`, `limit` | – |
| `POST /messages` | **nein** | – |
| `GET /messages/{id}` | **nein** | – |
| `PATCH /messages/{id}` | **nein** | – |
| `GET /users/{id}/news` | `offset`, `limit` | – |
| `POST /users/{id}/news` | **nein** | – |
| `GET /courses/{id}/news` | `offset`, `limit` | – |
| `POST /courses/{id}/news` | **nein** | – |
| `GET /studip/news` | `offset`, `limit` | – |
| `GET /{type:courses|institutes|users}/{id}/folders` | `offset`, `limit` | – |
| `POST /{type:courses|institutes|users}/{id}/folders` | **nein** | – |
| `GET /folders/{id}/folders` | `offset`, `limit` | – |
| `POST /folders/{id}/folders` | **nein** | – |
| `GET /folders/{id}/file-refs` | `offset`, `limit` | – |
| `POST /folders/{id}/file-refs` | **nein** | – |
| `GET /blubber-threads` | `offset`, `limit` | `since`, `before`, `search`, `context-type`, `context-id` |
| `POST /blubber-threads` | **nein** | – |
| `GET /users/{id}/blubber-threads` | `offset`, `limit` | `since`, `before`, `search`, `context-type`, `context-id` |
| `GET /courses/{id}/blubber-threads` | `offset`, `limit` | `since`, `before`, `search`, `context-type`, `context-id` |
| `GET /studip/blubber-threads` | `offset`, `limit` | `since`, `before`, `search`, `context-type`, `context-id` |
| `GET /blubber-threads/{id}` | **nein** | – |
| `PATCH /blubber-threads/{id}` | **nein** | – |
| `GET /blubber-threads/{id}/comments` | `offset`, `limit` | `since`, `before`, `search` |
| `POST /blubber-threads/{id}/comments` | **nein** | – |
| `GET /users/{id}/activitystream` | `offset`, `limit` | `start`, `end`, `activity-type`, `context-type`, `context-id`, `object-type`, `object-id` |
| `GET /users/{id}/contacts` | `offset`, `limit` | – |
| `GET /users/{id}/institute-memberships` | `offset`, `limit` | – |
| `GET /institutes/{id}` | **nein** | – |
| `GET /courses/{id}/forum-categories` | `offset`, `limit` | – |
| `POST /courses/{id}/forum-categories` | **nein** | – |
| `GET /forum-categories/{id}/entries` | `offset`, `limit` | – |
| `POST /forum-categories/{id}/entries` | **nein** | – |
| `GET /forum-entries/{id}/entries` | `offset`, `limit` | – |
| `POST /forum-entries/{id}/entries` | **nein** | – |
| `GET /courses/{id}/wiki-pages` | `offset`, `limit` | – |
| `POST /courses/{id}/wiki-pages` | **nein** | – |
| `GET /news/{id}/comments` | `offset`, `limit` | – |
| `POST /news/{id}/comments` | **nein** | – |

`sort` ist bei **allen** diesen Routen verboten (`$allowedSortFields = []`),
sortiert wird also im Client. `include` ist dagegen fast überall offen
(`$allowedIncludePaths = null`) — nur die Rechtelage kann ein `include`
scheitern lassen, deshalb der Wiederholungsversuch ohne Zusatzdaten in
`StudIPClient.documentAllowingMissingIncludes`.

## Was die JSON:API *nicht* kann

Drei Wünsche lassen sich mit der Schnittstelle nicht erfüllen. Alle drei sind
im Quelltext nachgelesen, nicht vermutet:

| Wunsch | Warum es nicht geht |
| --- | --- |
| **In eine Veranstaltung eintragen / austragen** | `Routes\Courses\Rel\Memberships::authorize()` gibt für jede Methode außer `GET` hart `return false` zurück. Es gibt keine weitere Route dafür. |
| **Mitgliedschaft löschen** | Für `course-memberships` existiert kein `DELETE`. `PATCH /v1/course-memberships/{id}` ändert ausschließlich `group` (0–9) und `visible` (`yes`/`no`), siehe `CourseMembershipsUpdate::updateMembershipFromJSON`. |
| **Rangliste / Punktestand über Studierende hinweg** | Stud.IP führt so etwas nicht. Der Aktivitätenstrom (`/v1/users/{id}/activitystream`) ist **rein persönlich** — er zeigt nur die eigene Sicht, nicht die anderer. |

`POST /v1/admission/available-courses` klingt passend, ist aber ein
Verwaltungswerkzeug: Es listet Veranstaltungen, die **noch keinem Anmeldeset
zugeordnet** sind, und dient dem Anlegen von Anmeldeverfahren.

Das An- und Abmelden führt deshalb über die Weboberfläche:
`/dispatch.php/course/enrolment/apply/{course_id}` bzw. `/dispatch.php/my_courses`.
StudGo öffnet beides im `SFSafariViewController` (`App/Core/WebSheet.swift`) —
der läuft in einem eigenen Prozess, die App sieht weder Sitzung noch Eingaben.

## Neu erschlossene Bereiche (2026-08-25)

| Bereich | Routen | Modell |
| --- | --- | --- |
| **Blubber** (Messenger) | `/v1/blubber-threads`, `.../{id}/comments` (GET + POST), `/v1/users/{id}/blubber-threads`, `/v1/courses/{id}/blubber-threads`, `/v1/studip/blubber-threads` | `BlubberThread`, `BlubberComment` |
| **Aktivitätenstrom** | `/v1/users/{id}/activitystream` | `ActivityItem` |
| **Kontakte** | `/v1/users/{id}/contacts` | `Contact` |
| **Veranstaltungssuche** | `/v1/courses` mit `filter[q]` (min. 3 Zeichen) | `Course` |
| **Forum** | `/v1/courses/{id}/forum-categories` → `/entries` → `/entries` | `ForumCategory`, `ForumEntry` |
| **Wiki** | `/v1/courses/{id}/wiki-pages` | `WikiPage` |
| **Einrichtungen** | `/v1/users/{id}/institute-memberships`, `/v1/institutes/{id}` | `Institute` |
| **Eigene Mitgliedschaft** | `/v1/users/{id}/course-memberships`, `PATCH /v1/course-memberships/{id}` | `CourseMembership` |

### Nachtrag: Community-Routen (ebenfalls 2026-08-25)

| Bereich | Routen | Besonderheit |
| --- | --- | --- |
| **Kontakte pflegen** | `POST` / `DELETE` `/v1/users/{id}/relationships/contacts` | Body ist eine **Liste von Ressourcenkennungen** (`{"data":[{"type":"users","id":"…"}]}`), kein Objekt. Antwort ist `204` ohne Inhalt. Erlaubt nur für das eigene Konto (`canEditUser`). |
| **Studiengruppen** | `GET /v1/studygroup-proposals` | Nimmt **nur `page[limit]`**, kein `page[offset]` — ein Offset ist ein 400. Standard sind 4 Vorschläge. Liefert `courses`, keine eigene Ressource. |
| **Sprechstunden** | `GET /v1/{courses\|institutes\|users}/{id}/consultations` → `GET /v1/consultation-blocks/{id}/slots` → `POST /v1/consultation-slots/{id}/bookings` | Filter `current` / `expired` sind **`0`/`1`**, nicht `true`/`false`. Ist der Termin schon vergeben, antwortet Stud.IP mit **`409 Conflict`**. |

Die Buchung will die Person **als Beziehung**, nicht als Attribut:

```jsonc
// POST /v1/consultation-slots/{id}/bookings
{"data":{"type":"consultation-bookings",
         "attributes":{"reason":"…"},
         "relationships":{
           "user":{"data":{"type":"users","id":"…"}},
           "slot":{"data":{"type":"consultation-slots","id":"…"}}}}}
```

Ohne `relationships.user` lehnt `BookingsCreate::validateResourceDocument` mit
„No user relationship defined for booking" ab.

### Fallstricke in diesen Bereichen

- **`blubber-threads`** unterscheidet über `context-type` zwischen `private`
  (Direktnachricht), `course`, `institute` und `public`. Wer nicht danach
  trennt, mischt Kursaushänge unter die Direktnachrichten.
- Die Zahl **ungelesener Blubber-Kommentare** steht *nicht* bei den
  Attributen, sondern im `meta` des Beziehungs-Links:
  `relationships.comments.links.related.meta["unseen-comments"]`.
  Dafür gibt es `Resource.relationshipLinkMeta(_:_:)`.
- **`activities`** heißt der Ressourcentyp, nicht `activity-stream`.
  `activity-type` wird serverseitig aus dem Provider-Klassennamen abgeleitet
  (`DocumentsProvider` → `documents`) — die Liste ist installationsabhängig,
  Filterknöpfe sollten deshalb aus den tatsächlich gelieferten Werten gebaut
  werden.
- **`institutes`** hat kein `email`-Attribut, und `city` wird aus der **PLZ**
  gefüllt (`'city' => $institute->plz`).
- **`/v1/courses`** (Suche) verlangt `filter[q]` mit **mindestens drei
  Zeichen** und akzeptiert bei `filter[fields]` nur
  `all`, `title_lecturer_number`, `title`, `sub_title`, `lecturer`, `number`,
  `comment`, `scope`. Alles andere ist ein 400.
- **`consultation-slots`** benennt seine Zeitfelder **`start_time` und
  `end_time` mit Unterstrich** — als einzige Ressource der ganzen API, überall
  sonst gilt der Bindestrich. Wer `start-time` liest, bekommt `nil` und eine
  Terminliste ohne Uhrzeiten.
- **`course-memberships`**: `visible` liefert Stud.IP nur mit, wenn man die
  Liste der eigenen Mitgliedschaften abruft oder die Veranstaltung leiten darf.
  Fehlt das Feld, ist `yes` die richtige Annahme.

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

## Attributtypen, die anders sind als der Name vermuten lässt

Aus den Schemas (`lib/classes/JsonApi/Schemas/`) gegengelesen. Jeder dieser
Punkte lässt im Client stillschweigend ein Feld leer — ohne Fehlermeldung.

| Ressource | Attribut | Fallstrick |
| --- | --- | --- |
| `courses` | `course-type` | **`(int)`**, nicht String — die ID einer Veranstaltungsart. Als String gelesen ist das Feld immer `nil`. Klartext über `GET /v1/sem-types` (`name`), die Belegung ist je Installation anders. |
| `file-refs` | `is-downloadable` | Nur vorhanden, **wenn** `getFolderType()` etwas liefert. Fehlt es und man liest es als `false`, sperrt der Client Dateien, die der Server sehr wohl herausgibt. Im Zweifel erlauben. |
| `course-memberships` | `label` | Meist leer — das ist die frei gepflegte Funktionsbezeichnung. Die Rolle steckt in `permission` (`dozent`, `tutor`, `autor`, `user`) und will für die Anzeige übersetzt werden. |
| `course-events` | `title` / `description` | `title` ist der **Veranstaltungsname** (in einer Terminliste also in jeder Zeile derselbe), `description` das **Thema der Sitzung**. Für die Liste zählt `description`. |
| `calendar-events` | `owner` | Zeigt auf **`users` oder `courses`**. Wer die ID ungeprüft als Kursbezug nimmt, ordnet private Termine einer Veranstaltung zu. Immer den `type` mitlesen. |
| `seminar-cycle-dates` | `owner` | Zeigt auf die **Veranstaltung** — damit lässt sich ein Stundenplanblock seinem Kurs zuordnen. Bei `schedule-entries` zeigt `owner` dagegen auf die *Person*. |
| `messages` | `sender` | Im **Postausgang** ist das die eigene Person. Dort trägt nur `include=recipients` eine Information. |

## Filter, die es tatsächlich gibt

Aus den Route-Klassen (`$allowedFilteringParameters`) verifiziert:

| Route | Filter |
| --- | --- |
| `/v1/users/{id}/courses` | `filter[semester]` = Semester-ID. **Ohne** Filter kommen *alle je belegten* Veranstaltungen zurück, über mehrere Jahre. |
| `/v1/users/{id}/schedule` | `filter[timestamp]` wählt das Semester (Standard: laufendes) |
| `/v1/users/{id}/events` | `filter[timestamp]` verschiebt das feste Zwei-Wochen-Fenster |
| `/v1/users` | `filter[search]`, mindestens drei Zeichen |

`/v1/users/{id}/schedule` verlangt `canEditUser` — der Stundenplan **anderer**
Personen ist nicht abrufbar, `me` funktioniert.

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

## OAuth-Zustimmung ohne Browser

Browser verwerfen die Weiterleitung auf `studgo://oauth/callback` kommentarlos —
der Code entsteht, ist aber nirgends ablesbar. Für Tests am Rechner deshalb
`./tools/studip-cli.py login --cookie`: Das Tool spielt die Zustimmungsseite
mit der bestehenden Stud.IP-Sitzung selbst durch.

Ablauf (aus `app/controllers/api/oauth2/authorize.php` und
`app/views/api/oauth2/authorize.php`):

1. `GET /dispatch.php/api/oauth2/authorize?…` mit Sitzungscookie
   → HTML-Zustimmungsseite. Ohne gültige Sitzung stattdessen 302 auf
   `/dispatch.php/login`.
2. Die Seite trägt **zwei** Formulare auf denselben Endpunkt. Das Ablehnen-
   Formular erkennt man am versteckten Feld `_method=delete`; das andere ist
   „Erlauben". Nötige Felder: `security_token` (CSRF), `auth_token`, `state`,
   `client_id`.
3. `POST` dieser Felder → **302 mit `Location: studgo://oauth/callback?code=…`**

Die Zustimmung wird **nicht gemerkt** — die Seite erscheint bei jedem Durchlauf
erneut. `auth_token` liegt in der Session und muss aus derselben Antwort
stammen, ein Vorrat an Codes lässt sich also nicht anlegen.

Sobald die ZQS die Loopback-Redirect-URI `http://127.0.0.1:8765/callback`
freischaltet, entfällt der Cookie-Umweg — dann kann das Tool einen lokalen
Listener aufmachen und den Code direkt entgegennehmen.
