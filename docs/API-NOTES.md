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

## Befunde aus der TestFlight-Rückmeldung (2026-08-25)

Fünf Fehler, die sich alle im Stud.IP-Quelltext erklären lassen — und keiner
davon meldet sich als Fehler, sie führen zu stillen Leerständen.

### 1. `filter[semester]=all` ist ein 400 — die Veranstaltungssuche lief nie

`CoursesIndex::getContextFilters()` setzt intern `'semester' => 'all'` als
Vorgabe. Das verleitet dazu, den Wert auch mitzuschicken. Aber
`validateFilters()` läuft **vorher**:

```php
if (isset($filtering['semester'])) {
    $semester = \Semester::find($filtering['semester']);
    if (!$semester) { return 'Invalid "semester".'; }
}
```

`Semester::find('all')` findet nichts → **`400 Invalid "semester"`**. Der
Vorgabewert gilt nur, wenn der Parameter **ganz fehlt**. StudGo hängte ihn
immer an; die Suche antwortete deshalb ausnahmslos mit einem Fehler.

**Regel:** `filter[semester]` nur mit einer echten Semester-ID senden, sonst
weglassen.

### 2. Blubber-Kommentare kommen **ältestezuerst** — `sort` ist hier erlaubt

`CommentsByThreadIndex::getComments()` hängt ohne Zutun `ORDER BY mkdate` an
und schneidet mit `LIMIT/OFFSET` **vorne** ab. Eine Anfrage ohne `sort` liefert
also den Anfang eines Fadens, nicht das Ende — in einer laufenden Unterhaltung
sieht man dann Monate alte Beiträge und keine einzige aktuelle Antwort.

Diese Route ist die **einzige** von StudGo benutzte, die Sortierung zulässt:

```php
protected $allowedSortFields = ['mkdate'];   // überall sonst: []
```

`sort=-mkdate` dreht auf `ORDER BY mkdate DESC`. StudGo holt damit die jüngste
Seite und dreht sie für die Anzeige zurück; `page[offset]` blättert weiter in
die Vergangenheit.

### 3. Ein leeres Wiki ist ein **404**, kein leeres Array

`WikiIndex` wirft `RecordNotFoundException`, sobald für den Kurs keine Seite
existiert:

```php
if (!$wiki = \WikiPage::findBySQL('`range_id` = ? ORDER BY name ASC ', [$course->id])) {
    throw new RecordNotFoundException();
}
```

Ungefiltert erscheint in der App „Nicht gefunden — vielleicht wurde der Eintrag
entfernt", wo in Wahrheit nur nie jemand eine Seite angelegt hat. Dasselbe gilt
sinngemäß für 403 bei Veranstaltungen, in denen man nicht eingetragen ist:
Teilnehmende, Termine und Aushang sind dort schlicht nicht einsehbar. Beides
behandelt `StudIPClient.listAllowingAbsence`.

### 4. Texte sind **Stud.IP-Auszeichnung**, nicht HTML

Beschreibung, Ankündigung, Forenbeitrag, Wikiseite und Blubber kommen roh aus
der Datenbank (`Schemas/Course.php` reicht `beschreibung` und `sonstiges`
unverändert durch). Das Format ist Stud.IPs eigene Auszeichnung aus
`lib/classes/StudipCoreFormat.php`:

| Auszeichnung | Bedeutung |
| --- | --- |
| `!` `!!` `!!!` `!!!!` | Überschrift, **je mehr desto größer** (`level = max(1, 5 - Anzahl)`) |
| `**fett**`, `%%kursiv%%`, `__unterstrichen__`, `##fest##`, `{-gestrichen-}` | Betonungen |
| `*Wort*`, `%Wort%`, `#Wort#` | Kurzformen, nur um ein Wort ohne Leerzeichen |
| `- Punkt`, `-- Unterpunkt` | Aufzählung, Zeichenzahl = Ebene |
| `= Punkt` | nummerierte Liste |
| `\|Zelle\|Zelle\|` | Tabellenzeile |
| `--` bis `--9` allein auf einer Zeile | waagerechte Linie |
| `[Text]https://…` | Verweis; nackte Adressen und Mailadressen ebenso |
| `[quote]`, `[code]`, `[pre]`, `[nop]` | Blöcke |

