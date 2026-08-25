# Wie vollständig ist StudGo?

Stand: **2026-08-25**, Fassung 1.2.0. Gegenübergestellt werden drei Dinge:
was die **Stud.IP-Weboberfläche** an der LUH kann, was die **JSON:API**
überhaupt hergibt, und was **StudGo** heute daraus macht.

Grundlage sind keine Vermutungen, sondern zwei Quellen aus dem Stud.IP-6.0-
Quelltext: `lib/navigation/*.php` (was die Weboberfläche anbietet) und
`lib/classes/JsonApi/RouteMap.php` (die 343 Routen der Schnittstelle).

Legende: ✅ vollständig · 🟡 teilweise · ⬜ noch nicht · 🚫 über die
Schnittstelle nicht möglich

---

## Kurzfassung

StudGo deckt den **studentischen Alltag** ab — Stundenplan, Veranstaltungen,
Dateien, Nachrichten, Ankündigungen, Forum, Wiki, Blubber, Kontakte,
Sprechstunden. Das sind die Bereiche, die man mehrmals pro Woche anfasst.

Nicht abgedeckt sind vor allem drei Dinge, und sie unterscheiden sich in der
Ursache:

1. **Courseware** — der größte offene Bereich. Die Schnittstelle kann es
   (rund 50 Routen), StudGo noch nicht. Das ist Arbeit, kein Hindernis.
2. **Alles Verwaltende** — Profil bearbeiten, Passwort, Zwei-Faktor,
   Einstellungen, Ein- und Austragen in Veranstaltungen. Die JSON:API bietet
   dafür schlicht **keine** Routen. Diese Wege führen dauerhaft über die
   Weboberfläche; StudGo verlinkt sie an Ort und Stelle.
3. **Uni-Mail** — technisch möglich, aber nur gegen das zentrale
   Uni-Passwort. Bewusst ausgelassen, Begründung in `SOGO-MAIL.md`.

Für den täglichen Gebrauch heißt das: **Was man unterwegs mit dem Telefon tun
will, geht.** Was man einmal im Semester am Rechner erledigt, geht nicht.

---

## Mein Arbeitsplatz

| Stud.IP | JSON:API | StudGo |
| --- | --- | --- |
| Übersicht / Startseite | – | ✅ Reiter **Heute**: laufender und nächster Termin mit Countdown, was heute noch kommt, demnächst, ungelesene Nachrichten, Ankündigungen |
| Ankündigungen lesen | `GET /users/{id}/news`, `/studip/news`, `/courses/{id}/news` | ✅ eigene und universitätsweite, mit Auszeichnung gesetzt |
| Ankündigungen **verfassen** | `POST /users/{id}/news`, `/courses/{id}/news` | ⬜ möglich, noch nicht gebaut |
| Ankündigungen kommentieren | `GET`/`POST /news/{id}/comments` | ⬜ Lesen im Client vorhanden, ohne Oberfläche |
| Dateien: Veranstaltungsordner | `/courses/{id}/folders` → `/folders/{id}/file-refs` | ✅ Ordnerbaum, Vorschau, Teilen, Download |
| Dateien: **persönliche Ablage** | `/users/{id}/folders`, `/users/{id}/file-refs` | ⬜ Route vorhanden, noch nicht gebaut |
| Dateien **hochladen**, Ordner anlegen | `POST /folders/{id}/file-refs`, `POST .../folders` | ⬜ möglich, noch nicht gebaut |
| Courseware (Lernmaterialien) | ~50 Routen (`/courseware-*`) | ⬜ **größte Lücke** |
| Fragebögen | – | 🚫 keine Route |
| Merkzettel (Clipboard) | `/clipboards`, `/clipboard-items` | ⬜ möglich, geringer Nutzen unterwegs |

## Veranstaltungen

| Stud.IP | JSON:API | StudGo |
| --- | --- | --- |
| Meine Veranstaltungen | `GET /users/{id}/courses` | ✅ mit Semesterfilter, laufendes Semester vorgewählt |
| Veranstaltung: Übersicht, Beschreibung | `GET /courses/{id}` | ✅ inklusive korrekt gesetzter Beschreibung (Stud.IP-Auszeichnung) |
| Ablaufplan / Termine | `GET /courses/{id}/events` | ✅ anstehend und vergangen, **jede Sitzung einzeln zu öffnen** |
| Teilnehmende | `GET /courses/{id}/memberships` | ✅ nach Rolle gruppiert, mit Nachricht/Sprechstunde/Kontakt |
| Dateien | s. o. | ✅ |
| Forum lesen und antworten | `/forum-categories`, `/entries` | ✅ Bereich → Thema → Antwort |
| Forum: **neues Thema** | `POST /forum-categories/{id}/entries` | ⬜ Antworten geht, neues Thema noch nicht |
| Wiki lesen | `GET /courses/{id}/wiki-pages` | ✅ mit Auszeichnung, Startseite oben |
| Wiki **bearbeiten** | `POST`/`PATCH /wiki-pages/{id}` | ⬜ möglich, noch nicht gebaut |
| Blubber der Veranstaltung | `/courses/{id}/blubber-threads` | ✅ lesen und schreiben |
| Ankündigungen der Veranstaltung | `/courses/{id}/news` | ✅ |
| **Ein- und Austragen** | – | 🚫 `Rel\Memberships::authorize()` gibt für alles außer `GET` hart `false` zurück. StudGo öffnet dafür die Weboberfläche. |
| Sichtbarkeit in der Teilnehmendenliste | `PATCH /course-memberships/{id}` | 🟡 im Client vorhanden, ohne Oberfläche |
| Freie Veranstaltungen / Suche | `GET /courses` mit `filter[q]` | ✅ ganzes Vorlesungsverzeichnis, Suche in Titel/Lehrenden/Nummer, Semesterfilter |
| Modulverzeichnis (MVV), Studienbereiche | `/modules`, `/study-areas`, `/tree-node` | ⬜ möglich, noch nicht gebaut |

