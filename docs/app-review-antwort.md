# Antwort an App Review — Reject vom 2026-09-02 (Submission 38557e5c…)

Apple hat 1.5.0 (Build 24) aus zwei Gründen abgelehnt:

- **5.2.5** — „iPhone" stand im Untertitel (`Stud.IP der LUH fürs iPhone`).
- **4.1(b)** — die Metadaten nannten die Leibniz Universität Hannover
  prominent; Apple wollte dafür einen dokumentierten Nachweis sehen.

**Entschieden am 2026-09-02:** Statt auf eine Bestätigung der Universität zu
warten, verschwindet die Universität aus App und Store-Angaben. StudGo ist
damit ein Client für Stud.IP, der zufällig auf eine bestimmte Installation
zeigt — und braucht keine fremde Marke mehr.

Das Resolution Center ist **nicht** Teil der App-Store-Connect-API; der
englische Text unten muss von Hand in ASC eingefügt werden. Die Prüfhinweise
(`appStoreReviewDetails.notes`), die derselbe Prüfer sieht, stehen bereits per
API auf demselben Stand.

## Was geändert wurde

| Wo | Vorher | Jetzt |
| --- | --- | --- |
| Untertitel | `Stud.IP der LUH fürs iPhone` | `Dein Studienalltag mit Stud.IP` |
| Beschreibung | begann mit der Universität, Disclaimer ganz unten | beginnt mit „privates, quelloffenes Studierendenprojekt … keine offizielle App einer Hochschule"; Universität kommt nicht mehr vor |
| Werbetext | „… der Leibniz Universität Hannover …" | „… aus deinem Stud.IP …", plus „Unabhängiges Studierendenprojekt" |
| Keywords | `Hannover,LUH,Uni,…` | `LUH` entfernt |
| Anmeldebildschirm | „Stud.IP der Leibniz Universität Hannover" | „Dein Stud.IP" + Unabhängigkeitshinweis |
| Einstellungen, Web-Blätter | „an der LUH", „Kennung der LUH" | „auf dem Campus", „Uni-Kennung" |
| Farbwelt | „Leibniz Blau — Das Blau der Leibniz Universität" | „StudGo Blau — Das Blau der Wortmarke" |

Stehen bleibt **eine** Nennung, und zwar bewusst: die Serveradresse
`studip.uni-hannover.de` im Datenschutzabschnitt und im Absatz „Welcher
Server". Ohne sie wüsste niemand vor dem Laden, mit welcher
Stud.IP-Installation die App spricht — das wäre irreführend, und irreführend
ist die andere Hälfte derselben Richtlinie.

## Ablauf bis zur Neueinreichung

1. ✅ Metadaten (Untertitel, Beschreibung, Werbetext, Keywords, Prüfhinweise)
2. ✅ App-Text und Farbwelt entmarkt
3. ⏳ Build 25 bei Codemagic (Tag `v1.5.1`)
4. ⏳ Version in ASC auf `1.5.1` setzen, Build anhängen
5. ⏳ Abgelehnte Submission `38557e5c…` canceln — sie steht auf
   `UNRESOLVED_ISSUES` und blockiert die Version, sonst kommt beim Einreichen
   ein irreführender 409
6. ⏳ Text unten ins Resolution Center, dann neu einreichen

---

Hello,

thank you for the detailed review. Both issues are addressed in build 25.

**Guideline 5.2.5 — Apple trademark in the subtitle**

You are right. The subtitle read "Stud.IP der LUH fürs iPhone". The word
"iPhone" has been removed; the subtitle now reads "Dein Studienalltag mit
Stud.IP". No Apple trademark or Apple-like design element appears in the app
name, subtitle, description, promotional text, keywords, icon or screenshots.

**Guideline 4.1(b) — reference to Leibniz University Hannover**

Rather than claim a relationship, we have removed the university from the app
and from its metadata:

- Subtitle, description, promotional text and keywords no longer name the
  university. The description now opens by stating that StudGo is a private,
  open-source student project and not an official app of any university.
- Inside the app, every user-facing string that named the university has been
  rewritten — sign-in screen, settings, in-app web sheets — and a colour theme
  that carried the university's name is now named after our own wordmark.
- No logo, wordmark, corporate colour or other brand asset of any university
  is or ever was used. The icon is our own wordmark, and every screenshot
  shows our own interface filled with fictional demo data.

One factual statement remains, and we would ask you to allow it: the server
address studip.uni-hannover.de, in the privacy section of the description and
in a short paragraph explaining which Stud.IP installation the app connects
to. Users need to know that before they download the app; leaving it out would
mislead them. Access to that server runs through an OAuth2 client (client_id
15) that the university's own IT service created for this app on August 24,
2026, and sign-in goes through the university's identity provider, so the
university controls and can withdraw access at any time.

For context: Stud.IP is campus management software by Stud.IP e.V. used by
around 70 German universities. StudGo is a client for it and describes itself
as such — in the same sense that a mail app is a client for an IMAP server. No
affiliation with Stud.IP e.V. or with any university is claimed anywhere.

To see the app without an account, tap "Demo ohne Anmeldung ansehen" on the
first screen (the bordered button with a play icon below the blue sign-in
button). It opens the complete app with fictional data and makes no network
request.

If anything is still missing, please tell us specifically what you need and we
will provide it.

Best regards,
Maximilian Paasch
