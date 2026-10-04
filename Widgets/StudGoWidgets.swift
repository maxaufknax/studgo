import SwiftUI
import WidgetKit

// MARK: - Eintrag

/// Ein Stand der Widgets zu einem Zeitpunkt. Die Einträge einer Timeline
/// unterscheiden sich nur im Zeitpunkt - der Schnappschuss bleibt derselbe,
/// die Ansicht leitet daraus ab, welcher Termin gerade dran ist und ob er
/// „in 25 Min“ beginnt oder schon läuft.
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
        // In der Widget-Galerie steht noch kein echter Stand - dort zeigt die
        // Vorschau den erfundenen, damit man sieht, was man hinzufügt.
        let snapshot: WidgetSnapshot? = context.isPreview ? WidgetSnapshot.placeholder
                                                          : WidgetSnapshotStore.load()
        completion(StudGoEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<StudGoEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date()

        // Ein Eintrag zu Beginn und zum Ende jedes Termins: „läuft gerade“
        // schaltet sich so von selbst um, und nach dem Ende steht der nächste
        // Termin da - ohne dass iOS die Erweiterung dafür wecken müsste. Bis
        // 1.8.1 kannte der Schnappschuss nur einen Termin; nach dessen Ende
        // blieb er als „Nächster Termin“ stehen.
        var entries = [StudGoEntry(date: now, snapshot: snapshot)]
        for date in snapshot?.changeDates(after: now) ?? [] {
            entries.append(StudGoEntry(date: date, snapshot: snapshot))
        }

        // Spätestens in zwei Stunden neu lesen - dann steht meist ein neuer
        // Schnappschuss der App bereit.
        completion(Timeline(entries: entries,
                            policy: .after(now.addingTimeInterval(2 * 3600))))
    }
}

// MARK: - Nächster Termin

