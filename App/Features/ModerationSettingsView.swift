import SwiftUI

/// Alles zum Thema Melden und Blockieren an einer Stelle.
///
/// Erreichbar über *Profil → Melden und Blockieren*. Hier steht, was die App
/// von sich aus verdeckt, wer blockiert ist, und wie eine Meldung ihren Weg
/// nimmt — Dinge, die sonst nur dann sichtbar wären, wenn gerade etwas
/// schiefgeht.
struct ModerationSettingsView: View {
    @Environment(ModerationStore.self) private var moderation
    @Environment(\.openURL) private var openURL
    @State private var showsTerms = false

    var body: some View {
        @Bindable var moderation = moderation

        List {
            Section {
                Toggle("Anstößige Inhalte verdecken", isOn: $moderation.hidesObjectionable)
            } footer: {
                Text("Beiträge mit beleidigender oder herabwürdigender Sprache werden verdeckt und erst auf Tippen angezeigt. Der Filter greift in Blubber, im Postfach, im Forum und im Aktivitätenstrom.")
            }

            Section("Blockierte Personen") {
                if moderation.blocklist.isEmpty {
                    Text("Niemand blockiert.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(moderation.blocklist.entries, id: \.id) { entry in
                        HStack {
                            InitialsBadge(initials: Self.initials(of: entry.name), size: 30)
                            Text(entry.name)
                            Spacer(minLength: 8)
                            Button("Aufheben") {
                                moderation.unblock(id: entry.id)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section {
                Button {
                    showsTerms = true
                } label: {
                    RowLabel(symbol: "doc.plaintext", title: "Nutzungsbedingungen")
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "mailto:\(AppConfig.moderationMail)?subject=StudGo%20Moderation") {
                        openURL(url)
                    }
                } label: {
                    RowLabel(symbol: "envelope",
                             title: "Etwas melden, das hier nicht passt",
                             subtitle: AppConfig.moderationMail)
                }
                .buttonStyle(.plain)
            } footer: {
                Text("So meldest du einen einzelnen Beitrag: lange darauf tippen und „Beitrag melden“ wählen — oder in der Detailansicht das Menü oben rechts. Wir sehen uns jede Meldung innerhalb von 24 Stunden an, entfernen anstößige Inhalte und schließen Verfasser aus, die wiederholt auffallen.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Melden und Blockieren")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTerms) {
            TermsView()
        }
    }

    private static func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        return parts.isEmpty ? "?" : parts.joined()
    }
}
