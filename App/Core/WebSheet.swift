import SafariServices
import SwiftUI

/// Öffnet eine Stud.IP-Seite im eingebauten Safari.
///
/// Nötig für alles, was die JSON:API nicht kann — allen voran das **An- und
/// Abmelden zu Veranstaltungen**: `Routes\Courses\Rel\Memberships::authorize()`
/// gibt für jede Methode außer GET hart `false` zurück, und
/// `PATCH /v1/course-memberships/{id}` ändert nur Farbgruppe und
/// Sichtbarkeit. Es gibt schlicht keine Route dafür.
///
/// Der `SFSafariViewController` läuft in einem eigenen Prozess: StudGo
/// bekommt weder die Sitzung noch die Eingaben zu sehen. Umgekehrt teilt er
/// sich die Cookies mit Safari — wer dort angemeldet ist, ist es hier auch,
/// muss sich sonst aber einmal anmelden.
///
/// **Im Demo-Modus** führt keiner dieser Wege irgendwohin: Hinter jeder
/// Adresse steht die Anmeldung der Leibniz Universität, und wer die Demo
/// benutzt, hat dort per Definition kein Konto. Ihn auf einen
/// Anmeldebildschirm zu schicken, den er nicht bedienen kann, wäre eine
/// Sackgasse — StudGo sagt stattdessen, wohin der Knopf im Betrieb führt.
/// Deshalb ist `WebSheet` eine gewöhnliche Ansicht mit einer Weiche und der
/// Safari-Aufsatz nur ihr einer Zweig.
struct WebSheet: View {
    let url: URL

    @Environment(AuthStore.self) private var auth

    var body: some View {
        if auth.isDemo {
            DemoWebNotice(url: url)
        } else {
            SafariView(url: url)
        }
    }
}

/// Was im Demo-Modus an der Stelle einer Stud.IP-Seite steht.
private struct DemoWebNotice: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Weiter geht es in Stud.IP", systemImage: "globe.badge.chevron.backward")
            } description: {
                VStack(spacing: 12) {
                    Text("Im angemeldeten Betrieb öffnet dieser Knopf eine Seite deiner Hochschule — dort wird ein- und ausgetragen, das Profilbild geändert und die Prüfungsverwaltung erreicht.")

                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text("Die Seite verlangt eine Uni-Kennung und bleibt in der Demo deshalb außen vor.")
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Damit sich eine Adresse direkt als `sheet(item:)` verwenden lässt.
struct WebTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
