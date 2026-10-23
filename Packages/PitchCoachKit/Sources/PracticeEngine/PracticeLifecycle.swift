/// 練習被中斷的原因。App 層把 AVAudioSession 通知、背景切換等轉成此值。
public enum PracticeInterruptionReason: String, CaseIterable, Sendable {
    /// 來電、鬧鐘、其他 App 佔用音訊。
    case audioInterruption
    /// 插拔耳機、連接或中斷藍牙裝置。
    case routeChange
    case appBackgrounded
    case mediaServicesReset
    case engineFailure
}

public enum PracticeState: Equatable, Sendable {
    case ready
    case running
    case completed
    case interrupted(PracticeInterruptionReason)
    /// 使用者主動放棄，不存檔。
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .ready, .running: false
        case .completed, .interrupted, .cancelled: true
        }
    }
}

public enum PracticeLifecycleEvent: Equatable, Sendable {
    case start
    case complete
    case cancel
    case interrupt(PracticeInterruptionReason)
}

/// 練習的生命週期（docs/ARCHITECTURE.md §3.5）。中斷後不續接，以已完成的部分存檔。
public struct PracticeLifecycle: Equatable, Sendable {
    public private(set) var state: PracticeState = .ready

    public init() {}

    /// 回傳是否發生狀態轉換；不適用於目前狀態的事件會被忽略。
    @discardableResult
    public mutating func handle(_ event: PracticeLifecycleEvent) -> Bool {
        switch (state, event) {
        case (.ready, .start):
            state = .running
        case (.running, .complete):
            state = .completed
        case (.running, .cancel):
            state = .cancelled
        case (.running, .interrupt(let reason)):
            state = .interrupted(reason)
        default:
            return false
        }
        return true
    }
}
