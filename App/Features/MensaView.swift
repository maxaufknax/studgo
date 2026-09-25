import SwiftUI

/// Der Speiseplan der Mensen über OpenMensa — pro Mensa ein Plan, pro Tag
/// die Gerichte mit Studierendenpreis und Kennzeichnungen.
///
/// **Warum das in der App steht:** Der Weg zur Mensa ist der häufigste Weg
/// des Tages auf dem Campus, und der Plan hing bisher an zwei Stellen — an
/// der Tür der Mensa und auf der Seite des Studentenwerks, die zum Handy
/// nicht passt. OpenMensa führt die Pläne als offene Daten, ohne Schlüssel;
/// die App muss nichts scrapen und nichts raten (siehe `MensaSource`).
struct MensaView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var preferences: Preferences

    @StateObject private var canteens = Loadable<[Canteen]>()
    @StateObject private var days = Loadable<[CanteenDay]>()
    @StateObject private var meals = Loadable<[MensaMeal]>()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var webTarget: WebTarget?

    private var source: MensaSource { MensaSource(isDemo: auth.isDemo) }

    /// Die gewählte Mensa — die Erinnerung daran ist eine Einstellung.
    private var canteen: Canteen? {
        let all = canteens.value ?? []
        return all.first { $0.id == preferences.mensaCanteenID } ?? all.first
    }

    private var dayIsClosed: Bool {
        guard let list = days.value else { return false }
        let key = MensaSource.iso(selectedDay)
        return list.first { $0.date == key }?.closed ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            DayStrip(selection: $selectedDay, markedDays: [], length: 7)
            Divider()
            mealList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(canteen?.name ?? "Mensa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Mensa", selection: canteenBinding) {
                        ForEach(canteens.value ?? []) { place in
                            Text(place.name).tag(place.id)
                        }
                    }
                } label: {
                    Label(canteen?.name ?? "Mensa",
                          systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.footnote)
                }
            }
        }
        .sheet(item: $webTarget) { target in
            WebSheet(url: target.url)
        }
        .refreshable { await load(fresh: true) }
        // Jeder Auslöser lädt nur das Seine: der erste Start die Mensen,
        // ein Mensawechsel Tage und Gerichte, ein Tageswechsel nur die
        // Gerichte. Alles lief sonst beim Öffnen mehrfach.
        .task {
            if canteens.value == nil {
                await canteens.load { try await source.canteens() }
            }
        }
        .task(id: canteen?.id) {
            guard canteen?.id != nil else { return }
            await loadDaysAndMeals(fresh: false)
        }
        .task(id: selectedDay) {
            guard canteen?.id != nil else { return }
            await loadMeals(fresh: false)
        }
    }

    // MARK: - Liste

    private var mealList: some View {
        List {
            if let grouped = groupedMeals, !grouped.isEmpty {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.meals) { meal in
                            MensaMealRow(meal: meal)
                        }
                    }
                }
                Section {
                    Text("Speiseplan über OpenMensa. Angaben ohne Gewähr; maßgeblich ist die Kennzeichnung in der Mensa.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if dayIsClosed {
                Section {
                    Label("An diesem Tag ist geschlossen.", systemImage: "storefront")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            // Geschlossene Tage sind ein Zustand der Liste, nicht leer —
            // alles andere (Laden, Fehler, kein Plan) steht hier.
            StateOverlay(isLoading: meals.isLoading,
                         errorMessage: meals.errorMessage,
                         isEmpty: groupedMeals == nil && !dayIsClosed,
                         emptyText: "Kein Speiseplan für diesen Tag",
                         emptySymbol: "fork.knife",
                         retry: { Task { await load(fresh: true) } })
        }
    }

    private var groupedMeals: [(category: String, meals: [MensaMeal])]? {
        guard let all = meals.value, !all.isEmpty else { return nil }
        var order: [String] = []
        var groups: [String: [MensaMeal]] = [:]
        for meal in all {
            if groups[meal.category] == nil { order.append(meal.category) }
            groups[meal.category, default: []].append(meal)
        }
        return order.map { (category: $0, meals: groups[$0] ?? []) }
    }

    /// Die Mensa-Wahl als Bindung — sie schreibt in die Einstellungen und
    /// lädt den Plan danach neu.
    private var canteenBinding: Binding<Int> {
        Binding(get: { canteen?.id ?? preferences.mensaCanteenID },
                set: { preferences.mensaCanteenID = $0 })
    }

    // MARK: - Laden

    private func load(fresh: Bool) async {
        if canteens.value == nil {
            await canteens.load { try await source.canteens() }
        }
        await loadDaysAndMeals(fresh: fresh)
    }

    private func loadDaysAndMeals(fresh: Bool) async {
        guard let id = canteen?.id else { return }
        await days.load { try await source.days(of: id) }
        await loadMeals(fresh: fresh)
    }

    private func loadMeals(fresh: Bool) async {
        guard let id = canteen?.id else { return }
        let day = selectedDay
        await meals.load { try await source.meals(of: id, on: day) }
    }
}

/// Ein Gericht: Name, Studierendenpreis, Kennzeichnungen.
struct MensaMealRow: View {
    let meal: MensaMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(meal.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let price = meal.priceLabel {
                    Text(price)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if !meal.notes.isEmpty {
                HStack(spacing: 6) {
                    if meal.isVegan {
                        Chip(text: "vegan", symbol: "leaf.fill", color: .green)
                    } else if meal.isVegetarian {
                        Chip(text: "vegetarisch", symbol: "leaf", color: .green)
                    }
                    Text(meal.notes.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
