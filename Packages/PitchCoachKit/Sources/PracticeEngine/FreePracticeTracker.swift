import PitchDetection

public struct FreePracticeSegment: Equatable, Sendable {
    /// 第一個有音高的 frame 的時間（串流時間）。
    public let startTime: Duration
    public let activeDuration: Duration
}

/// 自由練習（開著調音器演奏）的演奏時間。
///
/// - 有音高的 frame 之間停頓 ≤ `bridgeGap` 計入演奏時間（換弓、換氣、翻譜），超過則不計
/// - 距上一個有音高的 frame 超過 `sessionTimeout` 時結束這一段
/// - 演奏時間少於 `minimumDuration` 的段落不記錄（例如只是試一下音準）
public struct FreePracticeTracker: Sendable {
    public let bridgeGap: Duration
    public let sessionTimeout: Duration
    public let minimumDuration: Duration

    private var segmentStart: Duration?
    private var lastVoiced: Duration?
    private var activeDuration: Duration = .zero

    public init(bridgeGap: Duration = .seconds(5), sessionTimeout: Duration = .seconds(60),
                minimumDuration: Duration = .seconds(30)) {
        self.bridgeGap = bridgeGap
        self.sessionTimeout = sessionTimeout
        self.minimumDuration = minimumDuration
    }

    /// 是否正在一段演奏中。
    public var isActive: Bool { segmentStart != nil }

    /// 停頓逾時而結束一段時，回傳該段（若達到最短長度）。
    public mutating func process(_ frame: PitchFrame) -> FreePracticeSegment? {
        if frame.frequency != nil {
            if let lastVoiced {
                let gap = frame.time - lastVoiced
                if gap <= bridgeGap { activeDuration += gap }
            } else {
                segmentStart = frame.time
            }
            lastVoiced = frame.time
            return nil
        }
        if let lastVoiced, frame.time - lastVoiced > sessionTimeout {
            return finish()
        }
        return nil
    }

    /// 離開畫面、進入背景或被中斷時呼叫，結束目前這一段。
    public mutating func finish() -> FreePracticeSegment? {
        defer {
            segmentStart = nil
            lastVoiced = nil
            activeDuration = .zero
        }
        guard let segmentStart, activeDuration >= minimumDuration else { return nil }
        return FreePracticeSegment(startTime: segmentStart, activeDuration: activeDuration)
    }
}
