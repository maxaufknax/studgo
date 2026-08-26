import SwiftUI

/// Der Stundenplan als Wochenraster — Wochentage nebeneinander, Uhrzeit von
/// oben nach unten. Eine Liste beantwortet „was kommt als Nächstes", ein
/// Raster beantwortet „wie liegt meine Woche": wo die Lücken sind, wann der
/// Tag endet, was sich überschneidet.
///
/// **Zur Geometrie:** Kopfzeile, Stundenleiste und Tagesspalten rechnen alle
/// mit demselben `Layout` und mit **ganzen Punkten**. Vorher teilte jede
/// Stelle die verfügbare Breite für sich neu auf; bei sechs oder sieben
/// Spalten kamen dabei krumme Werte heraus, und Wochentag, Stundenlinie und
/// Block standen sichtbar gegeneinander versetzt. Die Höhe war zusätzlich
/// fest verdrahtet — im Querformat lief das Raster deshalb unten aus dem Bild.
struct TimetableView: View {
    let entries: [ScheduleEntry]
    /// Welche Wochentage nebeneinander stehen (1 = Montag … 7 = Sonntag).
    /// `nil` heißt: Montag bis Freitag plus alles, worauf ein Termin fällt.
    ///
    /// Mit fünf Spalten ist eine Telefonspalte rund 60 Punkte breit — darin
    /// steht von „Grundlagen der Rechnerarchitektur" nichts Lesbares. Deshalb
    /// bestimmt der Kalender die Spaltenzahl (3 / Mo–Fr / ganze Woche).
    var visibleDays: [Int]?
    /// Blasser setzen, was gerade **nicht stattfindet**.
    ///
    /// In der vorlesungsfreien Zeit steht der Plan des Semesters weiterhin im
    /// Raster — so hält es auch die Weboberfläche, und wer nachschlagen will,
    /// wann seine Vorlesung lag, findet sie nur dort. Stattfinden tut sie
    /// aber nicht. Betroffen sind allein die Veranstaltungen; selbst angelegte
    /// Termine laufen ganzjährig und bleiben in voller Farbe.
    var dimsCourses = false
    var onSelect: (ScheduleEntry) -> Void = { _ in }

    // MARK: - Maße

    private let rulerWidth: CGFloat = 44
    private let headerHeight: CGFloat = 32
    /// Luft zwischen zwei Blöcken derselben Spalte.
    private let blockGap: CGFloat = 2
    /// Wie viele Punkte eine Minute mindestens und höchstens hoch ist.
    /// Die Untergrenze hält eine 90-Minuten-Sitzung beschriftbar, die
    /// Obergrenze verhindert, dass ein einzelner Kurs die Woche sprengt.
    private let minScale: CGFloat = 0.55
    private let maxScale: CGFloat = 1.30

    /// Alles, was Kopfzeile und Raster gemeinsam brauchen — einmal gerechnet,
    /// damit nichts auseinanderlaufen kann.
    private struct Layout {
        let days: [Int]
        let dayWidth: CGFloat
        let rulerWidth: CGFloat
        let startMinute: Int
        let endMinute: Int
        let scale: CGFloat

        var spanMinutes: Int { endMinute - startMinute }
        var gridHeight: CGFloat { CGFloat(spanMinutes) * scale }
        var hours: [Int] { stride(from: startMinute, through: endMinute, by: 60).map { $0 } }

        func y(of minute: Int) -> CGFloat { CGFloat(minute - startMinute) * scale }
        func x(of day: Int) -> CGFloat {
            CGFloat(days.firstIndex(of: day) ?? 0) * dayWidth
        }
    }

    /// Sonntag kommt aus Stud.IP mal als 7, mal als 0.
    private var days: [Int] {
        if let visibleDays, !visibleDays.isEmpty { return visibleDays }
        // Montag bis Freitag stehen immer, damit ein leerer Freitag als
        // freier Tag sichtbar wird statt einfach zu fehlen.
        return Set(1...5).union(Set(entries.map(\.normalizedWeekday))).sorted()
    }

    /// Angezeigter Zeitraum, auf volle Stunden gerundet und auf mindestens
    /// sechs Stunden gestreckt — sonst stünde ein einzelnes Seminar als
    /// haushoher Block allein im Bild.
    private var span: (start: Int, end: Int) {
        let starts = entries.map(\.startMinutes)
        let ends = entries.map(\.endMinutes)
        guard let earliest = starts.min(), let latest = ends.max() else {
            return (8 * 60, 18 * 60)
        }
        var from = max(0, (earliest / 60) * 60)
        var to = min(24 * 60, ((latest + 59) / 60) * 60)
        while to - from < 6 * 60 {
            if to < 24 * 60 { to += 60 } else if from > 0 { from -= 60 } else { break }
        }
        return (from, to)
    }

