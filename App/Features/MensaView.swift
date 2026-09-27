import SwiftUI

/// Der Speiseplan der Mensen über OpenMensa - pro Mensa ein Plan, in zwei
/// Lesarten: **Tag** zeigt einen Tag mit seinen Gerichten, **Woche** die
/// ganze Woche in Abschnitten - wer nur „mittwochs essen gehen“ will, blättert
/// nicht durch Einzeltage. Jedes Gericht öffnet ein Blatt mit allen Preisen
/// und der vollständigen Kennzeichnung; die Liste zeigt von allem nur den
/// Studierendenpreis als Zeile.
///
/// **Warum das in der App steht:** Der Weg zur Mensa ist der häufigste Weg
/// des Tages auf dem Campus, und der Plan hing bisher an zwei Stellen - an
/// der Tür der Mensa und auf der Seite des Studentenwerks, die zum Handy
/// nicht passt. OpenMensa führt die Pläne als offene Daten, ohne Schlüssel;
/// die App muss nichts scrapen und nichts raten (siehe `MensaSource`).
struct MensaView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var preferences: Preferences

    enum Mode: String, CaseIterable, Identifiable {
        case day = "Tag"
        case week = "Woche"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .day
    @StateObject private var canteens = Loadable<[Canteen]>()
    @StateObject private var days = Loadable<[CanteenDay]>()
    @StateObject private var meals = Loadable<[MensaMeal]>()
    /// Die Gerichte der Wochenansicht, nach ISO-Datum verschlüsselt -
    /// sieben Tage parallel geholt, jeder bleibt für sich im
    /// Zwischenspeicher.
    @State private var weekMeals: [String: [MensaMeal]] = [:]
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var selectedMeal: MensaMeal?
    @State private var webTarget: WebTarget?

    private var source: MensaSource { MensaSource(isDemo: auth.isDemo) }

    /// Die gewählte Mensa - die Erinnerung daran ist eine Einstellung.
    private var canteen: Canteen? {
        let all = canteens.value ?? []
        return all.first { $0.id == preferences.mensaCanteenID } ?? all.first
    }

    private var dayIsClosed: Bool {
        guard let list = days.value else { return false }
        let key = MensaSource.iso(selectedDay)
        return list.first { $0.date == key }?.closed ?? false
    }

    /// Ob die Mensa an einem Tag der Woche geschlossen hat - nach OpenMensa
    /// bedeutet ein Tag ohne Eintrag: kein Plan veröffentlicht.
    private func isClosed(_ day: Date) -> Bool {
        guard let list = days.value else { return false }
        let key = MensaSource.iso(day)
        return list.first { $0.date == key }?.closed ?? false
    }

    /// Die Woche der Wochenansicht: die des gewählten Tages, Montag bis
    /// Sonntag. Wer in der Wochenansicht einen anderen Tag wählen will,
    /// wählt ihn in der Tagesleiste - beide Ansichten folgen derselben
    /// Auswahl.
    private var week: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Wann die Wochenansicht neu zu laden ist: beim Wechsel auf „Woche“,
    /// bei anderem Mensa- oder Wochenwechsel. `nil` in der Tagesansicht -
    /// ohne Ziel ruft `.task(id:)` die Arbeit nicht auf.
    private var weekReloadKey: String? {
        guard mode == .week else { return nil }
        return "\(canteen?.id ?? 0)|\(MensaSource.iso(week.first ?? selectedDay))"
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedHeader(title: "Ansicht", options: Mode.allCases,
                            selection: $mode) { $0.rawValue }
            DayStrip(selection: $selectedDay, markedDays: [], length: 7)
            Divider()
            switch mode {
            case .day: mealList
            case .week: weekList
            }
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
                .accessibilityLabel("Mensa wählen")
            }
        }
        .sheet(item: $selectedMeal) { meal in
            MensaMealDetail(meal: meal)
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
        .task(id: weekReloadKey) {
            guard weekReloadKey != nil else { return }
            await loadWeekMeals()
        }
    }

    // MARK: - Tagesansicht

    private var mealList: some View {
        List {
            if let grouped = groupedMeals, !grouped.isEmpty {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.meals) { meal in
                            mealButton(meal)
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
            // Geschlossene Tage sind ein Zustand der Liste, nicht leer -
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

    // MARK: - Wochenansicht

    /// Die Woche in Abschnitten - ein Tag, ein Abschnitt. Der Wochentag
    /// steht in der Überschrift; hier ist das Blättern von der Leiste.
    private var weekList: some View {
        List {
            ForEach(week, id: \.timeIntervalSince1970) { day in
                let key = MensaSource.iso(day)
                Section(Format.dayHeader(day)) {
                    if isClosed(day) {
                        Label("Geschlossen", systemImage: "storefront")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Am \(Format.dayHeader(day)) geschlossen")
                    } else {
                        let dayMeals = weekMeals[key] ?? []
                        if dayMeals.isEmpty {
                            if weekMeals[key] == nil {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .padding(.vertical, 4)
                                    Spacer()
                                }
                            } else {
                                Text("Kein Speiseplan für diesen Tag")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(dayMeals) { meal in
                                mealButton(meal)
                            }
                        }
                    }
                }
            }
            Section {
                Text("Speiseplan über OpenMensa. Angaben ohne Gewähr; maßgeblich ist die Kennzeichnung in der Mensa.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Gericht

    /// Eine Gerichtzeile - antippbar, dahinter das Blatt mit allen Details.
    private func mealButton(_ meal: MensaMeal) -> some View {
        Button {
            selectedMeal = meal
        } label: {
            MensaMealRow(meal: meal)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Details und Preise öffnen")
    }

    /// Die Mensa-Wahl als Bindung - sie schreibt in die Einstellungen und
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
        if mode == .week { await loadWeekMeals() }
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

    /// Sieben Tage parallel statt nacheinander: Jeder Einzeltag bleibt
    /// ohnehin fünf Minuten im Zwischenspeicher, aber das erste Öffnen
    /// der Wochenansicht wäre sonst siebenmal eine Anfrage lang.
    private func loadWeekMeals() async {
        guard let id = canteen?.id else { return }
        let source = source
        let targets = week
        var result: [String: [MensaMeal]] = [:]
        await withTaskGroup(of: (String, [MensaMeal]).self) { group in
            for day in targets {
                let key = MensaSource.iso(day)
                group.addTask {
                    let meals = (try? await source.meals(of: id, on: day)) ?? []
                    return (key, meals)
                }
            }
            for await pair in group {
                result[pair.0] = pair.1
            }
        }
        weekMeals = result
    }
}

/// Ein Gericht: Name, Studierendenpreis, Kennzeichnungen. Alles Weitere -
/// alle Preigruppen, die vollständige Kennzeichnung - steht im Blatt.
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

/// Das Blatt zu einem Gericht: alle Preise, alle Kennzeichnungen - die
/// Liste zeigt bewusst nur den Studierendenpreis als Zeile, hier steht der
/// Rest. Wer wissen will, was „K7“ bedeutet oder was Gäste zahlen, tippt
/// auf das Gericht.
struct MensaMealDetail: View {
    let meal: MensaMeal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meal.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meal.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                let prices = meal.priceRows
                if !prices.isEmpty {
                    Section("Preise") {
                        ForEach(Array(prices.indices), id: \.self) { index in
                            HStack {
                                Text(prices[index].label)
                                Spacer(minLength: 8)
                                Text(String(format: "%.2f €", prices[index].price))
                                    .monospacedDigit()
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("Kennzeichnungen") {
                    if meal.isVegan {
                        Label("Vegan", systemImage: "leaf.fill")
                            .foregroundStyle(.green)
                    } else if meal.isVegetarian {
                        Label("Vegetarisch", systemImage: "leaf")
                            .foregroundStyle(.green)
                    }
                    if !meal.additives.isEmpty {
                        ForEach(meal.additives, id: \.self) { note in
                            Label(note, systemImage: "tag")
                                .font(.subheadline)
                        }
                    }
                    if meal.notes.isEmpty {
                        Text("Keine Kennzeichnungen angegeben")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Speiseplan über OpenMensa. Angaben ohne Gewähr; maßgeblich ist die Kennzeichnung in der Mensa.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gericht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
