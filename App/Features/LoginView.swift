import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("StudGo")
                    .font(.largeTitle.bold())
                Text("Stud.IP der Leibniz Universität Hannover — aufs Wesentliche reduziert.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await auth.signIn() }
            } label: {
                if auth.isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Mit Stud.IP anmelden").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(auth.isWorking)
            .padding(.horizontal, 32)

            Text("Die Anmeldung läuft direkt bei studip.uni-hannover.de. StudGo speichert nur die Zugangstoken lokal auf diesem Gerät.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
        }
    }
}
