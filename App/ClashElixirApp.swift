import SwiftUI

@main
struct ClashElixirApp: App {
    @StateObject private var engine = ElixirEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
    }
}
