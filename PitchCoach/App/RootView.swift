import SwiftUI

struct RootView: View {
    @Environment(AudioPipeline.self) private var pipeline

    var body: some View {
        TabView {
            TunerView()
                .tabItem { Label("調音器", systemImage: "tuningfork") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .task { await pipeline.start() }
    }
}
