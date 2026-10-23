import Testing
@testable import PitchCoach

struct VoiceProcessingGuardTests {
    @Test func engineStoppingRightAfterStartTwiceDisablesVoiceProcessingForThatRoute() {
        var monitor = VoiceProcessingGuard()
        #expect(monitor.allowsVoiceProcessing(on: "Speaker:1"))

        monitor.engineStarted(voiceProcessing: true, at: 10)
        monitor.engineStoppedItself(at: 10.1, route: "Speaker:1")
        // 一次可能只是正常的硬體重新設定，再試一次
        #expect(monitor.allowsVoiceProcessing(on: "Speaker:1"))

        monitor.engineStarted(voiceProcessing: true, at: 10.5)
        monitor.engineStoppedItself(at: 10.6, route: "Speaker:1")
        #expect(!monitor.allowsVoiceProcessing(on: "Speaker:1"))
        // 換了輸出路由就重新嘗試
        #expect(monitor.allowsVoiceProcessing(on: "Speaker:2"))
    }

    @Test func onlyConsecutiveStopsShortlyAfterVoiceProcessingStartCount() {
        var monitor = VoiceProcessingGuard()
        monitor.engineStarted(voiceProcessing: true, at: 0)
        monitor.engineStoppedItself(at: 0.1, route: "Speaker:1")
        // 穩定運作一段時間後才停下：與回音消除無關，重新計算
        monitor.engineStarted(voiceProcessing: true, at: 1)
        monitor.engineStoppedItself(at: 5, route: "Speaker:1")
        monitor.engineStarted(voiceProcessing: true, at: 6)
        monitor.engineStoppedItself(at: 6.1, route: "Speaker:1")
        #expect(monitor.allowsVoiceProcessing(on: "Speaker:1"))

        // 沒開回音消除的引擎停下也不算，並中斷連續計數
        monitor.engineStarted(voiceProcessing: false, at: 7)
        monitor.engineStoppedItself(at: 7.1, route: "Speaker:1")
        monitor.engineStarted(voiceProcessing: true, at: 8)
        monitor.engineStoppedItself(at: 8.1, route: "Speaker:1")
        #expect(monitor.allowsVoiceProcessing(on: "Speaker:1"))
    }
}
