import SwiftUI

/// Ein Eintrag aus „Was passiert" ausführlich.
///
/// In der Liste steht jede Meldung auf zwei Zeilen gekürzt — bei einer
/// Ankündigung oder einem Forenbeitrag ist der eigentliche Text damit nicht
/// zu lesen, und angetippt geschah bisher gar nichts. Hier steht der ganze
/// Text, und von hier führt der Weg dorthin, wo die Sache stattgefunden hat.
struct ActivityDetailView: View {
    let item: ActivityItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !item.rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contentCard(item.rawContent)
                }
                facts
                if let courseID = item.courseID { target(courseID) }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.kindLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(0.22)))
                Chip(text: item.kindLabel, color: .white)
                Spacer(minLength: 0)
            }

            // Der Titel ist ein von Stud.IP fertig formulierter Satz
            // („… hat eine Datei im Kurs … hochgeladen") und kann selbst
            // Auszeichnung enthalten.
            FormattedText(raw: item.rawTitle, font: .headline)
                .foregroundStyle(.white)

            if let created = item.createdAt {
                Label(created.formatted(.dateTime.weekday(.wide).day().month(.wide)
                                            .hour().minute()),
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.cardPadding + 2)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner + 4, style: .continuous)
                .fill(Tint.gradient(item.tintSeed))
        )
    }

    private func contentCard(_ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inhalt")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            FormattedText(raw: raw)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let actor = item.actorName {
                FactRow(symbol: "person", title: "Von", value: actor)
            }
            if let course = item.courseName {
                FactRow(symbol: "books.vertical", title: "In", value: course)
            }
            if let object = item.objectName {
                FactRow(symbol: "doc", title: "Betrifft", value: object)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Weiterführen

    /// Wohin die Meldung führt. Welcher Bereich gemeint ist, verrät
    /// `activity-type`; die Veranstaltung liefert der Kontext. Auf die
    /// einzelne Datei oder den einzelnen Beitrag lässt sich nicht springen —
    /// dafür gäbe es in der JSON:API keine Route, die von einer Objekt-ID
    /// aus in den passenden Bereich zurückfände.
    @ViewBuilder
    private func target(_ courseID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PushButton(value: Route.courseByID(courseID)) {
                RowLabel(symbol: destinationSymbol,
                         title: destinationTitle,
                         subtitle: item.courseName) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var destinationTitle: String {
        switch item.activityType {
        case "documents": return "Dateien der Veranstaltung"
        case "forum": return "Forum der Veranstaltung"
        case "news": return "Aushang der Veranstaltung"
        case "wiki": return "Wiki der Veranstaltung"
        case "schedule": return "Termine der Veranstaltung"
        default: return "Zur Veranstaltung"
        }
    }

    private var destinationSymbol: String {
        switch item.activityType {
        case "documents": return "folder"
        case "forum": return "text.bubble"
        case "news": return "megaphone"
        case "wiki": return "book.closed"
        case "schedule": return "calendar"
        default: return "books.vertical"
        }
    }
}

extension ActivityItem: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
