import SwiftUI

@main
struct AyeKitchenApp: App {
    @State private var session = SessionStore()

    init() {
        KitchenTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .fontDesign(.rounded)
                .foregroundStyle(.inkPrimary)
        }
    }
}