**Nur** wenn ein Feld mit dem Marker `<!--HTML-->` beginnt, ist es echtes HTML
(`Markup::HTML_MARKER_REGEXP`, `/^\s*<!--\s*HTML.*?-->/i`). Alles andere ist
Klartext — ein `<` darin ist ein Kleiner-als-Zeichen, kein Tag.

Wer nur Tags entfernt (`strippingHTML`), zeigt dem Leser die Sternchen und
Prozentzeichen und verliert bei den HTML-Feldern zugleich die Absätze.
`App/Core/StudipMarkup.swift` setzt beide Fälle.

Nebenbei: Zwei Ressourcen liefern die fertige HTML-Fassung gleich mit —
`blubber-threads` als `content-html`, `blubber-comments` ebenso. Sonst nirgends.

### 5. Studiengruppen sind an der Antwort **nicht zu erkennen**

Es gibt keine Ressource „Studiengruppe": Es sind Veranstaltungen, deren
Veranstaltungsklasse `studygroup_mode` gesetzt hat. Dieses Kennzeichen steht in
**keinem** Schema — `Schemas/SemClass.php` führt `name`, `bereiche`, `visible`
und Ähnliches auf, aber nicht `studygroup_mode`.

Der tragfähige Umweg: `/v1/studygroup-proposals` filtert serverseitig
`status IN (:studygroup_types)`; was von dort kommt, **ist** per Konstruktion
eine Studiengruppe. Über `course-type` und die `sem-class`-Beziehung aus
`/v1/sem-types` (die immer mitgeliefert wird) ergeben sich alle Arten derselben
Klasse und die Klassen-ID für `filter[category]`.

Zwei weitere Eigenheiten der Vorschlagsroute, die man der Antwort nicht ansieht:
Die Auswahl wird **zufällig gemischt** (`shuffle`), zweimal Laden ergibt also
zwei Listen — und Vorschläge sind ausdrücklich Gruppen, in denen man **nicht**
Mitglied ist (`NOT EXISTS … seminar_user`). Die eigenen Studiengruppen stehen
dort nie; sie müssen aus `/v1/users/{id}/courses` herausgefiltert werden.

### Nachtrag: Attribute, die vorher ungenutzt blieben

