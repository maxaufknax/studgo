import SwiftUI
import WidgetKit

// MARK: - Eintrag

/// Ein Stand der Widgets zu einem Zeitpunkt. Die Einträge einer Timeline
/// unterscheiden sich nur im Zeitpunkt - der Schnappschuss bleibt derselbe,
/// die Ansicht leitet daraus ab, ob der Termin „in 25 Min“ oder „läuft“
/// heißt.
struct StudGoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Quelle

/// Liefert die Timeline aus dem Schnappschuss, den die App hinterlegt hat
/// (siehe `WidgetSnapshotStore`). Fragt bewusst **nie** selbst beim Server
/// an: Eine Widget-Erweiterung läuft im eigenen Prozess, ohne Anmeldung und
/// meist ohne Netz.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudGoEntry {
        StudGoEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (StudGoEntry) -> Void) {
        completion(StudGoEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<StudGoEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date()

        // Einträge zum Beginn und zum Ende des Termins: „läuft gerade“
        // schaltet sich so von selbst um, ohne dass iOS die Erweiterung
        // dafür wecken müsste.
        var entries = [StudGoEntry(date: now, snapshot: snapshot)]
        if let event = snapshot?.nextEvent {
            if event.start > now {
                entries.append(StudGoEntry(date: event.start, snapshot: snapshot))
            }
            if event.end > now {
                entries.append(StudGoEntry(date: event.end, snapshot: snapshot))
            }
        }

        // Spätestens in zwei Stunden neu lesen - dann steht meist ein neuer
        // Schnappschuss der App bereit.
        completion(Timeline(entries: entries,
                            policy: .after(now.addingTimeInterval(2 * 3600))))
    }
}

// MARK: - Nächster Termin

/// Der nächste Termin auf dem Sperrbildschirm - dieselbe Auswahl wie die
/// Karte auf „Heute“ (siehe `TodayView.current(of:)`).
struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudGo.NaechsterTermin",
                           provider: SnapshotProvider()) { entry in
            NextEventView(entry: entry)
                .widgetURL(URL(string: "studgo://heute"))
        }
        .configurationDisplayName("Nächster Termin")
        .description("Was als Nächstes ansteht - aus dem Stundenplan und dem Kalender.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NextEventView: View {
    let entry: StudGoEntry

    private var event: WidgetSnapshot.NextEvent? { entry.snapshot?.nextEvent }
    private var isRunning: Bool {
        guard let event else { return false }
        return event.start <= entry.date && entry.date <= event.end
    }

    var body: some View {
        content
            .containerBackgroundCompat()
    }

    @ViewBuilder
    private var content: some View {
        if let event {
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                footer(for: event)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Text("Keine Termine")
                    .font(.subheadline.weight(.medium))
                Text(entry.snapshot == nil ? "StudGo öffnen, um den Stand zu sehen"
                                           : "Nichts im Kalender")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: isRunning ? "play.circle.fill" : "calendar")
                .font(.caption2)
            Text(isRunning ? "Läuft gerade" : "Nächster Termin")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    /// Uhrzeit und verbleibende Zeit - beides aus dem Eintragszeitpunkt, das
    /// Widget hält die Anzeige so ohne eigene Arbeit aktuell.
    @ViewBuilder
    private func footer(for event: WidgetSnapshot.NextEvent) -> some View {
        HStack(spacing: 8) {
            Text("\(event.start, style: .time) – \(event.end, style: .time)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if isRunning {
                Text("endet \(event.end, style: .relative)")
                    .font(.caption.weight(.semibold))
            } else {
                Text(event.start, style: .relative)
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

// MARK: - Ungelesene Nachrichten

/// Die Zahl der ungelesenen Nachrichten - dieselbe, die auf dem App-Symbol
/// und dem Postfach-Reiter steht.
struct UnreadMessagesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudGo.Ungelesen",
                            provider: SnapshotProvider()) { entry in
            UnreadMessagesView(entry: entry)
                .widgetURL(URL(string: "studgo://postfach"))
        }
        .configurationDisplayName("Ungelesene Nachrichten")
        .description("Wie viele Nachrichten im Stud.IP-Postfach noch offen sind.")
        .supportedFamilies([.systemSmall])
    }
}

private struct UnreadMessagesView: View {
    let entry: StudGoEntry

    private var count: Int { max(0, entry.snapshot?.unreadMessages ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "envelope")
                    .font(.caption2)
                Text("Postfach")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if entry.snapshot == nil {
                Text("StudGo öffnen")
                    .font(.subheadline.weight(.medium))
                Text("Dann steht hier, was im Postfach offen ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if count == 0 {
                Text("Alles gelesen")
                    .font(.subheadline.weight(.medium))
                Text("Keine neuen Nachrichten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(count == 1 ? "ungelesene Nachricht" : "ungelesene Nachrichten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Bundle

@main
struct StudGoWidgets: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        UnreadMessagesWidget()
    }
}

// MARK: - iOS-Unterstützung

/// `containerBackground` gibt es erst ab iOS 17; für iOS 16 genügt der
/// kleine Innenrand. Ohne diese Verzweigung scheitert der Bau am alten Ziel.
extension View {
    @ViewBuilder
    func containerBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget, alignment: .topLeading) { Color.clear }
        } else {
            padding(12)
        }
    }
}

// MARK: - Platzhalter für die Vorschau

extension WidgetSnapshot {
    /// Was die Vorschau in der Widget-Galerie zeigt - ein erfundener Stand,
    /// die Geräte fragen nie danach.
    static var placeholder: WidgetSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: 95, to: Date()) ?? Date()
        return WidgetSnapshot(
            nextEvent: NextEvent(title: "Übung: Analysis I",
                                 start: start,
                                 end: start.addingTimeInterval(90 * 60),
                                 location: "Gebäude 1101, Raum 017"),
            unreadMessages: 3,
            updatedAt: Date())
    }
}
