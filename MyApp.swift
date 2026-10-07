import SwiftUI

@main struct MyApp: App {
    @State private var store = DebtStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
