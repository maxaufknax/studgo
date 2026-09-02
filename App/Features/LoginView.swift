import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    private static let brand = Brand.deep

    var body: some View {
        ZStack {
            // Dieselbe Achse wie Logo und App-Symbol: fast Schwarz nach
            // Logoblau. Vorher lief hier ein Indigo-Verlauf, der mit beidem
            // nichts zu tun hatte.
            LinearGradient(colors: [Brand.night, Brand.deep],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            // Quer auf einem kleinen iPhone bleibt weniger Höhe, als der
            // Inhalt braucht — ohne Scrollfläche rutschte der Anmeldeknopf aus
            // dem Bild. `minHeight` sorgt dafür, dass die Spacer bei genug
            // Platz weiterhin mittig ausrichten.
            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Das echte Logo statt Symbol plus gesetzter Wortmarke: Die
            // Nachbildung traf weder die Schrift noch das Blau.
            AppLogoView(size: 132, cornerRadius: 30)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            Text("Dein Stud.IP —\naufs Wesentliche reduziert.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.top, 18)
                .padding(.horizontal, 32)

            // Steht hier und nicht in den Einstellungen: Wer die App zum
            // ersten Mal öffnet — Studierende wie die App-Prüfung — soll die
            // Unabhängigkeit lesen, bevor er sich anmeldet, nicht danach.
            Text("Privates, quelloffenes Studierendenprojekt. Keine offizielle App einer Hochschule.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 32)

            Spacer(minLength: 32)

            VStack(spacing: 14) {
                if let message = auth.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.red.opacity(0.35))
                        )
                }

                Button {
                    Task { await auth.signIn() }
                } label: {
                    Group {
                        if auth.isWorking {
                            ProgressView().tint(Self.brand)
                        } else {
                            // Die Farbe steht am Text, nicht am Button: über
                            // den Button gesetzt überschreibt der Stil sie
                            // wieder und die Schrift bliebe weiß.
                            Text("Mit Stud.IP anmelden")
                                .fontWeight(.semibold)
                                .foregroundStyle(Self.brand)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .controlSize(.large)
                .disabled(auth.isWorking)

                Text("Die Anmeldung läuft direkt bei studip.uni-hannover.de. StudGo speichert die Zugangstoken nur lokal auf diesem Gerät.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                demoSection
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    /// **Der Weg in die App ohne Kennung der Leibniz Universität.**
    ///
    /// Die Anmeldung führt über Shibboleth; wer dort kein Konto hat — die
    /// Prüfung im App Store, Studieninteressierte, jeder vor der
    /// Einschreibung — käme sonst über diesen Bildschirm nicht hinaus. Der
    /// Knopf steht deshalb sichtbar hier und nicht in einer Einstellung:
    /// Was man erst suchen muss, ist kein Zugang.
    ///
    /// Was dahinter passiert, steht in `DemoData`.
    private var demoSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                line
                Text("oder")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                line
            }
            .padding(.top, 6)

            Button {
                Task { await auth.signInDemo() }
            } label: {
                Label("Demo ohne Anmeldung ansehen", systemImage: "play.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.large)
            .disabled(auth.isWorking)

            Text("Zeigt die vollständige App mit Beispieldaten — Stundenplan, Kurse, Postfach und Campus. Es werden keine Daten übertragen.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(height: 1)
    }
}
