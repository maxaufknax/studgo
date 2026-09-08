# App Review — der Vorgang zu 1.5.x

Zwei Ablehnungen, zwei Runden. Diese Datei hält beide fest und trägt den Text,
der ins Resolution Center gehört (das ist **nicht** Teil der
App-Store-Connect-API und muss von Hand eingefügt werden).

| Datum | Fassung | Beanstandung | Antwort |
| --- | --- | --- | --- |
| 2026-09-02 | 1.5.0 (24) | **5.2.5** „iPhone“ im Untertitel; **4.1(b)** LUH ohne Nachweis | Untertitel geändert, Universität aus App und Angaben entfernt → 1.5.1 |
| 2026-09-07 | 1.5.1 (25) | **1.2** fremde Inhalte ohne Schutzvorkehrungen | fünf Vorkehrungen eingebaut → 1.5.2 |
| 2026-09-08 | 1.5.2 (26) | — eingereicht, `WAITING_FOR_REVIEW` | Aufnahme als Anhang, Datenschutzerklärung berichtigt |

## Runde 2: Richtlinie 1.2

Apple verlangt fünf Dinge. Wo sie in StudGo stecken:

| Verlangt | In der App | Quelltext |
| --- | --- | --- |
| Zustimmung zu Nutzungsbedingungen **vor** der Anmeldung | Anmeldebildschirm, unter den Knöpfen; beide Knöpfe bleiben ohne Zustimmung gesperrt | `TermsGate`, `App/Core/Terms.swift` |
| Filter gegen anstößige Inhalte | verdeckt Beiträge („Inhalt verdeckt“), Schalter unter *Profil → Melden und Blockieren* | `ContentFilter` |
| Beiträge melden | langes Tippen auf jeden fremden Beitrag; in Detailansichten das „…“-Menü | `.moderated(_:)`, `ReportSheet` |
| Personen blockieren, Inhalte sofort weg | Kontextmenü und Personenblatt; Liste unter *Profil → Melden und Blockieren* | `Blocklist`, `ModerationStore.verdict` |
| Entwickler erfährt davon, reagiert in 24 h | POST an `studgo.maxaufknax.de/report`, Rückfall auf E-Mail | `ReportSubmitter`, `docker/studgo-reports/` |

Der Wortfilter vergleicht **ganze Wörter**. Das ist der Punkt, an dem solche
Filter üblicherweise scheitern: Ein `contains` verdeckte „Analysis“ wegen der
ersten vier Buchstaben. `ContentFilterTests` hält eine Liste harmloser
Uni-Wörter dagegen.

## Warum überhaupt ein Video, wo es doch die Demo gibt

Weil das Melden und das Blockieren **hinter einem langen Tippen** liegen. Ein
langer Druck hinterlässt keine Schaltfläche, kein Symbol, keinen Hinweis — wer
nicht weiss, dass es ihn gibt, findet ihn nicht. Genau das ist einem Prüfer in
Runde 2 passiert: Die Vorkehrungen waren in Build 25 noch gar nicht drin, aber
auch mit ihnen bleibt der Weg unsichtbar. Ein Mitschnitt ist der kürzeste
Beweis, dass er existiert.

Bei **PocketADM** kam die Frage nie auf: Dort schreibt niemand etwas, was ein
anderer zu sehen bekommt. Richtlinie 1.2 gilt nur für Apps mit fremden
Inhalten und greift dort schlicht nicht.

Wer das dauerhaft entschärfen will, hängt neben den langen Druck noch einen
sichtbaren Weg — das „…“-Menü gibt es in den Detailansichten bereits, in den
Listen nicht. Für diese Runde ist das nicht nötig; für die nächste Fassung ist
es die naheliegende Verbesserung.

## Zur Aufnahme

**Es gibt keine Längenbegrenzung.** Die vielzitierten 15–30 Sekunden gelten für
*App-Vorschauen* im Store, nicht für Anhänge im Resolution Center; Apple
dokumentiert dort weder eine Dauer noch ein Format. **90 Sekunden sind
richtig, und schneller abspielen wäre ein Fehler**: Was der Prüfer sehen muss —
dass beide Knöpfe grau sind, dass ein *langer* Druck das Menü öffnet, dass die
Zeile nach dem Blockieren verschwindet — ist genau das, was im Zeitraffer
verloren geht. Lieber ruhig und lesbar.

Was zählt, ist Apples eine ausdrückliche Bedingung: **auf einem echten
Gerät aufgenommen** („captured on a physical device“), kein Simulator.

| Szene | Was zu tun ist | Worauf es ankommt |
| --- | --- | --- |
| 1 — Bedingungen | App starten. Kurz auf beide Knöpfe deuten, dann unten „Nutzungsbedingungen lesen und annehmen" tippen, durch den Text scrollen, „Zustimmen und fortfahren" | Dass **beide** Knöpfe vorher grau sind und danach aktiv — das ist „presented **before** registering or logging in" |
| 2 — Melden | „Demo ohne Anmeldung ansehen" → *Postfach* → *Chats* → einen Faden öffnen → **lange** auf einen fremden Beitrag tippen → „Beitrag melden" → Grund wählen → „Senden" | Die Bestätigung „Die Meldung ist angekommen" ruhig eine Sekunde stehen lassen |
| 3 — Blockieren | Zurück zu *Postfach* → *Nachrichten* → lange auf eine Nachricht einer anderen Person → „Person blockieren" → „Blockieren" | Dass die Zeile **sofort** aus der Liste verschwindet — das ist Apples „remove it from the user's feed instantly" |
| 4 — Nachweis | *Campus*-Reiter → Personensymbol oben rechts → *Melden und Blockieren* | Die blockierte Person steht in der Liste, mit „Aufheben" |

