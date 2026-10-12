import SwiftUI

@main
struct CoretanApp: App {
    @StateObject private var store = DocumentStore.shared
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
