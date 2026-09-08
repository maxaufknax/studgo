# Datenschutzerklärung für StudGo

**Stand: 8. September 2026**

> **In short (English):** StudGo signs you in to `studip.uni-hannover.de` with
> your own account and talks to it directly. Access tokens stay in the iOS
> keychain on your device, cached content stays in the app's sandbox. There is
> no analytics, no tracking, no advertising and no third-party SDK.
> **One exception:** if *you* report a post or block a person, that single
> report is sent to `studgo.maxaufknax.de/report`, a service run by the
> developer, so that abuse can be dealt with — see *Melden und Blockieren*
> below. That endpoint is the only server besides Stud.IP the app ever
> contacts, it is contacted only when you report or block, and it does not
> record who you are. A built-in demo mode uses fictional sample data and
> contacts no university server.
> Contact: <maximilian.elias.paasch@gmail.com>.

## Wer ist verantwortlich?

StudGo ist eine private, nicht-kommerzielle App von **Maximilian Paasch**,
Student an der Leibniz Universität Hannover.

Kontakt: <maximilian.elias.paasch@gmail.com>

StudGo ist **kein offizielles Angebot** der Leibniz Universität Hannover. Die
App greift lediglich auf die offizielle Schnittstelle des universitätseigenen
Stud.IP zu, mit einem dafür von der Universität ausgegebenen OAuth-Client.

## Was die App überhaupt tut

StudGo zeigt die Inhalte deines Stud.IP-Kontos auf dem iPhone: Stundenplan,
Veranstaltungen, Termine, Nachrichten, Ankündigungen, Dateien und die
Community-Bereiche.

**Für deine Studiendaten gibt es keine Zwischenstelle.** Stundenplan,
Nachrichten, Kurse und Dateien holt die App direkt bei
`studip.uni-hannover.de`, mit deinem eigenen Zugangstoken. Sie legt davon
keine Kopie an anderer Stelle ab, und der Entwickler hat keinen Zugriff auf
dein Konto.

Einen einzigen eigenen Server gibt es dennoch: die **Meldestelle** unter
`studgo.maxaufknax.de`. Sie kommt nur zum Zuge, wenn du selbst einen Beitrag
meldest oder eine Person blockierst. Was dann übertragen wird, steht unten
unter *Melden und Blockieren*.

## Welche Daten verarbeitet werden — und wo sie bleiben

| Daten | Wo sie liegen | Wer sie sieht |
| --- | --- | --- |
| Zugangstoken (OAuth) | iOS-Schlüsselbund deines Geräts | nur die App |
| Zwischenspeicher der zuletzt geladenen Listen | Sandbox der App auf dem Gerät | nur die App |
| Einstellungen (Farbwelt, Erinnerungen) | `UserDefaults` auf dem Gerät | nur die App |
| Deine Blockliste | `UserDefaults` auf dem Gerät | nur die App |
| Deine Stud.IP-Inhalte | auf den Servern der LUH | wie in Stud.IP |
| Eine von dir abgeschickte Meldung | Meldestelle des Entwicklers | nur der Entwickler |

Bis auf die letzte Zeile verlässt nichts davon dein Gerät in eine andere
Richtung als zu `studip.uni-hannover.de`, verschlüsselt über HTTPS, mit
deinem eigenen Zugangstoken — also genau so, wie wenn du dich im Browser bei
Stud.IP anmeldest.

## Melden und Blockieren

Die App zeigt Beiträge, die andere Menschen geschrieben haben. Damit du dich
dagegen wehren kannst — und damit der Entwickler von Missbrauch überhaupt
erfährt — geht eine Meldung an die Meldestelle
`https://studgo.maxaufknax.de/report`.

**Das passiert nur, wenn du es auslöst**: durch „Beitrag melden" oder durch
„Person blockieren". Ohne diese Handlung wird dorthin nichts übertragen.

Übertragen wird dabei genau das:

| Feld | Inhalt |
| --- | --- |
| Art | Meldung oder Blockierung |
| Grund | die von dir gewählte Kategorie |
| Ort und Kennung | wo der Beitrag in Stud.IP liegt |
| Verfasser | Name und Kennung der gemeldeten Person, soweit angezeigt |
| Auszug | höchstens 500 Zeichen des gemeldeten Beitrags |
| Anmerkung | dein freier Text, falls du einen schreibst |
| App-Fassung und Zeitpunkt | zur Einordnung |

**Wer meldet, wird nicht mitgeschickt.** Deine Kennung, dein Name und dein
Zugangstoken sind nicht Teil der Meldung; die Meldestelle speichert auch
deine IP-Adresse nicht. Sie zählt Anfragen je Adresse nur flüchtig im
Arbeitsspeicher mit, um Massenanfragen zu bremsen.

Die Meldung landet in einer Akte auf dem Server des Entwicklers und löst dort
einen Hinweis aus, damit sie **binnen 24 Stunden** bearbeitet wird.
Rechtsgrundlage ist Art. 6 Abs. 1 lit. f DSGVO — das berechtigte Interesse daran,
Missbrauch in der App zu unterbinden; dazu ist der Anbieter einer App mit
fremden Inhalten auch gegenüber Apple verpflichtet. Meldungen werden
gelöscht, sobald sie bearbeitet sind, spätestens nach zwölf Monaten.

