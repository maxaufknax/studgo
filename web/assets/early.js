/* Läuft blockierend im <head>, bevor etwas gezeichnet wird: Erst mit dieser
   Klasse blendet das CSS die Abschnitte zum Einblenden aus. Ohne JavaScript
   bleibt alles sichtbar. Eigene Datei wegen script-src 'self'. */
document.documentElement.classList.add("js");