/// Der nächste Termin auf Start- und Sperrbildschirm - dieselbe Auswahl wie
/// die Karte auf „Heute“ (siehe `TodayView.current(of:)`).
struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudGo.NaechsterTermin",
                            provider: SnapshotProvider()) { entry in
            NextEventView(entry: entry)
                .widgetURL(URL(string: "studgo://heute"))
        }
        .configurationDisplayName("Nächster Termin")
        .description("Was als Nächstes ansteht - aus dem Stundenplan und dem Kalender.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

private struct NextEventView: View {
    let entry: StudGoEntry
    @Environment(\.widgetFamily) private var family

    private var event: WidgetSnapshot.NextEvent? { entry.snapshot?.current(at: entry.date) }

    private var isRunning: Bool {
        guard let event, let snapshot = entry.snapshot else { return false }
        return snapshot.isRunning(event, at: entry.date)
    }

    var body: some View {
        content
            .containerBackgroundCompat(family: family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Startbildschirm

    @ViewBuilder
    private var small: some View {
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
            empty
        }
    }

    /// Mittel: links der Termin wie im kleinen Widget, rechts, was danach
    /// kommt. Die Frage „und dann?“ ist morgens die zweithäufigste.
    @ViewBuilder
    private var medium: some View {
        if event != nil {
            let next = entry.snapshot?.following(at: entry.date, limit: 3) ?? []
            HStack(alignment: .top, spacing: 14) {
                small
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !next.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Danach")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        ForEach(next.indices, id: \.self) { index in
                            followingRow(next[index])
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            empty
        }
    }

    private func followingRow(_ item: WidgetSnapshot.NextEvent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(dayAndTime(item.start))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            Text("Keine Termine")
                .font(.subheadline.weight(.medium))
            Text(entry.snapshot == nil ? "StudGo öffnen, um den Stand zu sehen"
                                       : "In den nächsten sieben Tagen steht nichts an")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
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
            Text(timeRange(event))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isRunning {
                Text("endet \(event.end, style: .relative)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text(event.start, style: .relative)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    // MARK: Sperrbildschirm

    /// Rechteckig unter der Uhr: Uhrzeit und Raum, Titel, Restzeit.
    @ViewBuilder
    private var rectangular: some View {
        if let event {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: isRunning ? "play.circle.fill" : "calendar")
                    Text(lockScreenLine(event))
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if isRunning {
                        Text("endet \(event.end, style: .relative)")
                    } else {
                        Text(event.start, style: .relative)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label("StudGo", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text("Keine Termine")
                    .font(.headline)
                Text(entry.snapshot == nil ? "App öffnen" : "Die nächsten 7 Tage frei")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Eine Zeile über der Uhr: Beginn und Titel.
    @ViewBuilder
    private var inline: some View {
        if let event {
            Label {
                if isRunning {
                    Text("\(event.title) bis \(event.end, style: .time)")
                } else {
                    Text("\(event.start, style: .time) \(event.title)")
                }
            } icon: {
                Image(systemName: "calendar")
            }
        } else {
            Label("Keine Termine", systemImage: "calendar")
        }
    }

    /// Rund: die Uhrzeit des Beginns - oder, während er läuft, die des Endes.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: isRunning ? "play.fill" : "calendar")
                    .font(.caption2)
                    .widgetAccentable()
                if let event {
                    Text(isRunning ? event.end : event.start, style: .time)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Text(verbatim: "–")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(2)
        }
    }

    // MARK: Formate

    private func timeRange(_ event: WidgetSnapshot.NextEvent) -> String {
        let from = event.start.formatted(date: .omitted, time: .shortened)
        let to = event.end.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }

    /// „10:15 · 1101-E001“ - heute nur die Uhrzeit, sonst mit Wochentag.
    private func lockScreenLine(_ event: WidgetSnapshot.NextEvent) -> String {
        var parts = [dayAndTime(event.start)]
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private func dayAndTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDate(date, inSameDayAs: entry.date) else { return time }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time
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
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

private struct UnreadMessagesView: View {
    let entry: StudGoEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int { max(0, entry.snapshot?.unreadMessages ?? 0) }

    var body: some View {
        content
            .containerBackgroundCompat(family: family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    private var small: some View {
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
                Text(verbatim: "\(count)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(count == 1 ? "ungelesene Nachricht" : "ungelesene Nachrichten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: count == 0 ? "envelope.open" : "envelope.fill")
                    .font(.caption)
                    .widgetAccentable()
                Text(verbatim: "\(count)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? Text("1 ungelesene Nachricht")
                                       : Text("\(count) ungelesene Nachrichten"))
    }

    @ViewBuilder
    private var inline: some View {
        if count == 0 {
            Label("Postfach gelesen", systemImage: "envelope.open")
        } else {
            Label("\(count) ungelesen", systemImage: "envelope")
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
///
/// Die Formate des Sperrbildschirms bekommen **keinen** Innenrand: Ihr Platz
/// ist ohnehin knapp bemessen, und das System rahmt sie selbst.
extension View {
    @ViewBuilder
    func containerBackgroundCompat(family: WidgetFamily) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget, alignment: .topLeading) { Color.clear }
        } else {
            switch family {
            case .accessoryCircular, .accessoryInline, .accessoryRectangular:
                self
            default:
                padding(12)
            }
        }
    }
}

// MARK: - Platzhalter für die Vorschau

extension WidgetSnapshot {
    /// Was die Vorschau in der Widget-Galerie zeigt - ein erfundener Stand,
    /// die Geräte fragen nie danach.
    static var placeholder: WidgetSnapshot {
        let now = Date()
        func session(_ title: String, inMinutes offset: Int, room: String) -> NextEvent {
            let start = now.addingTimeInterval(TimeInterval(offset * 60))
            return NextEvent(title: title, start: start,
                             end: start.addingTimeInterval(90 * 60), location: room)
        }
        let upcoming = [
            session(String(localized: "Übung: Analysis I"), inMinutes: 95,
                    room: String(localized: "Gebäude 1101, Raum 017")),
            session(String(localized: "Datenbanksysteme"), inMinutes: 215,
                    room: String(localized: "Gebäude 1101, Raum B305")),
            session(String(localized: "Programmieren 2"), inMinutes: 24 * 60 + 30,
                    room: String(localized: "Gebäude 3703, Raum 023")),
        ]
        return WidgetSnapshot(nextEvent: upcoming.first,
                              upcoming: upcoming,
                              unreadMessages: 3,
                              updatedAt: now)
    }
}