| Ressource | Attribut | Wert |
| --- | --- | --- |
| `course-events`, `calendar-events` | `recurrence` | fertig formulierter Turnus („wöchentlich") |
| `course-events`, `calendar-events` | `categories` | Terminart im Klartext |
| `activities` | Beziehung `object` | das betroffene Ding — `FileRef`, `ForumEntry`, `Message`, `StudipNews`, `Course`, `WikiPage`. Ohne `include=object` lässt sich ein Eintrag im Verlauf nicht weiterverfolgen. |
| `sem-types` | Beziehung `sem-class` | wird **immer** mitgeliefert, auch ohne `include` |

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

---

# Befunde aus Fassung 1.3.0

## 6. `GET /users/{id}/events.ics` ist die **einzige** Quelle für echte Sitzungen

Der wichtigste Fund dieser Runde. Die Route steht in `RouteMap.php` Zeile 277
und ist ein `NonJsonApiController` — sie antwortet mit `text/calendar`, nicht
mit JSON:API, und fällt deshalb bei jedem Streifzug durch `/v1/discovery`
zwischen die Zeilen.

Serverseitig ruft `Routes\Events\UserEventsIcal` drei Exporte auf:

```php
$ical_export->exportCalendarDates($user, $start, $end)   // persönlicher Kalender
   . $ical_export->exportCourseDates($user, $start, $end)   // *** alle Sitzungen ***
   . $ical_export->exportCourseExDates($user, $start, $end) // ausgefallene Termine
```

`$end` ist fest auf den Unix-Zeitstempel `2114377200` gesetzt — **Januar 2037**.

Damit liefert diese eine Anfrage, was `/v1/users/{id}/events` **nicht** kann:

| | `/v1/users/{id}/events` | `/v1/users/{id}/events.ics` |
| --- | --- | --- |
| Veranstaltungstermine | ❌ (filtert auf `range_id = user`) | ✅ |
| Zeitraum | zwei Wochen ab `filter[timestamp]` | heute bis 2037 |
| Ausfälle | ❌ | ✅ (`… (fällt aus)` im `SUMMARY`) |
| Thema der Sitzung | ❌ | ✅ (`DESCRIPTION`) |
| Raum | ✅ | ✅ (`LOCATION`) |
| Kommendes Semester | ❌ | ✅, sobald man eingetragen ist |

**Format-Eigenheiten des Stud.IP-Exports** (`lib/classes/calendar/ICalendarExport.php`),
an denen ein strenger Leser scheitert:

1. **Kein Zeilenumbruch nach RFC 5545.** Lange `SUMMARY`-Zeilen werden nicht
   auf 75 Zeichen gefaltet. Falten können muss man trotzdem — falls sich das
   ändert.
2. **Echte Zeilenumbrüche in `DESCRIPTION`.** `prepareCourseDate()` fügt die
   Themen mit `implode("\n", …)` zusammen, `quoteText()` maskiert aber nur die
   *Zeichenfolge* Backslash-n, nicht das Zeichen selbst. Die Fortsetzungszeile
   beginnt ohne Leerzeichen und ist formal ungültig. `ICSParser` zählt eine
   Zeile ohne `NAME:Wert` zum vorigen Feld, statt den Rest zu verwerfen.
3. **Kennung als Herkunftsmerkmal.** Veranstaltungstermine tragen
   `UID:Stud.IP-SEM-<id>@<server>`, alles andere kommt aus dem persönlichen
   Kalender. Nur so lassen sich beide auseinanderhalten.
4. **Keine Kursbeziehung.** Der Strom nennt `Course::getFullName()`, nicht die
   Kennung. StudGo ordnet über den normalisierten Titel zu
   (`StudIPClient.matchCourse`), damit ein Kurs im Kalender dieselbe Farbe hat
   wie im Stundenplan.
5. **Ganztägig** wird als `DTSTART;VALUE=DATE:20261012` geschrieben, sonst als
   `DTSTART;TZID=Europe/Berlin:20261012T101500`.

## 7. Stud.IP-Felder enthalten HTML **ohne** den `<!--HTML-->`-Marker

Befund 4 (Fassung 1.2.0) war richtig, aber unvollständig. `Markup::isHtml()`
verlangt den Marker — an der LUH stehen in den Feldern aber reihenweise
`<p>…</p>` und `&auml;` *ohne* ihn, weil die Beschreibungen aus dem
Vorlesungsverzeichnis importiert oder aus einem Textverarbeiter eingefügt
wurden. `Schemas/Course::getAttributes()` reicht `beschreibung` unverändert
durch; Stud.IP selbst zeigt so ein Feld ebenfalls falsch an.

Deshalb entscheidet in StudGo seit 1.3.0 nicht der Marker allein, sondern
zusätzlich der Augenschein (`StudipMarkup.looksLikeHTML`): ein *geschlossenes*
Tag aus dem HTML-Grundwortschatz oder ein eindeutig leeres (`<br>`, `<hr>`,
`<img …>`). Bewusst eng — `a < b` und `3<4` bleiben Klartext, sonst verlöre
ein mathematischer Text seine Zeilenumbrüche.

Zwei Ressourcen liefern die gerenderte Fassung gleich mit: `blubber-threads`
und `blubber-comments` als `content-html` (`formatReady()` im Schema). Wo es
das gibt, ist es die bessere Quelle.

## 8. Der Dateibereich ist **vollständig beschreibbar**

Anders als Mitgliedschaften und Termine:

| Route | Zweck | Besonderheit |
| --- | --- | --- |
| `POST /folders/{id}/file-refs` | Hochladen | **nur** mit `multipart/form-data` |
| `POST /folders/{id}/folders` | Unterordner | `parent` muss auch im Rumpf stehen |
| `PATCH /file-refs/{id}` | Umbenennen | |
| `DELETE /file-refs/{id}` | Löschen | |
| `GET /terms-of-use` | Lizenzen | `is-default` markiert die Vorgabe |

`NegotiateFileRefsCreate` schaut auf den `Content-Type` und verzweigt: Mit
`application/vnd.api+json` erwartet die Route eine *Referenz auf eine bereits
vorhandene Datei*, nur mit `multipart/form-data` nimmt sie Bytes entgegen
(`FileRefsCreateByUpload`). Wer den JSON:API-Kopf mitschickt, bekommt eine
Fehlermeldung über ein fehlendes `data` und sucht an der falschen Stelle.

Den Dateinamen setzt der Kopf `Slug` (`RoutesHelperTrait::getFilename`,
`rawurldecode`), die Lizenz das Formularfeld `term-id`. Ob hochgeladen werden
darf, steht am Ordner in `is-writable`.

## 9. `/v1/blubber-threads` kann an **einem** verwaisten Faden scheitern

`Schemas/BlubberThread::getContextRelationship()` wirft einen
`InternalServerError`, sobald ein Faden mit `context_type = 'course'` auf eine
Veranstaltung zeigt, die es nicht mehr gibt — was am Semesterende vorkommt. Der
Fehler nimmt die **ganze** Liste mit; im Postfach stand dann null statt zwei
Unterhaltungen.

`StudIPClient.personalBlubberThreads` fällt deshalb auf
`/v1/courses/{id}/blubber-threads` je belegter Veranstaltung zurück, sobald die
Sammelroute nichts liefert. Ein kaputter Datensatz kostet dann höchstens diesen
einen Kurs.

Zweite Falle derselben Route: `/v1/studip/blubber-threads` (`type = public`)
holt in `getPublicThreads()` **alle** öffentlichen Fäden der Installation
(`findBySQL("context_type = 'public'")`), siebt sie in PHP und paginiert erst
danach. Auf einer Universität mit Jahren an Blubber ist das die teuerste Route,
die StudGo überhaupt anfasst — sie gehört nicht in einen Bildschirm, der beim
Öffnen eines Reiters mitlädt.

## 10. `/v1/users/{id}/blubber-threads` ist **nicht** „meine Fäden"

Die Route heißt in `RouteMap.php` `->setArgument('type', 'private')` und
landet in `getPrivateThreads($observer, $userID)`: Sie sucht Fäden, in denen
**beide** — der Anfragende und `{id}` — erwähnt sind. `/v1/users/{me}/…` gibt
also die Direktnachrichten *mit sich selbst*. Wer „meine Fäden" will, nimmt
`/v1/blubber-threads` ohne Präfix.

## 11. Der Stundenplan des **kommenden** Semesters

`UserScheduleShow` wählt das Semester über
`Semester::findByTimestamp((int) $filtering['timestamp'])`. Ein Zeitstempel im
kommenden Semester liefert dessen Plan — vorausgesetzt, man ist dort schon
eingetragen (`semester_courses.semester_id = :semester_id`). Zwei Monate vor
Beginn ist das meist nicht der Fall; eine leere Antwort ist dann kein Fehler.

`ScheduleEntry::findByUser_id()` läuft **ohne** Semesterfilter: Selbst angelegte
Termine kommen immer mit, egal welches Semester angefragt wird.

## 12. Anmeldung der Weboberfläche läuft über Shibboleth

`dispatch.php/login` der LUH bindet `login.uni-hannover.de` und
`/Shibboleth.sso` ein. Praktische Folge für die Rückfallebenen: Wer eine
gültige IdP-Sitzung in Safari hat, wird auf jeder von StudGo geöffneten
Stud.IP-Seite ohne Zutun durchgereicht — der `SFSafariViewController` teilt
sich den Cookie-Vorrat mit Safari.

Ob die OAuth-Anmeldung diese Sitzung überhaupt anlegt, entscheidet
`ASWebAuthenticationSession.prefersEphemeralWebBrowserSession` und damit die
Einstellung „Im Browser angemeldet bleiben" (`Preferences.sharesWebSession`,
Vorgabe **an**). Mit einer eigenen Sitzung bleibt kein Cookie zurück — dafür
verlangt jede Webseite eine erneute Anmeldung.

