import SwiftUI

@main
struct PitchCoachApp: App {
    @State private var settings = AppSettings()
    @State private var pipeline = AudioPipeline()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(pipeline)
        }
    }
}
