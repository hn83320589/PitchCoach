import SwiftUI
import UIKit

struct MicrophonePermissionView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("需要麥克風權限", systemImage: "mic.slash")
        } description: {
            Text("PitchCoach 要用麥克風聽你演奏的音高。請到「設定」開啟麥克風權限。")
        } actions: {
            Button("前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct AudioErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("無法啟動收音", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重試", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct AudioSuspendedView: View {
    let resume: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("收音已暫停", systemImage: "pause.circle")
        } description: {
            Text("收音被來電或其他 App 中斷。")
        } actions: {
            Button("恢復收音", action: resume)
                .buttonStyle(.borderedProminent)
        }
    }
}
