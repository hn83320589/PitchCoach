import AVFAudio
import Foundation
import PracticeEngine

/// 影響收音的系統事件，由 Notification 或 scenePhase 轉換而來。
enum AudioSessionEvent: Equatable, Sendable {
    enum RouteChange: Equatable, Sendable {
        case deviceConnected
        case deviceDisconnected
        case other
    }

    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(RouteChange)
    case mediaServicesReset
    case engineConfigurationChanged
    case appBackgrounded
    case appForegrounded

    /// 不相關的通知回傳 nil。
    init?(notification: Notification) {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return nil }
            switch type {
            case .began:
                self = .interruptionBegan
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                self = .interruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
            @unknown default:
                return nil
            }
        case AVAudioSession.routeChangeNotification:
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            switch AVAudioSession.RouteChangeReason(rawValue: rawReason) {
            case .newDeviceAvailable: self = .routeChanged(.deviceConnected)
            case .oldDeviceUnavailable: self = .routeChanged(.deviceDisconnected)
            default: self = .routeChanged(.other)
            }
        case AVAudioSession.mediaServicesWereResetNotification:
            self = .mediaServicesReset
        case .AVAudioEngineConfigurationChange:
            self = .engineConfigurationChanged
        default:
            return nil
        }
    }
}

enum PipelineCommand: Equatable, Sendable {
    /// 通知進行中的練習：以此原因標記為中斷。
    case interruptPractice(PracticeInterruptionReason)
    /// 停止引擎，等待恢復。
    case suspend
    /// 重新設定 session 並建立新的引擎（取樣率可能已改變）。
    case restart
    case pauseAccompaniment
}

/// 系統事件 → 收音管線要做的事（docs/ARCHITECTURE.md §3.5）。純函式，可脫離 AVAudioSession 測試。
enum AudioInterruptionPolicy {
    enum PipelineStatus: Equatable, Sendable {
        case idle
        case running
        case suspended
    }

    /// - Parameter isSongPlaying: 歌唱伴奏播放中。伴奏播放器跟著引擎重建，原本的演唱接不回去。
    static func commands(for event: AudioSessionEvent, status: PipelineStatus, isSongPlaying: Bool = false) -> [PipelineCommand] {
        guard status != .idle else { return [] }
        let isRunning = status == .running

        switch event {
        case .interruptionBegan:
            return isRunning ? [.interruptPractice(.audioInterruption), .suspend] : []
        case .interruptionEnded(let shouldResume):
            return !isRunning && shouldResume ? [.restart] : []
        case .routeChanged(.deviceConnected):
            return [.interruptPractice(.routeChange)] + (isRunning ? [.restart] : [])
        case .routeChanged(.deviceDisconnected):
            return [.interruptPractice(.routeChange), .pauseAccompaniment] + (isRunning ? [.restart] : [])
        case .routeChanged(.other):
            return []
        case .mediaServicesReset:
            return [.interruptPractice(.mediaServicesReset)] + (isRunning ? [.restart] : [])
        case .engineConfigurationChanged:
            guard isRunning else { return [] }
            return isSongPlaying ? [.interruptPractice(.engineFailure), .restart] : [.restart]
        case .appBackgrounded:
            return isRunning ? [.interruptPractice(.appBackgrounded), .suspend] : []
        case .appForegrounded:
            return isRunning ? [] : [.restart]
        }
    }
}
