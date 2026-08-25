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
struct WebSheet: UIViewControllerRepresentable {
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
