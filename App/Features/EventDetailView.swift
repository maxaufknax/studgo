import SwiftUI

/// Ein Termin ausführlich: Thema, Zeit, Raum, Turnus — und der Weg in die
/// Veranstaltung, zu der er gehört.
///
/// Vorher war eine Terminzeile eine Sackgasse: Das Thema der Sitzung stand
/// auf zwei Zeilen gekürzt in der Liste, die Beschreibung war gar nicht zu
/// sehen, und von einem Termin aus kam man nicht in seinen Kurs.
struct EventDetailView: View {
    let event: CourseEvent
    /// Name der Veranstaltung, sofern die aufrufende Ansicht ihn schon kennt.
    var courseTitle: String?

    @State private var webTarget: WebTarget?

    private var headline: String {
        // Bei `course-events` steht im Titel der Veranstaltungsname und im
        // Beschreibungsfeld das Thema der Sitzung — hier zählt das Thema.
        event.topic ?? event.title
    }

    private var subheadline: String? {
        guard event.topic != nil else { return courseTitle }
        return courseTitle ?? event.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                facts
                if let description = event.description, event.topic != nil || !description.isEmpty {
                    notes(description)
                }
                if let location = event.location { roomLink(location) }
                if let courseID = event.courseID { courseLink(courseID) }
                if event.isDerived { derivedHint }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Termin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url).ignoresSafeArea()
        }
    }

    /// Der Weg zum Hörsaal.
    ///
    /// Der Standortfinder der LUH ist eine Kartenanwendung ohne
    /// Schnittstelle — nachbauen ließe sich davon nichts, verlinken alles.
    /// Stud.IP schreibt Räume als „1101 - E001": Die führende Zahl ist die
    /// Gebäudenummer, und danach sucht der Standortfinder zuverlässig.
    private func roomLink(_ location: String) -> some View {
        Button {
            webTarget = WebTarget(url: WebLinks.campusMap(searching: location))
        } label: {
            RowLabel(symbol: "map",
                     title: "Raum auf dem Campusplan",
                     subtitle: location) {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Chip(text: event.isPersonal ? "Persönlich" : "Veranstaltung",
                     symbol: event.isPersonal ? "person.crop.circle" : "books.vertical.fill",
                     color: .white)
                if event.isCancelled {
                    Chip(text: "Fällt aus", symbol: "xmark.circle.fill", color: .white)
                }
            }

            Text(headline)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let subheadline, subheadline != headline {
                Text(subheadline)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(Format.eventTime(event.start), systemImage: "clock")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.cardPadding + 2)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner + 4, style: .continuous)
                .fill(Tint.gradient(event.tintSeed))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Eckdaten

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            FactRow(symbol: "calendar",
                    title: "Tag",
                    value: event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            FactRow(symbol: "clock",
                    title: "Uhrzeit",
                    value: "\(Format.timeRange(event.start, event.end)) · \(durationLabel)")
            if let location = event.location {
                FactRow(symbol: "mappin.and.ellipse", title: "Ort", value: location)
            }
            if let recurrence = event.recurrence {
                FactRow(symbol: "repeat", title: "Turnus", value: recurrence)
            }
            if let category = event.category {
                FactRow(symbol: "tag", title: "Art", value: category)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var durationLabel: String {
        let minutes = max(0, Int(event.end.timeIntervalSince(event.start) / 60))
        if minutes < 60 { return "\(minutes) Min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) Std" : "\(hours) Std \(rest) Min"
    }

    // MARK: - Beschreibung

    private func notes(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.topic != nil ? "Beschreibung" : "Notiz")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            FormattedText(raw: description)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func courseLink(_ courseID: String) -> some View {
        PushButton(value: Route.courseByID(courseID)) {
            RowLabel(symbol: "books.vertical",
                     title: "Zur Veranstaltung",
                     subtitle: courseTitle ?? event.title) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
    }

    /// Ehrlich bleiben: Aus dem Stundenplan abgeleitete Sitzungen kennen
    /// keine Ausfälle — die stehen nur in `/v1/courses/{id}/events`.
    private var derivedHint: some View {
        Label("Aus deinem Stundenplan errechnet. Ob die Sitzung wirklich stattfindet, steht in der Terminliste der Veranstaltung.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

extension CourseEvent: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Ein Stundenplaneintrag ausführlich — der wiederkehrende Block, nicht die
/// einzelne Sitzung.
struct ScheduleEntryDetailView: View {
    let entry: ScheduleEntry
    @State private var webTarget: WebTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Chip(text: entry.isCourse ? "Veranstaltung" : "Eigener Eintrag",
                         symbol: entry.isCourse ? "books.vertical.fill" : "pencil",
                         color: .white)
                    Text(entry.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("\(entry.weekdayName), \(entry.timeRange)", systemImage: "clock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.cardPadding + 2)
                .background(
                    RoundedRectangle(cornerRadius: Design.cardCorner + 4, style: .continuous)
                        .fill(Tint.gradient(entry.tintSeed))
                )

                VStack(alignment: .leading, spacing: 10) {
                    FactRow(symbol: "calendar", title: "Wochentag", value: entry.weekdayName)
                    FactRow(symbol: "clock", title: "Uhrzeit", value: entry.timeRange)
                    if let location = entry.location {
                        FactRow(symbol: "mappin.and.ellipse", title: "Ort", value: location)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if let description = entry.description {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notiz")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        FormattedText(raw: description)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                if let courseID = entry.courseID {
                    PushButton(value: Route.courseByID(courseID)) {
                        RowLabel(symbol: "books.vertical",
                                 title: "Zur Veranstaltung",
                                 subtitle: entry.title) {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .card()
                    }
                }

                // Nur eigene Einträge: Turnustermine einer Veranstaltung
                // gehören der Veranstaltung, die ändert man nicht von hier
                // aus. Ändern und Löschen laufen über die Weboberfläche — zu
                // `schedule-entries` kennt die JSON:API ausschliesslich
                // Lesezugriff.
                if !entry.isCourse {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            webTarget = WebTarget(url: WebLinks.scheduleEntry(entry.id))
                        } label: {
                            RowLabel(symbol: "pencil",
                                     title: "Ändern oder löschen",
                                     subtitle: "Öffnet Stud.IP") {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        Text("Eigene Termine lassen sich über die Stud.IP-Schnittstelle nur lesen; geschrieben wird in der Weboberfläche.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Stundenplan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url)
        }
    }
}

extension ScheduleEntry: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
