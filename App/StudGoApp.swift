import SwiftUI

@main
struct StudGoApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .task { await auth.restore() }
        }
    }
}
