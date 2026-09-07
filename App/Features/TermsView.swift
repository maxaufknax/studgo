import SwiftUI

/// Die Nutzungsbedingungen zum Lesen.
///
/// Erreichbar an zwei Stellen: vor der Anmeldung (dort mit dem Knopf zum
/// Zustimmen) und später in den Einstellungen (dort nur zum Nachlesen).
struct TermsView: View {
    /// Zeigt den Knopf „Zustimmen und fortfahren“. Aus, wenn der Text nur
    /// nachgelesen wird.
    var showsAcceptance = false

    @Environment(ModerationStore.self) private var moderation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Nutzungsbedingungen")
                        .font(.largeTitle.bold())

                    Text("Fassung \(ModerationStore.termsVersion) · gilt für StudGo auf diesem Gerät")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(Terms.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showsAcceptance ? "Abbrechen" : "Fertig") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showsAcceptance {
                    Button {
                        moderation.acceptTerms()
                        dismiss()
                    } label: {
                        Text("Zustimmen und fortfahren")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
        }
    }
}

/// Die Zustimmungszeile auf dem Anmeldebildschirm.
///
/// **Warum ein eigenes Häkchen und kein blosser Hinweis:** Richtlinie 1.2
/// verlangt, dass die Bedingungen *vor* der Anmeldung angenommen werden. Ein
/// Satz im Kleingedruckten ist keine Annahme — ein Häkchen, ohne das es nicht
/// weitergeht, schon.
struct TermsGate: View {
    @Environment(ModerationStore.self) private var moderation
    @State private var showsTerms = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                showsTerms = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: moderation.hasAcceptedTerms ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(moderation.hasAcceptedTerms ? Color.accentColor : Color.white.opacity(0.7))
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(moderation.hasAcceptedTerms
                             ? "Nutzungsbedingungen angenommen"
                             : "Nutzungsbedingungen lesen und annehmen")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(Terms.summary)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet die Nutzungsbedingungen")
        }
        .sheet(isPresented: $showsTerms) {
            TermsView(showsAcceptance: !moderation.hasAcceptedTerms)
        }
    }
}
