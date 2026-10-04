import SwiftUI

/// Die kurze Einführung nach der Anmeldung - drei Seiten, jederzeit
/// überspringbar.
///
/// **Für wen:** Erstsemester kennen Stud.IP oft noch gar nicht, und wer von
/// einer älteren Fassung kommt, erfährt hier, dass es Widgets für den
/// Sperrbildschirm und den Abgleich mit dem iOS-Kalender gibt. Beides sucht
/// sonst niemand von selbst.
///
/// Gezeigt wird sie einmal je Gerät (`seenKey`); im Profil steht „Einführung
/// ansehen“ für später. Die Schalter auf der letzten Seite fragen erst beim
/// Umlegen nach der Erlaubnis - nie beim bloßen Ansehen.
struct OnboardingView: View {
    /// Hochzählen, wenn eine neue Fassung der Einführung allen noch einmal
    /// gezeigt werden soll.
    static let seenKey = "studgo.onboarding.seen.v1"

    static var hasBeenSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Überspringen") { finish() }
                    .font(.subheadline)
                    .opacity(page < lastPage ? 1 : 0)
                    .disabled(page == lastPage)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            TabView(selection: $page) {
                OnboardingWelcomePage().tag(0)
                OnboardingWidgetPage().tag(1)
                OnboardingAlertsPage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < lastPage ? "Weiter" : "Los geht’s")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // Auch Wegwischen zählt als gesehen - wer sie wegwischt, will sie
        // nicht beim nächsten Start wieder vorgesetzt bekommen.
        .onDisappear { UserDefaults.standard.set(true, forKey: Self.seenKey) }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }
}

// MARK: - Seite 1: die Reiter

private struct OnboardingWelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppLogoView(size: 88, cornerRadius: 20)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text("Willkommen bei StudGo")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Dein Stud.IP, aufs Wesentliche reduziert. Fünf Reiter, jeder mit einer klaren Aufgabe:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    OnboardingRow(symbol: "sun.max.fill", title: "Heute",
                                  text: "Was jetzt ansteht, was heute noch kommt, was neu ist.")
                    OnboardingRow(symbol: "calendar", title: "Plan",
                                  text: "Tag, Woche und Liste - mit Feiertagen und Ausfällen.")
                    OnboardingRow(symbol: "books.vertical.fill", title: "Kurse",
                                  text: "Dateien, Ankündigungen, Forum, Wiki und Courseware.")
                    OnboardingRow(symbol: "tray.full.fill", title: "Postfach",
                                  text: "Nachrichten und Blubber an einer Stelle.")
                    OnboardingRow(symbol: "person.2.fill", title: "Campus",
                                  text: "Mensa, Personen, Sprechstunden und mehr.")
                }
                .card()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Seite 2: Widgets

private struct OnboardingWidgetPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Immer im Blick")
                        .font(.title2.bold())
                    Text("Der nächste Termin und ungelesene Nachrichten als Widget - auf dem Home-Bildschirm und dem Sperrbildschirm. Nach dem Ende eines Termins springt das Widget von selbst zum nächsten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    OnboardingRow(symbol: "lock.fill", title: "Sperrbildschirm",
                                  text: "Sperrbildschirm gedrückt halten → Anpassen → Sperrbildschirm → Widgets hinzufügen → StudGo.")
                    OnboardingRow(symbol: "apps.iphone", title: "Home-Bildschirm",
                                  text: "Eine freie Stelle gedrückt halten → Bearbeiten → Widget hinzufügen → StudGo.")
                    OnboardingRow(symbol: "wifi.slash", title: "Auch ohne Netz",
                                  text: "Widgets fragen nie selbst beim Server an. Sie zeigen, was die App zuletzt geladen hat.")
                }
                .card()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Seite 3: Erinnerungen, Kalender, Postfach

private struct OnboardingAlertsPage: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var calendarModel = CalendarSyncModel()
    @State private var notificationsDenied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "bell.badge.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Nichts verpassen")
                        .font(.title2.bold())
                    Text("Alles freiwillig und jederzeit im Profil umstellbar. StudGo hat keinen eigenen Server: Erinnerungen plant das Gerät selbst.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { preferences.eventReminders },
                                         set: { isOn in Task { await setReminders(isOn) } })) {
                        RowLabel(symbol: "clock.badge", title: String(localized: "Vor Veranstaltungen erinnern"),
                                 subtitle: Preferences.leadLabel(preferences.leadMinutes))
                    }
                    Divider()
                    CalendarSyncToggle(model: calendarModel)
                    if let problem = calendarModel.problem {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if auth.isDemo {
                        Text("Der Kalender-Abgleich ist in der Demo aus - er würde Beispieltermine in deinen echten Kalender schreiben.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Toggle(isOn: Binding(get: { preferences.mailboxAlerts },
                                         set: { isOn in Task { await setMailbox(isOn) } })) {
                        RowLabel(symbol: "tray.full", title: String(localized: "Neue Nachrichten und Beiträge"))
                    }
                    if notificationsDenied {
                        Text("Mitteilungen sind gesperrt. Erlauben lassen sie sich in den Einstellungen des Geräts unter „StudGo“ → „Mitteilungen“.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    /// Wie in den Einstellungen: erst die Erlaubnis, sonst springt der
    /// Schalter zurück. Geplant werden die Erinnerungen von „Heute“, das auf
    /// diese Einstellung hört (siehe `TodayView`).
    private func setReminders(_ isOn: Bool) async {
        if isOn {
            guard await ensureAuthorization() else { return }
            preferences.eventReminders = true
        } else {
            preferences.eventReminders = false
            await Notifications.clearEventReminders()
        }
    }

    private func setMailbox(_ isOn: Bool) async {
        if isOn {
            guard await ensureAuthorization() else { return }
            preferences.mailboxAlerts = true
            Notifications.scheduleBackgroundRefresh()
        } else {
            preferences.mailboxAlerts = false
            Notifications.cancelBackgroundRefresh()
        }
    }

    private func ensureAuthorization() async -> Bool {
        if await Notifications.isAuthorized() { return true }
        let granted = await Notifications.requestAuthorization()
        notificationsDenied = !granted
        return granted
    }
}

// MARK: - Baustein

/// Symbol, Überschrift, ein Satz - die Zeile, aus der alle drei Seiten bestehen.
private struct OnboardingRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