Löschen kann der Entwickler einen Beitrag **nicht** — er steht in Stud.IP,
und dort entscheidet die Hochschule. Was er tut: den Fall prüfen und, wenn er
gegen die Nutzungsbedingungen verstößt, an die zuständige Stelle der
Hochschule weitergeben. Aus **deiner** Ansicht ist die blockierte Person
sofort verschwunden, unabhängig davon — die Blockliste wirkt auf dem Gerät
und braucht keine Bestätigung von aussen.

Ist die Meldestelle nicht erreichbar, öffnet die App stattdessen eine
vorbereitete E-Mail an den Entwickler. Abgeschickt wird sie nur, wenn du sie
abschickst.

## Was **nicht** passiert

- **Keine Analyse, keine Statistik, kein Tracking.** StudGo enthält kein
  Analyse-SDK, keine Absturzberichterstattung an Dritte und keine
  Werbekennungen.
- **Keine Werbung.**
- **Keine Weitergabe an Dritte.** Die Meldestelle läuft auf dem eigenen
  Server des Entwicklers; ein Dritter bekommt auch von dort nichts. Wird ein
  Fall an die Hochschule weitergegeben, geht dorthin nur, was zur Klärung
  nötig ist.
- **Kein Zugriff des Entwicklers auf dein Konto.** Er sieht weder deine
  Nachrichten noch deine Kurse noch deinen Stundenplan — nur das, was du ihm
  mit einer Meldung ausdrücklich schickst.
- **Kein Uni-Passwort in der App.** Die Anmeldung läuft über OAuth2 im
  Systembrowser direkt bei der Universität; StudGo bekommt die Eingabe nie zu
  sehen. Auch die Uni-Mail wird deshalb nur verlinkt und nicht eingebunden.

## Anmeldung

Die Anmeldung erfolgt über **OAuth2 mit PKCE** gegen
`studip.uni-hannover.de`. Der Anmeldebildschirm ist der der Universität
(Shibboleth, `login.uni-hannover.de`) und läuft in einem eigenen
Systemfenster (`ASWebAuthenticationSession`), auf das die App keinen Zugriff
hat.

Zurück kommt ein Zugangs- und ein Erneuerungstoken. Beide liegen im
Schlüsselbund des Geräts und werden beim Abmelden gelöscht.

## Demo-Modus

Wer keine Kennung der Leibniz Universität hat, kann die App über den Knopf
**„Demo ohne Anmeldung ansehen"** in Betrieb sehen. In diesem Modus

- besteht **keine Verbindung zu Stud.IP** und zu keinem Server der Hochschule,
- stammen alle Inhalte aus erfundenen Beispieldaten in der App selbst,
- werden über dich keinerlei Daten erhoben, gespeichert oder übertragen.

Was im Demo-Modus geschrieben wird, liegt nur im Arbeitsspeicher und ist beim
Verlassen der Demo verschwunden.

Eine Ausnahme gibt es auch hier: Wer in der Demo etwas **meldet**, dessen
Meldung geht wirklich an die Meldestelle — sonst wäre der Melde-Knopf eine
Attrappe. Die erfundenen Beispieldaten stehen dann darin, keine echten.

## Benachrichtigungen

StudGo verschickt **keine Push-Nachrichten** und betreibt dafür auch keinen
Server. Erinnerungen an Termine und der Hinweis auf neue Nachrichten sind
**lokale** Mitteilungen, die das Gerät selbst plant. Es wird dafür kein
Gerätetoken an irgendwen übermittelt.

## Weiterführende Verweise aus der App

Einige Funktionen gibt es in der Schnittstelle von Stud.IP nicht — etwa das
Ein- und Austragen zu Veranstaltungen oder die Prüfungsverwaltung. Dafür
öffnet StudGo die zuständige Seite der Universität im eingebauten Browser
(`SFSafariViewController`). Dieser läuft in einem eigenen Prozess; die App
sieht weder die Sitzung noch die Eingaben. Für diese Seiten gelten die
Datenschutzbestimmungen der jeweiligen Einrichtung.

## Deine Rechte

Die auf dem Gerät gehaltenen Daten — Token, Zwischenspeicher, Einstellungen,
Blockliste — löschst du vollständig, indem du dich in der App abmeldest oder
die App entfernst. Der Entwickler kommt an keines davon heran.

Beim Entwickler liegen ausschließlich die Meldungen, die jemand selbst
abgeschickt hat. Wer wissen will, ob und was über ihn dort steht, oder wer
eine Löschung wünscht, schreibt an
<maximilian.elias.paasch@gmail.com>; die Antwort kommt binnen eines Monats
(Art. 15 und 17 DSGVO). Weil Meldungen den Melder nicht benennen, ist die
Auskunft nur für die **gemeldete** Person möglich.

Für die Daten **in** Stud.IP ist die Leibniz Universität Hannover
verantwortlich; die Rechte nach DSGVO sind dort geltend zu machen.

## Änderungen

Änderungen dieser Erklärung erscheinen an dieser Stelle mit neuem Datum.
