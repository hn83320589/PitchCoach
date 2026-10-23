import Foundation

/// 判斷回音消除能否在目前的輸出路由穩定運作（docs/SINGING_MODE.md §8）。
///
/// 某些裝置（例如 iOS 模擬器）開啟 voice processing 後，引擎啟動約 0.1 秒就自己停下並發出設定變更通知；
/// 若每次都照常重建，會無限重啟。連續發生 `maximumFailures` 次就停用該路由的回音消除，
/// 退回不消除的模式（快速衰減的提示音＋建議戴耳機）。
struct VoiceProcessingGuard {
    /// 啟動後多久內停下算「開不起來」。
    static let failureWindow: TimeInterval = 1
    static let maximumFailures = 2

    private var voiceProcessingStartTime: TimeInterval?
    private var consecutiveFailures = 0
    private var unstableRoutes: Set<String> = []

    func allowsVoiceProcessing(on route: String) -> Bool {
        !unstableRoutes.contains(route)
    }

    mutating func engineStarted(voiceProcessing: Bool, at time: TimeInterval) {
        voiceProcessingStartTime = voiceProcessing ? time : nil
    }

    mutating func engineStoppedItself(at time: TimeInterval, route: String) {
        defer { voiceProcessingStartTime = nil }
        guard let start = voiceProcessingStartTime, time - start <= Self.failureWindow else {
            consecutiveFailures = 0
            return
        }
        consecutiveFailures += 1
        if consecutiveFailures >= Self.maximumFailures {
            unstableRoutes.insert(route)
            consecutiveFailures = 0
        }
    }
}
