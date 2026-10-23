import Testing
@testable import PitchCoach

struct AudioUnavailableNoticeTests {
    @Test func runningPipelineNeedsNoNotice() {
        #expect(AudioUnavailableNotice(state: .running) == nil)
    }

    @Test func suspendedPipelineOffersResumeOnPracticePage() {
        // 中斷結束時 iOS 不一定建議恢復（例如其他 App 仍在播放）：練習頁本身就要能恢復，不能只在調音器頁
        let notice = AudioUnavailableNotice(state: .suspended)
        #expect(notice?.action == .resume)
        #expect(notice?.message.contains("暫停") == true)
    }

    @Test func failedPipelineShowsReasonAndOffersRetry() {
        let notice = AudioUnavailableNotice(state: .failed("沒有可用的輸入"))
        #expect(notice?.action == .retry)
        #expect(notice?.message.contains("沒有可用的輸入") == true)
    }

    @Test func deniedPermissionPointsToSettingsAndStartingHasNoAction() {
        #expect(AudioUnavailableNotice(state: .permissionDenied)?.action == .openSettings)
        let starting = AudioUnavailableNotice(state: .idle)
        #expect(starting?.action == nil)
        #expect(starting?.message.contains("啟動") == true)
    }
}
