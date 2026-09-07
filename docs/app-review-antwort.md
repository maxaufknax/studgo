# App Review — der Vorgang zu 1.5.x

Zwei Ablehnungen, zwei Runden. Diese Datei hält beide fest und trägt den Text,
der ins Resolution Center gehört (das ist **nicht** Teil der
App-Store-Connect-API und muss von Hand eingefügt werden).

| Datum | Fassung | Beanstandung | Antwort |
| --- | --- | --- | --- |
| 2026-09-02 | 1.5.0 (24) | **5.2.5** „iPhone“ im Untertitel; **4.1(b)** LUH ohne Nachweis | Untertitel geändert, Universität aus App und Angaben entfernt → 1.5.1 |
| 2026-09-07 | 1.5.1 (25) | **1.2** fremde Inhalte ohne Schutzvorkehrungen | fünf Vorkehrungen eingebaut → 1.5.2 |

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

## Was Maximilian noch tun muss

1. **Codemagic-Token erneuern** (`./tools/codemagic-setup.sh`) — der alte ist
   abgelaufen, der Tag `v1.5.2` liegt gepusht bereit, Build 26 fehlt noch.
2. **Bildschirmaufnahme auf einem echten iPhone.** Apple verlangt sie
   ausdrücklich; sie muss drei Dinge zeigen (Reihenfolge egal, ein Durchlauf
   genügt, ~60 Sekunden):
   * **Nutzungsbedingungen vor der Anmeldung** — App frisch starten, zeigen,
     dass „Mit Stud.IP anmelden“ und „Demo ohne Anmeldung ansehen“ **grau**
     sind, dann unten auf „Nutzungsbedingungen lesen und annehmen“ tippen,
     durch den Text scrollen, „Zustimmen und fortfahren“ drücken — und dass
     die Knöpfe jetzt aktiv sind.
   * **Melden** — Demo öffnen → *Postfach* → *Chats* → einen Faden öffnen →
     lange auf einen fremden Beitrag tippen → „Beitrag melden“ → Grund wählen
     → „Senden“ → die Bestätigung zeigen.
   * **Blockieren** — im selben Menü „Person blockieren“ (oder *Campus →
     Verzeichnis → Personen → eine Person → Person blockieren*) und zeigen,
     dass die Beiträge sofort verschwinden. Danach kurz *Profil → Melden und
     Blockieren* öffnen: Dort steht die Person, mit „Aufheben“.
3. **Aufnahme + Text unten** ins Resolution Center (Video als Anhang).

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
and may add a note.

**4 — Blocking.** The same menu offers "Person blockieren", as does every user
profile. A blocked user disappears from every list in the app immediately —
posts, messages, forum entries and activity. Blocked users are listed under
Profil > Melden und Blockieren and can be unblocked there.

**5 — We are notified and act within 24 hours.** Every report and every block
is sent to a service we run for exactly this purpose
(https://studgo.maxaufknax.de/report). It files the report and pushes a
message to the developer's phone immediately; if the endpoint cannot be
reached, the app opens a prepared email instead, so no report is lost. We
review every report within 24 hours, remove objectionable content and eject
the user who posted it.

All of this is reachable without an account: on the first screen, accept the
terms, then tap "Demo ohne Anmeldung ansehen" (the bordered button with a play
icon). The demo contains fictional data and makes no network request.

Best regards,
Maximilian Paasch