## 13. `/v1/users/{id}/activitystream` scheitert an **einem** verwaisten Ziel

Dieselbe Klasse Fehler wie bei den Blubber-Fäden (Befund 9), nur an einer Route
ohne offensichtliche Rückfallebene. Der Aktivitätenstrom sammelt aus vielen
Anbietern (`documents`, `forum`, `wiki`, `news` …). Zieht `include=object` die
serverseitige Serialisierung eines Ziels nach sich, das nicht mehr existiert —
eine Datei in einem gelöschten Ordner, ein Beitrag in einer entfernten
Veranstaltung —, antwortet Stud.IP mit **`500`**. Ein einziger solcher Eintrag
nimmt den **ganzen** Strom mit; im Campus-Reiter stand dann „Serverfehler 500".

`StudIPClient.activityStream` versucht deshalb in Stufen: erst mit allen
Beziehungen, dann mit weniger, dann ohne `include` — und, wenn auch das ein
`500` bleibt, mit einem engen `filter[start]` (letzte 90 Tage), damit die alten,
verwaisten Einträge gar nicht erst mitgeladen werden. Ohne `include=object`
fehlt nur der Anzeigename des Ziels; Typ und Kennung stehen weiter im
`relationships`-Block, ein Eintrag lässt sich also weiterhin öffnen.

