import SwiftUI
import UIKit

/// Ein- und Ausschalten des Kalender-Abgleichs - mit Erlaubnis, erstem
/// Abgleich und ehrlicher Auskunft, wenn etwas nicht klappt.
///
/// Liegt in einem eigenen Modell, weil Einstellungen und Einführung denselben
/// Schalter zeigen: Zwei Kopien dieses Ablaufs liefen über kurz oder lang
/// auseinander.
@MainActor
final class CalendarSyncModel: ObservableObject {
    @Published var isWorking = false
    @Published var problem: String?
    @Published var lastSync: (date: Date, count: Int)?

    init() {
        lastSync = CalendarSync.lastSync
    }

    /// Der Schalter steht nur dann auf „an“, wenn der Zugriff wirklich
    /// vorliegt - ein Schalter, der an bleibt, ohne dass je etwas im Kalender
    /// ankommt, wäre eine Lüge (dieselbe Regel wie bei den Erinnerungen).
    func set(_ isOn: Bool, preferences: Preferences, auth: AuthStore,
             hiddenEvents: HiddenEventsStore) async {
        guard isOn != preferences.calendarSync else { return }
        problem = nil
        guard isOn else {
            preferences.calendarSync = false
            CalendarSync.removeCalendar()
            lastSync = nil
            return
        }

        isWorking = true
        defer { isWorking = false }
        guard await CalendarSync.requestAccess() else {
            preferences.calendarSync = false
            problem = String(localized: "Kein Zugriff auf den Kalender. Erlauben lässt er sich in den Einstellungen des Geräts unter „StudGo“ → „Kalender“.")
            return
        }
        preferences.calendarSync = true
        guard let userID = auth.currentUserID else { return }
        do {
            try await CalendarSync.syncNow(client: auth.client, userID: userID,
                                           isHidden: { hiddenEvents.isHidden($0) })
            lastSync = CalendarSync.lastSync
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Der Schalter selbst - eine Listenzeile.
struct CalendarSyncToggle: View {
    @ObservedObject var model: CalendarSyncModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hiddenEvents: HiddenEventsStore

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.calendarSync },
            set: { isOn in
                Task {
                    await model.set(isOn, preferences: preferences, auth: auth,
                                    hiddenEvents: hiddenEvents)
                }
            })) {
            RowLabel(symbol: "calendar.badge.plus",
                     title: String(localized: "Stundenplan im iOS-Kalender"))
        }
        .disabled(auth.isDemo || model.isWorking)
    }
}

/// Der Abschnitt in den Einstellungen: Schalter plus Erklärung darunter.
struct CalendarSyncSection: View {
    @StateObject private var model = CalendarSyncModel()
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        Section {
            CalendarSyncToggle(model: model)
            if model.problem != nil, CalendarSync.access == .denied,
               let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Label("Einstellungen öffnen", systemImage: "gear")
                        .font(.subheadline)
                }
            }
        } footer: {
            Text(CalendarSyncSection.footer(isDemo: auth.isDemo,
                                            isOn: preferences.calendarSync,
                                            problem: model.problem,
                                            lastSync: model.lastSync))
        }
    }

    /// Was unter dem Schalter steht - Erklärung, Stand oder Problem.
    static func footer(isDemo: Bool, isOn: Bool, problem: String?,
                       lastSync: (date: Date, count: Int)?) -> String {
        if isDemo {
            return String(localized: "In der Demo nicht verfügbar: Sie würde Beispieltermine in deinen echten Kalender schreiben.")
        }
        if let problem { return problem }
        var text = String(localized: "Trägt die nächsten acht Wochen in einen eigenen Kalender „StudGo“ ein und hält ihn bei jedem Öffnen aktuell. So stehen die Termine auch auf der Apple Watch, in CarPlay und bei Siri. Ausschalten entfernt den Kalender wieder.")
        if isOn, let lastSync {
            let when = Format.eventTime(lastSync.date)
            text += " " + String(localized: "Zuletzt abgeglichen: \(when), \(lastSync.count) Termine.")
        }
        return text
    }
}
