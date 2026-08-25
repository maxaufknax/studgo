import SwiftUI

/// Die Veranstaltungsseite als **Übersicht mit Einstiegen** statt als
/// segmentierter Umschalter.
///
/// Fünf Segmente nebeneinander waren auf einem iPhone kaum zu treffen und
/// verrieten nichts über den Inhalt: Man musste jeden Reiter antippen, um zu
/// sehen, ob überhaupt etwas darin liegt. Jetzt steht oben, worum es geht,
/// darunter Kacheln mit Anzahl — leere Bereiche sind sofort als leer erkennbar.
struct CourseDetailView: View {
    let course: Course
    @Environment(AuthStore.self) private var auth

    @State private var events = Loadable<[CourseEvent]>()
    @State private var news = Loadable<[NewsItem]>()
    @State private var participants = Loadable<[Participant]>()
    @State private var webTarget: WebTarget?

    private var lecturers: [Participant] {
        (participants.value ?? []).filter { $0.permission == "dozent" }
    }

    private var nextEvent: CourseEvent? {
        (events.value ?? []).first { !$0.isOver && !$0.isCancelled }
    }

    /// Der **rohe** Text. Das Setzen übernimmt `FormattedText` — die
    /// Beschreibung ist in aller Regel Stud.IP-Auszeichnung, kein HTML.
    private var description: String? {
        course.description?.nilIfEmpty
    }

    /// Ist das eine Studiengruppe? Dann heißt der Bereich anders, und
    /// „Eintragen" heißt „Beitreten".
    private var isStudygroup: Bool { auth.studygroupKinds.contains(course.typeID) }

    /// Man ist selbst gar nicht eingetragen — dann liefert Stud.IP zu
    /// Teilnehmenden, Terminen und Aushang nichts, und das ist keine Störung.
    ///
    /// Erst wenn **alle drei** Abrufe durch sind: Während des Ladens sind sie
    /// ebenfalls leer, und der Hinweis dürfte nicht kurz aufblitzen.
    private var isOutsider: Bool {
        guard participants.hasValue, events.hasValue, news.hasValue else { return false }
        return (participants.value ?? []).isEmpty
            && (events.value ?? []).isEmpty
            && (news.value ?? []).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let nextEvent {
                    NavigationLink(value: nextEvent) { nextCard(nextEvent) }
                        .buttonStyle(.plain)
                }
                if isOutsider { outsiderNote }
                sections
                if description != nil || course.miscellaneous != nil { about }
                facts
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(course.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        webTarget = WebTarget(url: StudIPClient.courseURL(courseID: course.id))
                    } label: {
                        Label("In Stud.IP öffnen", systemImage: "safari")
                    }
                    Button {
                        webTarget = WebTarget(url: StudIPClient.enrolmentURL(courseID: course.id))
                    } label: {
                        Label(isStudygroup ? "Beitreten / verlassen" : "Eintragen / austragen",
                              systemImage: "person.badge.plus")
                    }
                    ShareLink(item: StudIPClient.courseURL(courseID: course.id)) {
                        Label("Link teilen", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url).ignoresSafeArea()
        }
        .task { await loadOverview() }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let number = course.courseNumber {
                    Chip(text: number, color: .white)
                }
                if let type = auth.courseTypeName(course.typeID) {
                    Chip(text: type, color: .white)
                } else if isStudygroup {
                    Chip(text: "Studiengruppe", symbol: "person.3.fill", color: .white)
                }
            }