Merke: Bei diesen Sammel-Routen lösen **`400` und `500`** denselben Schritt aus
— das eine heißt „`include` nicht erlaubt", das andere „ein Datensatz ließ sich
nicht serialisieren". Beide sind mit weniger Beziehungen zu überstehen.

## 14. Der Anfangsbeitrag eines Blubber-Fadens

`/v1/blubber-threads/{id}` (Show, **kein** `page[...]`) liefert `content` und
`content-html` verlässlich; `StudIPClient.blubberThread(id:)` holt den Faden
beim Öffnen und setzt den Aufschlag über den Verlauf.

**Berichtigung zu 1.3.0:** Hier stand, die *Listen*routen gäben `content-html`
nicht mit. Das stimmt nicht. `getOrderedThreads()` verbindet zwar
`blubber_threads` per `LEFT JOIN` mit `blubber_comments`, wählt aber
ausdrücklich nur die Fadenspalten aus:

```php
// SQLQuery::fetchAll($sorm_class) — lib/classes/SQLQuery.php
$sql = "SELECT `{$this->settings['table']}`.* ";
```

Der Anfangsbeitrag ist also auch in der Liste da. Die Einzelroute bleibt
trotzdem richtig — sie kostet nichts (`ResponseCache`) und ist die einzige
Quelle, wenn der Faden gar nicht aus einer Liste kam.

Und: Die Kommentar-Route lässt `sort=-mkdate` zu (`$allowedSortFields =
['mkdate']`, Befund 2) — falls eine Installation das doch mit `400` quittiert,
fällt `blubberComments` auf die unsortierte Reihenfolge (ältestezuerst) zurück,
statt den Verlauf leer zu lassen.


---

# Befunde aus Fassung 1.4.0

## 15. Der **globale Blubber** heißt `global` — und ist in der API ein Faden wie jeder andere

Der Strom, den die Weboberfläche unter `dispatch.php/blubber` zuerst zeigt, ist
kein eigener Endpunkt. Es ist ein gewöhnlicher Datensatz in `blubber_threads`
mit der fest verdrahteten Kennung `global`:

```php
// BlubberThread::findMyGlobalThreads()
$query->where('public/global/mentions', implode(' OR ', [
    "blubber_threads.thread_id = 'global'",
    "user_id = :user_id",
    "thread_id IN (SELECT thread_id FROM blubber_comments WHERE user_id = :user_id)"
]), [':user_id' => $user_id]);
```

Sein `display_class` ist `BlubberGlobalThread`; `BlubberThread::upgradeThread()`
macht daraus beim Laden die Unterklasse, deren `isReadable()` für **jeden**
Angemeldeten `true` liefert und deren `getName()` „Globaler Blubber" heißt.

Damit ist er über `GET /v1/blubber-threads/global` und
`GET /v1/blubber-threads/global/comments` erreichbar — ohne die teure Route
`/v1/studip/blubber-threads` (Befund 9).

**Die Falle:** Er trägt `context-type = public`. Wer im Postfach den
öffentlichen Strom heraussiebt (`thread.context != .publicStream`), siebt ihn
mit heraus. Genau deshalb fehlte er in StudGo bis 1.3.0 vollständig, obwohl er
in der Weboberfläche der erste Eintrag ist.

## 16. Ein Blubber-Faden trägt seinen Inhalt **entweder** im Aufschlag **oder** in den Beiträgen