**Vor der Aufnahme unbedingt: die App vom Gerät löschen** und Build 26 frisch
aus TestFlight installieren. Die Zustimmung liegt in den `UserDefaults`; ist
sie einmal erteilt, lässt sich der gesperrte Zustand nicht mehr zeigen, und
genau der ist Apples erster Punkt.

## Das Video geht über die API, nicht über das Resolution Center

Das war die Überraschung dieser Runde und der Grund, warum niemand mehr durch
die Weboberfläche muss: Ein Video **lässt sich per API anhängen**, nur eben an
einer anderen Stelle, als man sucht.

- **Resolution Center** — die Nachrichtenspur zur Ablehnung. Hat **keine** API,
  weder für den Text noch für Anhänge. Nur von Hand.
- **`appStoreReviewAttachments`** — der Anhang zu den *App Review
  Information*, direkt neben den Notizen für den Prüfer. **Hat eine API**, und
  genau dorthin gehört ein Demonstrationsvideo.

Der Ablauf ist dreistufig und steckt in `.secrets/`:

1. `POST /v1/appStoreReviewAttachments` mit `fileName` und `fileSize`, verwandt
   mit dem `appStoreReviewDetail` der Fassung. Apple antwortet mit fertigen
   `uploadOperations` — bei 51 MiB waren es elf Teile zu je 5 MiB.
2. Jeden Teil per `PUT` an die mitgelieferte URL, `Content-Type` aus den
   `requestHeaders`, Bytes per `dd skip=<offset> count=<length>`.
3. `PATCH` mit `uploaded: true` und `sourceFileChecksum` = **MD5 in
   Hexadezimal**. Die Antwort auf das PATCH zeigt den Anhang noch ohne
   Prüfsumme — das täuscht. Erst ein frisches `GET` sagt die Wahrheit:
   `assetDeliveryState.state` muss `COMPLETE` sein und `errors` leer.

**51 MiB gingen glatt durch**, obwohl im Umlauf oft von 50 MB die Rede ist.
Die Datei war trotz `.mp4`-Endung ein QuickTime-Container (`ftypqt`); Apple hat
sie mit `Content-Type: video/mp4` anstandslos genommen.

## Die Reihenfolge beim Abschicken

Erst alles an die Fassung hängen, dann einreichen:

1. **Notizen und Videoanhang** an den `appStoreReviewDetail` (siehe oben).
2. **`.secrets/submit-1.5.2.sh`** — zieht die abgelehnte Einreichung zurück,
   legt eine neue an, hängt Fassung 1.5.2 mit Build 26 hinein, schickt sie ab.
   Das Zurückziehen ist unvermeidlich: Eine Einreichung auf
   `UNRESOLVED_ISSUES` blockiert die Fassung und quittiert jeden neuen Versuch
   mit einem irreführenden 409 auf die *Version*.

Eine Antwort im Resolution Center ist danach **Kür, nicht Pflicht** — der
vollständige Text steht in den Notizen, das Video hängt an der Einreichung.
Wer trotzdem schreibt, nimmt den Text unten.

Nur zu antworten genügt dagegen **nicht**: Ohne neue Einreichung prüft Apple
weiter Build 25, in dem keine der fünf Vorkehrungen steckt.

## Der Text fürs Resolution Center

Hello,

thank you for the detailed review. All five precautions required by guideline
1.2 are implemented in build 26 (version 1.5.2), and the attached screen
recording, captured on a physical iPhone, shows the three you asked to see.

**1 — Terms of use before signing in.** The first screen now carries
"Nutzungsbedingungen lesen und annehmen" below the buttons. Until they are
accepted, both the sign-in button and the demo button are disabled, so no
content is reachable before agreement. The terms state explicitly that there
is no tolerance for objectionable content or abusive users, that offending
users are excluded from the app, and that reports are acted on within 24
hours. The same text is now filed as the app's custom license agreement in App
Store Connect and can be re-read in the app under Profil > Melden und
Blockieren > Nutzungsbedingungen.

**2 — Filtering objectionable content.** Posts containing abusive language are
replaced by a curtain ("Inhalt verdeckt — Könnte anstößig sein") with a
button to reveal them deliberately. It is on by default and can be switched in
Profil > Melden und Blockieren.

**3 — Flagging.** Every post written by someone else can be reported: long
press it and choose "Beitrag melden", or use the "…" menu at the top right of
any detail screen. This covers the chat (Blubber), the mailbox, course forums,
announcements, the activity feed and user profiles. The user picks a reason
and may add a note. The recording shows the long press, because that gesture
is the part a reviewer cannot discover by looking.

**4 — Blocking.** The same menu offers "Person blockieren", as does every user
profile. A blocked user disappears from every list in the app immediately —
posts, messages, forum entries and activity. Blocked users are listed under
Profil > Melden und Blockieren and can be unblocked there.

**5 — We are notified and act within 24 hours.** Every report and every block
is sent to a service we run for exactly this purpose
(https://studgo.maxaufknax.de/report) and filed there; a report additionally
raises an immediate alert on the developer's phone. If the endpoint cannot be
reached, the app opens a prepared email instead, so no report is lost. We
review every report within 24 hours, act on the content and eject the user who
posted it. Our privacy policy documents exactly what that endpoint receives;
the reporting user is not identified and no IP address is stored.

All of this is reachable without an account: on the first screen, accept the
terms, then tap "Demo ohne Anmeldung ansehen" (the bordered button with a play
icon). The demo runs on fictional data and contacts no university server; a
report sent from it does reach our report endpoint, which is the point of it.

Best regards,
Maximilian Paasch
