import SwiftUI
import UIKit

/// Der Stundenplan als Bild zum Teilen - für die Gruppe, die Fachschaft, das
/// WG-Brett oder den eigenen Sperrbildschirm.
///
/// Gerendert wird **nicht** die Ansicht vom Bildschirm: Die hat einen
/// Scrollbereich, eine Jetzt-Linie und Antippflächen, und ihre Höhe hängt am
/// Gerät. `TimetablePoster` ist eine eigene, ruhige Fassung mit fester Breite.
/// Ausgeblendete Termine bleiben draußen - auch wenn sie im Raster gerade
/// sichtbar geschaltet sind.
struct TimetableShareSheet: View {
    let entries: [ScheduleEntry]
    let semesterTitle: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hiddenEvents: HiddenEventsStore
    @State private var image: UIImage?
    @State private var showsRooms = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                                .accessibilityLabel("Vorschau des Stundenplans")
                        } else {
                            ProgressView()
                                .frame(height: 320)
                        }
                    }
                    .padding(.horizontal, 24)

                    Toggle(isOn: $showsRooms) {
                        Label("Räume zeigen", systemImage: "mappin.and.ellipse")
                    }
                    .padding(.horizontal, 24)

                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("Mein Stundenplan", image: Image(uiImage: image))) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal, 24)
                    }

                    Text("Das Bild entsteht auf dem Gerät. Es enthält nur, was du im Raster siehst, ohne ausgeblendete Termine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stundenplan teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task(id: showsRooms) { render() }
        }
    }

    /// Dreifache Auflösung: 360 Punkte Breite werden 1080 Pixel - die Breite,
    /// die Instagram und WhatsApp ohne Neuberechnung zeigen.
    private func render() {
        let poster = TimetablePoster(entries: entries.filter { !hiddenEvents.isHidden($0) },
                                     semesterTitle: semesterTitle,
                                     showsRooms: showsRooms)
            // Ein geteiltes Bild sieht für alle gleich aus: hell und in der
            // Standardschriftgröße, egal was dieses Gerät eingestellt hat.
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        image = renderer.uiImage
    }
}

/// Das Wochenraster als Bild: Kopf, Raster, Herkunft.
///
/// Feste Breite statt Bildschirmbreite, damit das Bild auf jedem Gerät gleich
/// aussieht; die Höhe ergibt sich aus der Spanne des Tages.
struct TimetablePoster: View {
    let entries: [ScheduleEntry]
    let semesterTitle: String?
    var showsRooms = true

    private let width: CGFloat = 360
    private let padding: CGFloat = 18
    private let rulerWidth: CGFloat = 30
    private let hourHeight: CGFloat = 46
    private let headerHeight: CGFloat = 22

    /// Montag bis Freitag immer, Wochenende nur mit Termin - wie im Raster.
    private var days: [Int] {
        Set(1...5).union(entries.map(\.normalizedWeekday)).sorted()
    }

    /// Volle Stunden, mindestens acht - ein einzelnes Seminar soll nicht als
    /// haushoher Block allein im Bild stehen.
    private var span: (start: Int, end: Int) {
        guard let earliest = entries.map(\.startMinutes).min(),
              let latest = entries.map(\.endMinutes).max() else { return (8 * 60, 16 * 60) }
        var from = (earliest / 60) * 60
        var to = min(24 * 60, ((latest + 59) / 60) * 60)
        while to - from < 8 * 60 {
            if to < 24 * 60 { to += 60 } else if from > 0 { from -= 60 } else { break }
        }
        return (from, to)
    }

    private var dayWidth: CGFloat {
        (width - padding * 2 - rulerWidth) / CGFloat(max(1, days.count))
    }

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(minute - span.start) / 60 * hourHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mein Stundenplan")
                    .font(.title3.bold())
                if let semesterTitle {
                    Text(semesterTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 4) {
                dayHeader
                grid
            }

            HStack(spacing: 8) {
                AppLogoView(size: 22, cornerRadius: 5)
                Text("Erstellt mit StudGo")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(verbatim: "studgo.de")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.blue)
            }
        }
        .padding(padding)
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: rulerWidth, height: headerHeight)
            ForEach(days, id: \.self) { day in
                Text(Weekday.short(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .frame(width: dayWidth, height: headerHeight)
            }
        }
    }

    private var grid: some View {
        let hours = Array(stride(from: span.start, through: span.end, by: 60))
        let height = y(span.end)
        return ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { minute in
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: dayWidth * CGFloat(days.count), height: 0.5)
                    .offset(x: rulerWidth, y: y(minute))
                Text(Format.clock(minutes: minute))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.black.opacity(0.45))
                    .frame(width: rulerWidth - 4, alignment: .trailing)
                    .offset(y: y(minute) - 6)
            }
            ForEach(entries) { entry in
                block(entry)
            }
        }
        .frame(width: width - padding * 2, height: height, alignment: .topLeading)
    }

    private func block(_ entry: ScheduleEntry) -> some View {
        let column = CGFloat(days.firstIndex(of: entry.normalizedWeekday) ?? 0)
        let height = max(18, y(entry.endMinutes) - y(entry.startMinutes) - 2)
        return VStack(alignment: .leading, spacing: 1) {
            Text(entry.displayTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(height > 44 ? 3 : 2)
                .minimumScaleFactor(0.75)
            if showsRooms, let location = entry.location, height > 40 {
                Text(location)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.75)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .frame(width: dayWidth - 3, height: height, alignment: .topLeading)
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
        .offset(x: rulerWidth + column * dayWidth + 1, y: y(entry.startMinutes) + 1)
    }
}