## Stundenplan und Kalender

| Stud.IP | JSON:API | StudGo |
| --- | --- | --- |
| Stundenplan (Woche) | `GET /users/{id}/schedule` | ✅ Wochenraster mit Überschneidungen, Jetzt-Linie, angepasst an Hoch- und Querformat |
| Terminliste | `GET /users/{id}/events` | ✅ nach Tagen, **jeder Termin zu öffnen** |
| Termindetails (Raum, Turnus, Thema) | Attribute `recurrence`, `categories` | ✅ |
| Termin **anlegen oder ändern** | – | 🚫 Es gibt **nur** `GET` für `events` und `schedule-entries`. Der Kalender ist über die Schnittstelle nur lesbar. |
| Kalender abonnieren (iCal) | `GET /users/{id}/events.ics` | ⬜ Möglichkeit, den Plan in die Kalender-App zu legen |
| Feiertage | `GET /holidays` | ⬜ |

## Nachrichten und Community

| Stud.IP | JSON:API | StudGo |
| --- | --- | --- |
| Nachrichten lesen, senden, antworten | `/inbox`, `/outbox`, `POST /messages` | ✅ mit Gelesen-Markierung und Empfängersuche |
| Blubber | `/blubber-threads`, `/comments` | ✅ Verlauf **mit den neuesten Beiträgen zuerst geladen**, Älteres nachladbar, schreiben |
| Kontakte | `/users/{id}/contacts`, `relationships/contacts` | ✅ ansehen, hinzufügen, entfernen |
| Personensuche | `GET /users` mit `filter[search]` | ✅ |
| Studiengruppen: meine | aus `/users/{id}/courses` gefiltert | ✅ (die API hat dafür keine eigene Route) |
| Studiengruppen: Vorschläge | `GET /studygroup-proposals` | ✅ |
| Studiengruppen: Suche | `GET /courses` mit `filter[category]` | ✅ |
| Studiengruppe **gründen / beitreten** | – | 🚫 wie beim Eintragen: nur über die Weboberfläche |
| Sprechstunden buchen | `/consultations` → `/slots` → `/bookings` | ✅ inklusive Absage |
| Wer ist online? | – | 🚫 keine Route |
| Rangliste | – | 🚫 Die Weboberfläche hat eine Rangliste (`CommunityNavigation`), die JSON:API bietet dafür **keine** Route. |
| Aktivitätenstrom | `GET /users/{id}/activitystream` | ✅ „Was passiert", filterbar, **jeder Eintrag zu öffnen** |

## Profil und Einstellungen

| Stud.IP | JSON:API | StudGo |
| --- | --- | --- |
| Eigenes Profil ansehen | `GET /users/me` | ✅ |
| Profil **bearbeiten**, Bild, Studiendaten | – | 🚫 keine Route |
| Passwort, Zwei-Faktor, Datenschutz, Vertretung | – | 🚫 keine Route |
| Einrichtungen, denen man angehört | `/users/{id}/institute-memberships` | ✅ |
| Semesterübersicht | `GET /semesters` | ✅ mit Vorlesungszeiten |
| Darstellung | – | ✅ acht Farbwelten, hell/dunkel/automatisch, dichtere Listen (**Vorschau wechselt jetzt sofort**) |

## Nicht Stud.IP

| Wunsch | Stand |
| --- | --- |
| Uni-Mail im Posteingang | 🚫 bewusst nicht. Dovecot an der LUH bietet nur `AUTH=PLAIN`, SOGo nur HTTP Basic — es gäbe keinen Weg ohne das zentrale Uni-Passwort in der App. StudGo verlinkt SOGo und zeigt die Serverdaten für die Mail-App des Geräts. Ausführlich: `SOGO-MAIL.md`. |
| Push-Benachrichtigungen | ⬜ bräuchte einen eigenen Server, der für dich pollt — StudGo hat bewusst kein Backend. |
| Offline-Betrieb | ✅ die zuletzt geladenen Listen liegen auf dem Gerät, die App startet ohne Empfang mit dem letzten Stand |

---

## Was als Nächstes am meisten brächte

In dieser Reihenfolge, nach Nutzen je Aufwand:

1. **Kalender-Abo (`events.ics`)** — eine Zeile Arbeit, und der Stundenplan
   steht in der Kalender-App des Telefons, inklusive Mitteilungen. Das ist
   der billigste Ersatz für die fehlenden Push-Nachrichten.
2. **Persönliche Dateien und Datei-Upload** — die Routen sind da, und
   „schnell das Foto der Tafel in den Kursordner" ist genau das, wofür man
   das Telefon dabeihat.
3. **Ankündigung verfassen und Forenthema eröffnen** — kleine Ergänzungen,
   machen die App vom Lesegerät zum Arbeitsgerät.
4. **Courseware** — der große Brocken. Lohnt nur, wenn deine Veranstaltungen
   ihn tatsächlich benutzen; das ist von Fach zu Fach sehr verschieden.
