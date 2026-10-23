import SwiftUI

struct RootView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TunerView()
                .tabItem { Label("調音器", systemImage: "tuningfork") }
            PracticeHomeView()
                .tabItem { Label("練習", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .task { await pipeline.start() }
        .onChange(of: scenePhase) { _, phase in
            // 只看背景／前景；下拉控制中心等 .inactive 不暫停
            switch phase {
            case .background: pipeline.handle(.appBackgrounded)
            case .active: pipeline.handle(.appForegrounded)
            default: break
            }
        }
    }
}