            Text(course.shortTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = course.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !lecturers.isEmpty {
                Label(lecturers.map(\.name).joined(separator: ", "),
                      systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.cardPadding + 2)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner + 4, style: .continuous)
                .fill(Tint.gradient(course.id))
        )
        .accessibilityElement(children: .combine)
    }

    private func nextCard(_ event: CourseEvent) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nächste Sitzung")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Tint.color(course.id))
                Text(Format.eventTime(event.start))
                    .font(.subheadline.weight(.semibold))
                if let topic = event.topic {
                    Text(topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let location = event.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .card()
    }

    // MARK: - Kacheln

    private var sections: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            NavigationLink {
                CourseDatesView(course: course, events: events)
            } label: {
                CourseTile(symbol: "calendar", title: "Termine",
                           count: events.value?.count, seed: course.id)
            }
            .buttonStyle(.plain)

            NavigationLink {
                FolderBrowserView(course: course)
            } label: {
                CourseTile(symbol: "folder", title: "Dateien",
                           count: nil, seed: course.id)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CourseParticipantsView(course: course, participants: participants)
            } label: {
                CourseTile(symbol: "person.2", title: "Personen",
                           count: participants.value?.count, seed: course.id)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CourseNewsView(course: course, news: news)
            } label: {
                CourseTile(symbol: "megaphone", title: "Aushang",
                           count: news.value?.count, seed: course.id)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CourseForumView(course: course)
            } label: {
                CourseTile(symbol: "text.bubble", title: "Forum",
                           count: nil, seed: course.id)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CourseWikiView(course: course)
            } label: {
                CourseTile(symbol: "book.closed", title: "Wiki",
                           count: nil, seed: course.id)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CourseBlubberView(course: course)
            } label: {
                CourseTile(symbol: "bubble.left.and.bubble.right", title: "Blubber",
                           count: nil, seed: course.id)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Beschreibung

    /// Beschreibung und „Sonstiges".
    ///
    /// Beide Felder kommen **unbearbeitet** aus Stud.IP
    /// (`Schemas/Course.php` reicht `beschreibung` und `sonstiges` roh
    /// durch). Sie tragen Absätze, Aufzählungen, Betonungen und Verweise in
    /// Stud.IP-Auszeichnung — als Klartext gezeigt stand hier ein einziger
    /// Block voller Sternchen und Prozentzeichen. `FormattedText` setzt das.
    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description {
                Text("Beschreibung")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                // Lange Kommentartexte schoben früher alles Übrige aus dem
                // Bild; sie stehen jetzt gekürzt und lassen sich aufklappen.
                ExpandableText(raw: description)
            }

            if let extra = course.miscellaneous?.nilIfEmpty {
                if description != nil { Divider().padding(.vertical, 2) }
                Text("Sonstiges")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ExpandableText(raw: extra)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Wer nicht eingetragen ist, sieht bei Terminen, Personen und Aushang
    /// nichts — das ist die Rechtelage, kein Fehler. Vorher stand in jedem
    /// dieser Bereiche „Für diesen Bereich fehlen die Rechte".
    private var outsiderNote: some View {
        HStack(spacing: 11) {
            Image(systemName: "lock")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(isStudygroup ? "Du bist in dieser Gruppe nicht dabei"
                                  : "Du bist hier nicht eingetragen")
                    .font(.subheadline.weight(.semibold))
                Text("Termine, Personen und Aushang gibt Stud.IP nur Mitgliedern heraus. \(isStudygroup ? "Beitreten" : "Eintragen") geht über die Weboberfläche.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Eckdaten

    @ViewBuilder
    private var facts: some View {
        if course.location != nil || !lecturers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Eckdaten")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let location = course.location {
                    FactRow(symbol: "mappin.and.ellipse", title: "Ort", value: location)
                }
                if !lecturers.isEmpty {
                    FactRow(symbol: "person.fill",
                            title: lecturers.count == 1 ? "Lehrende:r" : "Lehrende",
                            value: lecturers.map(\.name).joined(separator: ", "))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Laden

    /// Termine, Aushang und Teilnehmende zusammen — daraus speisen sich die
    /// Zahlen auf den Kacheln, die Kopfzeile und die nächste Sitzung. Die
    /// Unterseiten bekommen die fertigen Listen gereicht und laden nicht
    /// erneut.
    private func loadOverview() async {
        guard events.value == nil else { return }
        let client = auth.client
        async let dates: Void = events.load { try await client.events(for: course) }
        async let posts: Void = news.load { try await client.news(for: course) }
        async let people: Void = participants.load { try await client.participants(of: course) }
        _ = await (dates, posts, people)
    }
}

/// Eine Kachel auf der Veranstaltungsseite.
struct CourseTile: View {
    let symbol: String
    let title: String
    var count: Int?
    let seed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Tint.color(seed))
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Tint.color(seed))
                }
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Tint.color(seed).opacity(0.35))
                .frame(height: 3)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count.map { "\(title), \($0) Einträge" } ?? title)
    }
}

/// Zeile mit Symbol, Bezeichnung und Wert — für die Eckdaten.
struct FactRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

extension Course: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
