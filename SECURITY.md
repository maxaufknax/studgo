# Sicherheit

StudGo hält nichts, was nicht das Gerät gehört: kein eigener Server, keine
Nutzerkonten unsererseits, kein Analytics. Die App trägt den Zugangstoken eines
Stud.IP-Kontos - deshalb steht jedes Design-Entscheidung unter der Frage, wie
diese Daten geschützt bleiben. Wer einen Weg findet, sie trotzdem zu erreichen,
soll es schnell melden.

## Melden

Mail an **maximilian.elias.paasch@gmail.com** mit `StudGo Sicherheit` im
Betreff. Bitte kein öffentliches Issue dazu aufmachen. Antwort in der Regel
innerhalb weniger Tage; Nennung im Changelog, wenn gewünscht.

## Im Umfang

- OAuth2-PKCE-Ablauf und Token-Aufbewahrung (`App/Core`, Keychain)
- Zwischenspeicher und offline gehaltene Dateien (`ResponseCache`, Downloads)
- Widget-Schnappschüsse (`Widgets/`, App Group)
- Demo-Modus (`DemoServer`): darf keine echten Kontodaten oder Server erreichen
- Landung und Verteilung: Codemagic-Pipeline, Signing, App-Store-Metadaten

## Nicht im Umfang

- Der Stud.IP-Server der Universität selbst: Er ist das vertrauensvolle
  Gegenüber, mit denselben Rechten wie die Weboberfläche.
- Der Browser-Spielraum von iOS (Jailbreak, entriegeltes Gerät in fremder Hand):
  Dagegen hilft das Betriebssystem, nicht die App.

## Wie dazu gedacht ist

Die Sicherheitsprüfung von 1.9.0 - Bedrohungsmodell, Befunde, offene Punkte -
liegt vollständig in [docs/SICHERHEIT.md](docs/SICHERHEIT.md). Datenschutz in
aller Ausführlichkeit steht in [PRIVACY.md](PRIVACY.md).
