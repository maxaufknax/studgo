import SwiftUI

/// Der Stundenplan als Wochenraster — Wochentage nebeneinander, Uhrzeit von
/// oben nach unten. Eine Liste beantwortet „was kommt als Nächstes", ein
/// Raster beantwortet „wie liegt meine Woche": wo die Lücken sind, wann der
/// Tag endet, was sich überschneidet.
struct TimetableView: View {
    let entries: [ScheduleEntry]
    var onSelect: (ScheduleEntry) -> Void = { _ in }

    /// Höhe einer Minute in Punkten. 0,9 zeigt einen Tag von 8 bis 20 Uhr
    /// ohne Scrollen und lässt eine 90-Minuten-Sitzung noch beschriftbar.
    private let scale: CGFloat = 0.9
    private let rulerWidth: CGFloat = 38

    /// Sonntag kommt aus Stud.IP mal als 7, mal als 0.
    private var days: [Int] {
        let used = Set(entries.map(\.normalizedWeekday))
        // Montag bis Freitag stehen immer, damit ein leerer Freitag als
        // freier Tag sichtbar wird statt einfach zu fehlen.
        let base = Set(1...5)
        return base.union(used).sorted()
    }

    /// Angezeigter Zeitraum, auf volle Stunden gerundet.
    private var span: (start: Int, end: Int) {
        let starts = entries.map(\.startMinutes)
        let ends = entries.map(\.endMinutes)
        guard let earliest = starts.min(), let latest = ends.max() else {
            return (8 * 60, 18 * 60)
        }
        return (max(0, (earliest / 60) * 60),
                min(24 * 60, ((latest + 59) / 60) * 60))
    }

    private var hours: [Int] {
        stride(from: span.start, through: span.end, by: 60).map { $0 }
    }

    private var gridHeight: CGFloat { CGFloat(span.end - span.start) * scale }

    var body: some View {
        GeometryReader { geometry in
            // Ohne Mindestbreite: bei sechs oder sieben Tagen würde eine
            // feste Untergrenze die letzte Spalte aus dem Bild schieben,
            // und ein zusätzliches seitliches Scrollen ließe die Kopfzeile
            // stehenbleiben. Schmaler ist hier besser als abgeschnitten.
            let dayWidth = max(1, (geometry.size.width - rulerWidth) / CGFloat(days.count))

            VStack(spacing: 0) {
                header(dayWidth: dayWidth)
                Divider()

                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        ruler
                        ForEach(days, id: \.self) { day in
                            column(for: day, width: dayWidth)
                        }
                    }
                    .frame(height: gridHeight, alignment: .top)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Kopfzeile

    private func header(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: rulerWidth)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 1) {
                    Text(Self.shortName(day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(day == Self.todayWeekday ? Color.accentColor : .primary)
                    if day == Self.todayWeekday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear.frame(height: 4)
                    }
                }
                .frame(width: dayWidth)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Stundenleiste

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { minute in
                Text(Format.clock(minutes: minute))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: rulerWidth - 6, alignment: .trailing)
                    // Um die halbe Zeilenhöhe nach oben, damit die
                    // Beschriftung auf der Linie sitzt und nicht darunter.
                    .offset(y: CGFloat(minute - span.start) * scale - 6)
            }
        }
        .frame(width: rulerWidth, height: gridHeight, alignment: .topLeading)
    }

    // MARK: - Tagesspalte

    private func column(for day: Int, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Der heutige Tag zuerst — als Hintergrund, nicht über die Linien.
            if day == Self.todayWeekday {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.06))
                    .frame(width: width, height: gridHeight)
            }

            // Stundenlinien
            ForEach(hours, id: \.self) { minute in
                Rectangle()
                    .fill(Color(.separator).opacity(0.35))
                    .frame(height: 0.5)
                    .offset(y: CGFloat(minute - span.start) * scale)
            }

            ForEach(placements(for: day)) { placement in
                block(placement, dayWidth: width)
            }
        }
        .frame(width: width, height: gridHeight, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(.separator).opacity(0.35))
                .frame(width: 0.5)
        }
    }

    private func block(_ placement: Placement, dayWidth: CGFloat) -> some View {
        let entry = placement.entry
        let width = (dayWidth - 4) / CGFloat(placement.columnCount)
        let height = CGFloat(entry.endMinutes - entry.startMinutes) * scale

        return Button {
            onSelect(entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(height > 44 ? 3 : 1)
                if let location = entry.location, height > 52 {
                    Text(location)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(width: width - 2, height: max(18, height - 2), alignment: .topLeading)
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
        }
        .buttonStyle(.plain)
        .offset(x: 2 + CGFloat(placement.column) * width,
                y: CGFloat(entry.startMinutes - span.start) * scale)
        .accessibilityLabel("\(entry.title), \(Self.fullName(entry.normalizedWeekday)) \(entry.timeRange)")
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

    // MARK: - Wochentage

    static let shortNames = ["", "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let fullNames = ["", "Montag", "Dienstag", "Mittwoch",
                            "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static func shortName(_ day: Int) -> String {
        shortNames.indices.contains(day) ? shortNames[day] : "?"
    }

    static func fullName(_ day: Int) -> String {
        fullNames.indices.contains(day) ? fullNames[day] : "Unbekannt"
    }

    /// Wochentag in Stud.IP-Zählung (1 = Montag … 7 = Sonntag).
    /// `Calendar` zählt 1 = Sonntag.
    static func weekday(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static var todayWeekday: Int { weekday(of: Date()) }
}
