import SwiftUI

/// Farbwelt und Erscheinungsbild wählen.
///
/// Jedes Thema wird als Muster gezeigt, nicht nur benannt: Akzentfarbe und
/// die ersten fünf Kursfarben nebeneinander. Ein Name wie „Beere" sagt sonst
/// wenig darüber, wie der Stundenplan hinterher aussieht.
struct AppearanceView: View {
    @Environment(ThemeStore.self) private var store

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        @Bindable var store = store

        return List {
            Section {
                Picker("Erscheinungsbild", selection: $store.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.name, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            } header: {
                Text("Erscheinungsbild")
            } footer: {
                Text("„Automatisch“ folgt der Einstellung des Geräts und wechselt abends von selbst.")
            }

            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.theme = theme
                            }
                        } label: {
                            ThemeCard(theme: theme, isSelected: store.theme == theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                .listRowBackground(Color.clear)
            } header: {
                Text("Farbwelt")
            } footer: {
                Text("Die Farbwelt bestimmt den Akzent der Bedienelemente und den Vorrat, aus dem jede Veranstaltung ihre feste eigene Farbe zieht. Ein Kurs behält seine Farbe innerhalb einer Farbwelt dauerhaft.")
            }

            Section {
                Toggle("Dichtere Listen", isOn: $store.isCompact)
            } footer: {
                Text("Zeigt mehr Einträge auf einmal, dafür mit weniger Luft dazwischen.")
            }

            Section("Vorschau") {
                ThemePreviewRows()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Darstellung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ein Thema als antippbare Karte mit Farbmuster.
struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool

    private var swatches: [Color] {
        theme.hues.prefix(5).map { theme.courseColor(hue: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 18, height: 18)
                // Über den Index statt über die Farbe: `Color` ist nicht
                // Hashable, und ein Tupel aus `enumerated()` lässt sich im
                // ForEach-Abschluss nicht in zwei Parameter zerlegen.
                ForEach(swatches.indices, id: \.self) { index in
                    Circle()
                        .fill(swatches[index])
                        .frame(width: 12, height: 12)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                }
            }

            Text(theme.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(theme.blurb)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardCorner, style: .continuous)
                .strokeBorder(isSelected ? theme.accent : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Zeigt an echten Bausteinen, wie sich die Wahl auswirkt — ein Farbkreis
/// allein verrät nicht, ob der Stundenplan hinterher lesbar ist.
struct ThemePreviewRows: View {
    private let samples = ["Analysis I", "Technische Informatik", "Statistik"]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(samples, id: \.self) { name in
                HStack(spacing: 10) {
                    AccentBar(seed: name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                        Text("Mo 10:15 – 11:45 · Raum 1101.B305")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Chip(text: "VL", color: Tint.color(name))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Tint.surface(name))
                )
            }
        }
        .padding(.vertical, 2)
    }
}
