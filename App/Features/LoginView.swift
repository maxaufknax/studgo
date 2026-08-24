import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    private static let brand = Color(red: 0.05, green: 0.24, blue: 0.55)

    var body: some View {
        ZStack {
            // Ruhiger Verlauf statt einer weißen Fläche — dieselben Töne wie
            // im App-Symbol, damit Start und Symbol zusammengehören.
            LinearGradient(colors: [Color(red: 0.14, green: 0.16, blue: 0.48),
                                    Color(red: 0.05, green: 0.41, blue: 0.75)],
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

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 66))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            Text("StudGo")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 18)

            Text("Stud.IP der Leibniz Universität Hannover —\naufs Wesentliche reduziert.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
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
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}