Die Sorte entscheidet, wo der Text steckt:

| `context_type` | Aufschlag (`content`) | Verlauf (`blubber_comments`) |
| --- | --- | --- |
| `course`, `institute` | der geschriebene Beitrag | die Antworten darauf |
| `private` (Direktnachricht) | **leer** | die ganze Unterhaltung |
| `public` mit `thread_id = 'global'` | **leer** | der ganze Strom |

Eine Ansicht, die nur den Faden liest, zeigt bei den letzten beiden Sorten
nichts. Umgekehrt zeigt eine Ansicht, die nur die Kommentare liest, bei einem
Kursfaden ohne Antworten nichts. Beide Quellen gehören zusammen.

Nebenbei erklärt das die Aufräumabfrage am Anfang von `findMyGlobalThreads()`:
Fäden **ohne** Aufschlag **und ohne** Beitrag, älter als eine Stunde, werden
gelöscht. Ein Faden ohne beides ist in Stud.IP kein gültiger Zustand.

## 17. Die Beiträge lassen sich auch über die **Show**-Route holen

`Schemas/BlubberThread` erlaubt `include=comments`:

```php
protected ?array $allowedIncludes = [self::REL_AUTHOR, self::REL_COMMENTS,
                                     self::REL_CONTEXT, self::REL_MENTIONS];
```

und `getCommentsRelationship()` legt bei gesetztem `include` schlicht
`$resource->comments` (die `has_many`-Beziehung) in die Antwort. Das ist ein
**völlig anderer Weg** als `CommentsByThreadIndex`, das eine eigene SQL-Abfrage
mit `LIMIT`/`OFFSET` und Sortierung zusammensetzt und vorher
`Authority::canShowBlubberThread()` prüft.

`StudIPClient.blubberConversation(id:)` nutzt das als dritte Stufe:

1. `…/{id}/comments?sort=-mkdate` — Regelweg, mit Seitenaufteilung.
2. dieselbe Route ohne `sort` — für Fassungen, die es mit `400` ablehnen.
3. `…/{id}?include=comments.author` — holt alles auf einmal, ohne Paging.

Verschachteltes `include` ist erlaubt: `$allowedIncludePaths` steht im
`JsonApiController` auf `null` (= alle Pfade), und `BlubberComment` führt
`author` in seinen eigenen `allowedIncludes`.

Was auf welchem Weg herauskam, sammelt `BlubberConversation.trail` — die App
zeigt es unter „Warum ist hier nichts?", wenn ein Faden wirklich leer bleibt.
Ein stiller Leerstand war der teuerste Fehler der Fassung 1.3.0: „Noch keine
Beiträge", ohne dass irgendwo stand, welche Route was geantwortet hatte.

## 18. Zu `schedule-entries` gibt es **keine** schreibende Route

Der komplette Bestand in `RouteMap.php`:

```php
$group->get('/users/{id}/schedule',      Routes\Schedule\UserScheduleShow::class);
$group->get('/schedule-entries/{id}',    Routes\Schedule\ScheduleEntriesShow::class);
$group->get('/seminar-cycle-dates/{id}', Routes\Schedule\SeminarCycleDatesShow::class);
```

Kein POST, kein PATCH, kein DELETE — selbst angelegte Termine lassen sich über
die JSON:API nur lesen. Geschrieben wird in der Weboberfläche über
`app/controllers/calendar/schedule.php`:

| Zweck | Adresse |
| --- | --- |
| Übersicht | `dispatch.php/calendar/schedule` |
| Anlegen | `dispatch.php/calendar/schedule/entry/add` |
| Ändern/Löschen | `dispatch.php/calendar/schedule/entry/{id}` |

Die Anlegen-Seite nimmt Vorgaben entgegen — `entry_action()` liest
`Request::int('dow')` sowie `Request::get('start'|'end')`, wenn `start`
mitgeschickt wird. StudGo hängt beim Anlegen aus dem Kalender heraus den
angetippten Wochentag und die nächste volle Stunde an
(`WebLinks.newScheduleEntry(weekday:start:end:)`). Löschen läuft serverseitig
über einen `POST` mit `CSRFProtection::verifyUnsafeRequest()` und ist deshalb
nicht als Verweis nachzubauen; die Änderungsseite trägt den Knopf dafür.