    private func makeLayout(in size: CGSize) -> Layout {
        let columns = days
        // Auf ganze Punkte abrunden und den Rest der Stundenleiste geben:
        // So sitzt jede Spaltengrenze auf einer ganzen Bildschirmzeile.
        let usable = max(0, size.width - rulerWidth)
        let dayWidth = max(34, (usable / CGFloat(columns.count)).rounded(.down))
        let leftover = usable - dayWidth * CGFloat(columns.count)

        let bounds = span
        let available = max(0, size.height - headerHeight - 1)
        let fitting = available / CGFloat(max(1, bounds.end - bounds.start))
        let scale = min(maxScale, max(minScale, fitting))

        return Layout(days: columns,
                      dayWidth: dayWidth,
                      rulerWidth: rulerWidth + leftover,
                      startMinute: bounds.start,
                      endMinute: bounds.end,
                      scale: scale)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = makeLayout(in: geometry.size)

            VStack(spacing: 0) {
                header(layout)
                Divider()

                ScrollView(.vertical) {
                    grid(layout)
                        // Oben etwas Luft, damit die erste Stundenzahl nicht
                        // halb unter der Kopfzeile klemmt — sie sitzt auf der
                        // Linie und ragte deshalb nach oben heraus.
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Kopfzeile

    private func header(_ layout: Layout) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: layout.rulerWidth)
            ForEach(layout.days, id: \.self) { day in
                let isToday = day == Weekday.today
                VStack(spacing: 2) {
                    Text(Weekday.short(day))
                        .font(.caption.weight(isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                    Circle()
                        .fill(isToday ? Color.accentColor : .clear)
                        .frame(width: 4, height: 4)
                }
                .frame(width: layout.dayWidth)
                .accessibilityLabel(Weekday.full(day))
            }
        }
        .frame(height: headerHeight)
    }

    // MARK: - Raster

    private func grid(_ layout: Layout) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ruler(layout)
            ForEach(layout.days, id: \.self) { day in
                column(for: day, layout: layout)
            }
        }
        .frame(height: layout.gridHeight, alignment: .top)
        .overlay(alignment: .topLeading) { nowLine(layout) }
    }

    private func ruler(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.hours, id: \.self) { minute in
                Text(Format.clock(minutes: minute))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: layout.rulerWidth - 7, alignment: .trailing)
                    // Um die halbe Zeilenhöhe nach oben, damit die
                    // Beschriftung auf der Linie sitzt und nicht darunter.
                    .offset(y: layout.y(of: minute) - 6)
            }
        }
        .frame(width: layout.rulerWidth, height: layout.gridHeight, alignment: .topLeading)
    }

    private func column(for day: Int, layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            // Der heutige Tag zuerst — als Hintergrund, nicht über die Linien.
            if day == Weekday.today {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.07))
                    .frame(width: layout.dayWidth, height: layout.gridHeight)
            }

            // Breite ausdrücklich: ein dehnbares Rechteck im ZStack würde
            // sonst die Spaltenbreite mitbestimmen, statt sie zu übernehmen.
            ForEach(layout.hours, id: \.self) { minute in
                Rectangle()
                    .fill(Color(.separator).opacity(0.35))
                    .frame(width: layout.dayWidth, height: 0.5)
                    .offset(y: layout.y(of: minute))
            }

            ForEach(placements(for: day)) { placement in
                block(placement, layout: layout)
            }
        }
        .frame(width: layout.dayWidth, height: layout.gridHeight, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(.separator).opacity(0.35))
                .frame(width: 0.5)
        }
    }

    /// Die aktuelle Uhrzeit als feine Linie quer über den heutigen Tag.
    @ViewBuilder
    private func nowLine(_ layout: Layout) -> some View {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: Date()) * 60
            + calendar.component(.minute, from: Date())
        if layout.days.contains(Weekday.today),
           minutes >= layout.startMinute, minutes <= layout.endMinute {
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1)
            }
            .frame(width: layout.dayWidth)
            .offset(x: layout.rulerWidth + layout.x(of: Weekday.today),
                    y: layout.y(of: minutes) - 2.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func block(_ placement: Placement, layout: Layout) -> some View {
        let entry = placement.entry
        let lane = (layout.dayWidth - blockGap) / CGFloat(placement.columnCount)
        let width = lane - blockGap
        let height = max(20, CGFloat(entry.endMinutes - entry.startMinutes) * layout.scale - blockGap)
        let isDormant = dimsCourses && entry.isCourse

        return Button {
            onSelect(entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(height > 46 ? 3 : 1)
                if let location = entry.location, height > 54 {
                    Text(location)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Tint.surface(entry.tintSeed))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Tint.color(entry.tintSeed))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
            .foregroundStyle(Tint.color(entry.tintSeed))
            // Nur die Deckkraft, keine graue Ersatzfarbe: Der Block soll als
            // *derselbe* Kurs erkennbar bleiben — die Farbe ist in Kursliste,
            // Terminliste und Raster dieselbe und trägt hier die Zuordnung.
            .opacity(isDormant ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .offset(x: blockGap + CGFloat(placement.column) * lane,
                y: layout.y(of: entry.startMinutes))
        .accessibilityLabel("\(entry.title), \(Weekday.full(entry.normalizedWeekday)) \(entry.timeRange)")
        .accessibilityValue(isDormant ? "Findet zurzeit nicht statt" : "")
        .accessibilityHint("Öffnet die Einzelheiten")
    }

    // MARK: - Überschneidungen

    private struct Placement: Identifiable {
        let entry: ScheduleEntry
        let column: Int
        let columnCount: Int
        var id: String { entry.id }
    }

    /// Termine, die sich zeitlich überlappen, teilen sich die Spaltenbreite.
    /// Ohne das läge eine Übung unsichtbar unter der Vorlesung.
    private func placements(for day: Int) -> [Placement] {
        let sorted = entries
            .filter { $0.normalizedWeekday == day }
            .sorted { $0.startMinutes < $1.startMinutes }
        guard !sorted.isEmpty else { return [] }

        // Jede Spalte sammelt Termine, die einander nicht überschneiden.
        var lanes: [[ScheduleEntry]] = []
        for entry in sorted {
            if let index = lanes.firstIndex(where: { ($0.last?.endMinutes ?? 0) <= entry.startMinutes }) {
                lanes[index].append(entry)
            } else {
                lanes.append([entry])
            }
        }

        return lanes.enumerated().flatMap { index, lane in
            lane.map { Placement(entry: $0, column: index, columnCount: lanes.count) }
        }
    }
}
