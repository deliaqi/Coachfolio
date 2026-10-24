import SwiftUI

@main
struct CoachJournalApp: App {
    @State private var store = StudioStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .tint(StudioColor.forest)
                .preferredColorScheme(.light)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            OpenAISettingsView()
        }
    }
}

enum StudioColor {
    static let canvas = Color(red: 0.965, green: 0.961, blue: 0.937)
    static let forest = Color(red: 0.153, green: 0.310, blue: 0.267)
    static let ink = Color(red: 0.118, green: 0.173, blue: 0.153)
    static let muted = Color(red: 0.427, green: 0.482, blue: 0.447)
    static let line = Color(red: 0.882, green: 0.894, blue: 0.863)
    static let mint = Color(red: 0.882, green: 0.933, blue: 0.878)
    static let blue = Color(red: 0.875, green: 0.922, blue: 0.945)
    static let peach = Color(red: 0.976, green: 0.914, blue: 0.855)
    static let white = Color(red: 0.996, green: 0.996, blue: 0.980)
}
