# SOGo als Mailclient in StudGo?

Stand: 2026-08-25. Alle Angaben gegen die Live-Systeme der LUH geprüft.

## Was die LUH betreibt

| | |
| --- | --- |
| Groupware | **SOGo** (Alinto), Build `202603301008` |
| Weboberfläche | `https://kalender.uni-hannover.de/SOGo/` |
| Alias | `webmail.uni-hannover.de` → 301 auf `kalender.uni-hannover.de` |
| CalDAV/CardDAV | `https://kalender.uni-hannover.de/SOGo/dav/` |
| DAV-Discovery | `/.well-known/caldav` → 301 auf `/SOGo/dav` ✅ |
| IMAP | `mail.uni-hannover.de:993` (Dovecot) |
| SMTP-Submission | `smtp.uni-hannover.de:587` |

## Der entscheidende Befund

```
$ curl -sI https://kalender.uni-hannover.de/SOGo/dav/ | grep -i www-authenticate
www-authenticate: basic realm="SOGo"

$ openssl s_client -connect mail.uni-hannover.de:993 ... <<< 'a CAPABILITY'
* OK [CAPABILITY IMAP4rev1 SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LITERAL+
      AUTH=PLAIN] Dovecot ready.
```

**Beide Wege kennen nur Benutzername + Passwort.**

- SOGos DAV-Endpunkt verlangt **HTTP Basic**.
- Dovecot bietet **ausschließlich `AUTH=PLAIN`** an — kein `AUTH=XOAUTH2`,
  kein `AUTH=OAUTHBEARER`.

Es gibt damit **keinen tokenbasierten Zugang zur Uni-Mail**. Ein in StudGo
eingebauter Mailclient müsste das zentrale LUH-Passwort abfragen und dauerhaft
auf dem Gerät vorhalten.

Das steht der Zusage an die Universität direkt entgegen: StudGo hat kein
Backend, spricht ausschließlich per OAuth mit Stud.IP und legt **nur Tokens**
in der Keychain ab — Tokens lassen sich serverseitig zurückziehen, ein
Passwort nicht. Ein Passwortfeld in der App wäre außerdem genau das Muster,
das Phishing-Schulungen den Studierenden abgewöhnen sollen.

**Empfehlung: keinen eigenen Mailclient in StudGo bauen.**

## Was stattdessen geht

### 1. SOGo im eingebauten Safari (empfohlen, sofort machbar)

Die SOGo-Oberfläche ist responsiv (`viewport width=device-width`) und auf dem
iPhone bedienbar. `App/Core/WebSheet.swift` gibt es bereits — derselbe
`SFSafariViewController`, mit dem StudGo das Ein- und Austragen zu
Veranstaltungen öffnet.

Der Punkt dabei: Der Controller läuft in einem **eigenen Prozess**. StudGo
sieht weder die Eingaben noch die Sitzung; die Cookies teilt er sich mit
Safari, wer dort angemeldet ist, ist es hier auch. Aus Datenschutzsicht ist
das sauber — die App wird zum Wegweiser, nicht zum Passwortempfänger.

Aufwand: eine Zeile pro Einstiegspunkt.

### 2. Auf Apple Mail und Kalender verweisen

Das eigentliche Ziel — Uni-Mail auf dem iPhone lesen — löst iOS besser, als
StudGo es je könnte: Account einmal in den Systemeinstellungen anlegen,
danach laufen Mail, Kalender und Kontakte mit Push, Widgets, Suche und
Systemintegration.

StudGo kann dabei helfen, ohne selbst Zugangsdaten anzufassen:

- eine **Anleitungsseite** mit den fertigen Serverdaten (siehe Tabelle oben),
- Kopierknöpfe für Hostnamen und Ports,
- ein `mailto:`-Link, der die eingerichtete Mail-App öffnet.

Eine `.mobileconfig` (Konfigurationsprofil) wäre der Komfortweg, muss aber
signiert und ausgeliefert werden und enthält je nach Bauart ebenfalls den
Benutzernamen — für den Nutzen ist das zu viel Apparat.

### 3. Kalender lesend einbinden (falls gewünscht)

Ein Weg an der Passwortfrage vorbei existiert für **Kalender**: SOGo kann
einen Kalender als geheime ICS-Adresse veröffentlichen
(*Kalender → Freigeben → Web-Adresse*). Diese Adresse trägt ihre eigene
Berechtigung im Pfad, ist also ohne Passwort abrufbar. StudGo könnte sie
speichern und die Termine neben denen aus Stud.IP anzeigen.

Zu bedenken: Wer die Adresse kennt, sieht den Kalender. Sie gehört in die
Keychain, nicht in `UserDefaults`, und der Nutzer muss verstehen, was er da
einträgt. **Stud.IP selbst bietet dasselbe** bereits an —
`GET /v1/users/{id}/events.ics`, und das sogar mit OAuth-Token.

## Was die ZQS ändern müsste, damit ein echter Posteingang möglich wird

Genau eine Sache: **`AUTH=XOAUTH2` in Dovecot gegen dieselbe IdM**, die schon
hinter dem Stud.IP-OAuth steht. Dann könnte StudGo denselben Token benutzen,
den es ohnehin hat, und ein echter Posteingang wäre ohne jedes Passwort
möglich. Google und Microsoft machen es für ihre Mailserver seit Jahren so.

Das ist eine sinnvolle Frage für die nächste Mail an Philipp Schüttlöffel —
zusammen mit der ohnehin offenen Bitte, Client 15 auf *public* umzustellen
(siehe `mail-an-philipp-public-client.md`). Solange sie offen ist, bleibt es
bei Weg 1 und 2.

## Fazit in einem Satz

SOGo lässt sich **verlinken**, nicht **integrieren** — und das ist hier die
richtige Entscheidung, nicht bloß die bequeme.
