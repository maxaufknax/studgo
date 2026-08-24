import SwiftUI

/// Einstiegsbildschirm: was heute ansteht, was neu ist.
struct TodayView: View {
    let user: StudIPUser
    @Environment(AuthStore.self) private var auth

    @State private var events = Loadable<[CourseEvent]>()
    @State private var messages = Loadable<[Message]>()
    @State private var news = Loadable<[NewsItem]>()

    private var todaysEvents: [CourseEvent] {
        (events.value ?? []).filter { Calendar.current.isDateInToday($0.start) }
    }

    private var nextEvents: [CourseEvent] {
        let now = Date()
        return (events.value ?? [])
            .filter { $0.start > now && !Calendar.current.isDateInToday($0.start) }
            .prefix(3)
            .map { $0 }
    }

    private var unread: [Message] {
        (messages.value ?? []).filter { !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            List {
                greeting

                Section("Heute") {
                    if todaysEvents.isEmpty {
                        Label("Keine Termine heute", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(todaysEvents) { EventRow(event: $0) }
                    }
                }

                if !nextEvents.isEmpty {
                    Section("Als Nächstes") {
                        ForEach(nextEvents) { EventRow(event: $0, showDay: true) }
                    }
                }

                Section {
                    if unread.isEmpty {
                        Label("Keine ungelesenen Nachrichten", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unread.prefix(3)) { message in
                            NavigationLink(value: message) { MessageRow(message: message) }
                        }
                    }
                } header: {
                    Text(unread.isEmpty ? "Nachrichten" : "\(unread.count) ungelesen")
                }

                if let items = news.value, !items.isEmpty {
                    Section("Neueste Ankündigungen") {
                        ForEach(items.prefix(3)) { item in
                            NavigationLink(value: item) { NewsRow(item: item) }
                        }
                    }
                }
            }
            .navigationTitle("Heute")
            .navigationDestination(for: Message.self) { MessageDetailView(message: $0) }
            .navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }
            .refreshable { await reload() }
            .task { await reloadIfNeeded() }
            .overlay {
                if events.isLoading && messages.isLoading { ProgressView() }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(salutation)
                .font(.title2.bold())
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private var salutation: String {
        let name = user.givenName ?? user.formattedName
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: return "Guten Morgen, \(name)"
        case 11..<18: return "Hallo, \(name)"
        default: return "Guten Abend, \(name)"
        }
    }

    private func reloadIfNeeded() async {
        guard events.value == nil else { return }
        await reload()
    }

    private func reload() async {
        let client = auth.client
        // Die drei Abschnitte sind voneinander unabhängig — parallel laden.
        async let loadEvents: Void = events.load { try await client.events(for: user.id) }
        async let loadMessages: Void = messages.load { try await client.inbox(for: user.id) }
        async let loadNews: Void = news.load { try await client.news(for: user.id) }
        _ = await (loadEvents, loadMessages, loadNews)
    }
}

struct EventRow: View {
    let event: CourseEvent
    var showDay = false

    var body: some View {
        HStack(spacing: 12) {
            AccentBar(seed: event.courseID ?? event.title)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .strikethrough(event.isCancelled)
                Text(showDay ? Format.eventTime(event.start) : Format.timeRange(event.start, event.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if event.isCancelled {
                    Text("Fällt aus")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