## 19. Selbst angelegte Termine kennen **kein** Semester

Schon in Befund 11 vermerkt, aber mit Folgen, die erst 1.4.0 aufgefallen sind:

```php
ScheduleEntry::findByUser_id()   // ohne Semesterfilter
```

`/v1/users/{id}/schedule` liefert deshalb bei **jedem** `filter[timestamp]`
dieselben eigenen Termine — und in der Weboberfläche stehen sie auch in den
Semesterferien im Stundenplan. Wer beim Ausrollen zu datierten Terminen
dieselbe Regel anwendet wie auf `seminar-cycle-dates` (nur innerhalb der
Vorlesungszeit), verliert sie in der vorlesungsfreien Zeit — im Wochenraster
stehen sie dann noch (das zeigt die Einträge unmittelbar), in der Tagesansicht
nicht mehr. `EventMerge.plannedSessions` unterscheidet die beiden Sorten
seit 1.4.0.


---

# Befunde aus Fassung 1.4.1

## 20. „Ist der Plan des kommenden Semesters leer?" ist die **falsche** Frage

`/v1/users/{id}/schedule` mischt zwei Sorten Eintrag, und nur eine davon hängt
am Semester:

| Ressource | Semesterbezug | Quelle |
| --- | --- | --- |
| `seminar-cycle-dates` | ja — `semester_courses.semester_id` | die belegten Veranstaltungen |
| `schedule-entries` | **nein** — `ScheduleEntry::findByUser_id()` läuft ohne Filter | selbst angelegte Blöcke |

Wer den Plan des kommenden Semesters mit `filter[timestamp]` holt und prüft,
ob die Antwort leer ist, prüft in Wahrheit: „Hat die Person irgendeinen eigenen
Termin?" Denn die kommen bei **jedem** Zeitstempel mit.

Genau daran hing Fassung 1.4.0. Zwei selbst angelegte Tutorien machten die
Antwort nicht-leer; das Raster zeigte in den Semesterferien deshalb *nur* diese
beiden, überschrieben mit „Vorschau auf das Wintersemester". Nach dem Löschen
der beiden in Stud.IP kippte die Antwort auf leer — und beim nächsten
Aktualisieren standen schlagartig alle Veranstaltungen des Sommersemesters im
Raster. Beide Zustände sahen nach einem Fehler aus; tatsächlich war es zweimal
dieselbe falsche Frage.

Richtig ist: **Führt der Plan schon `seminar-cycle-dates`?**
`SchedulePlan.hasCourses(_:)` prüft genau das, `SchedulePlan.resolve(...)`
entscheidet damit und setzt die eigenen Termine anschliessend in **jeden**
Plan — dedupliziert, denn sie stehen in beiden Antworten mit derselben Kennung.

## 21. Der Stundenplan der Weboberfläche zeigt das Semester, nicht die Gegenwart

`dispatch.php/calendar/schedule` zeigt in der vorlesungsfreien Zeit weiterhin
das volle Wochenraster des Semesters — die Veranstaltungen verschwinden dort
nicht, wenn die Vorlesungszeit endet. Das ist richtig so: Ein Raster beantwortet
„wie liegt meine Woche", nicht „was steht heute an".

StudGo hält es seit 1.4.1 genauso, sagt aber dazu, woran man ist: Über dem
Raster steht, zu welchem Semester der Plan gehört und wann dessen Vorlesungszeit
endete beziehungsweise die nächste beginnt, und die Veranstaltungsblöcke stehen
blasser, solange keine Vorlesungszeit läuft. Eigene Termine bleiben in voller
Farbe — die finden statt.

Beides sind **belegte** Angaben aus `Schemas/Semester` (`start-of-lectures`,
`end-of-lectures`). Der naheliegende Schritt weiter — je Veranstaltung „ist
beendet" schreiben — wäre dagegen eine Schätzung: Die Zuordnung der
ICS-Sitzungen zu einer Veranstaltung läuft über einen Namensabgleich
(`StudIPClient.matchCourse`), und ein verfehlter Abgleich erklärte eine
laufende Veranstaltung für beendet. Deshalb bleibt es bei der Semesterangabe.
