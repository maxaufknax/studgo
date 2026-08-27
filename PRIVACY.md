# Datenschutzerklärung für StudGo

**Stand: 27. August 2026**

> **In short (English):** StudGo has no backend. The app talks only to
> `studip.uni-hannover.de`, using the account *you* sign in with. Access
> tokens stay in the iOS keychain on your device, cached content stays in the
> app's sandbox. There is no analytics, no tracking, no advertising, and no
> third party receives any data. A built-in demo mode works entirely offline
> with fictional sample data. Contact: <maximilian.elias.paasch@gmail.com>.

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

**Es gibt keinen Server des Anbieters.** Die App spricht ausschließlich
direkt mit `studip.uni-hannover.de`. Es gibt keine Zwischenstelle, keine
Kopie deiner Daten an anderer Stelle und keinen Zugriff des Entwicklers auf
dein Konto.

## Welche Daten verarbeitet werden — und wo sie bleiben

| Daten | Wo sie liegen | Wer sie sieht |
| --- | --- | --- |
| Zugangstoken (OAuth) | iOS-Schlüsselbund deines Geräts | nur die App |
| Zwischenspeicher der zuletzt geladenen Listen | Sandbox der App auf dem Gerät | nur die App |
| Einstellungen (Farbwelt, Erinnerungen) | `UserDefaults` auf dem Gerät | nur die App |
| Deine Stud.IP-Inhalte | auf den Servern der LUH | wie in Stud.IP |

Alles davon verlässt dein Gerät nur in eine Richtung: zu
`studip.uni-hannover.de`, verschlüsselt über HTTPS, mit deinem eigenen
Zugangstoken — also genau so, wie wenn du dich im Browser bei Stud.IP
anmeldest.

## Was **nicht** passiert

- **Keine Analyse, keine Statistik, kein Tracking.** StudGo enthält kein
  Analyse-SDK, keine Absturzberichterstattung an Dritte und keine
  Werbekennungen.
- **Keine Werbung.**
- **Keine Weitergabe an Dritte.** Es gibt niemanden, an den etwas weiterginge.
- **Kein Zugriff des Entwicklers.** Weder auf dein Konto noch auf deine Daten.
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

- besteht **überhaupt keine Netzwerkverbindung**,
- stammen alle Inhalte aus erfundenen Beispieldaten in der App selbst,
- werden keinerlei Daten erhoben, gespeichert oder übertragen.

Was im Demo-Modus geschrieben wird, liegt nur im Arbeitsspeicher und ist beim
Verlassen der Demo verschwunden.

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

Da StudGo selbst keine Daten über dich speichert oder verarbeitet, gibt es
beim Entwickler nichts, worüber Auskunft zu erteilen oder was zu löschen
wäre. Die auf dem Gerät gehaltenen Daten löschst du vollständig, indem du
dich in der App abmeldest oder die App entfernst.

Für die Daten **in** Stud.IP ist die Leibniz Universität Hannover
verantwortlich; die Rechte nach DSGVO sind dort geltend zu machen.

## Änderungen

Änderungen dieser Erklärung erscheinen an dieser Stelle mit neuem Datum.
