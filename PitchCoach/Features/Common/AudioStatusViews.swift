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

/// 練習設定頁在收音不可用時的提示與可做的事。收音被中斷後，iOS 不一定會建議自動恢復
/// （例如其他 App 仍在播放），所以練習頁本身要提供恢復方式，不能只在調音器頁。
struct AudioUnavailableNotice: Equatable {
    enum Action: Equatable {
        case resume
        case retry
        case openSettings
    }

    let message: String
    let action: Action?

    init?(state: AudioPipeline.State) {
        switch state {
        case .running:
            return nil
        case .idle:
            (message, action) = ("收音啟動中…", nil)
        case .suspended:
            (message, action) = ("收音已暫停（被來電或其他 App 中斷）。", .resume)
        case .failed(let reason):
            (message, action) = ("無法啟動收音：\(reason)", .retry)
        case .permissionDenied:
            (message, action) = ("需要麥克風權限才能練習。", .openSettings)
        }
    }
}

/// 放在練習「開始」按鈕下方：說明收音為什麼不可用，並提供恢復、重試或前往設定。
struct AudioUnavailableFooter: View {
    let notice: AudioUnavailableNotice
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notice.message)
            switch notice.action {
            case .resume:
                Button("恢復收音") { pipeline.resume() }.accessibilityIdentifier("practice.resumeAudio")
            case .retry:
                Button("重試") { pipeline.resume() }
            case .openSettings:
                Button("前往設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case nil:
                EmptyView()
            }
        }
    }
}
