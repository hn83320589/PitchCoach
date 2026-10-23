import AVFAudio
import Foundation
import PracticeEngine
import Testing
@testable import PitchCoach

struct AudioSessionEventMappingTests {
    @Test func interruptionNotificationsMapToBeganAndEnded() {
        let began = Notification(name: AVAudioSession.interruptionNotification, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
        ])
        let ended = Notification(name: AVAudioSession.interruptionNotification, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ])
        let endedWithoutResume = Notification(name: AVAudioSession.interruptionNotification, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
        ])
        #expect(AudioSessionEvent(notification: began) == .interruptionBegan)
        #expect(AudioSessionEvent(notification: ended) == .interruptionEnded(shouldResume: true))
        #expect(AudioSessionEvent(notification: endedWithoutResume) == .interruptionEnded(shouldResume: false))
    }

    @Test func routeChangeReasonsMapToDeviceChanges() {
        func route(_ reason: AVAudioSession.RouteChangeReason) -> AudioSessionEvent? {
            AudioSessionEvent(notification: Notification(name: AVAudioSession.routeChangeNotification,
                                                         userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]))
        }
        #expect(route(.newDeviceAvailable) == .routeChanged(.deviceConnected))
        #expect(route(.oldDeviceUnavailable) == .routeChanged(.deviceDisconnected))
        #expect(route(.categoryChange) == .routeChanged(.other))
    }

    @Test func mediaResetAndEngineConfigurationChangeAreRecognized() {
        #expect(AudioSessionEvent(notification: Notification(name: AVAudioSession.mediaServicesWereResetNotification)) == .mediaServicesReset)
        #expect(AudioSessionEvent(notification: Notification(name: .AVAudioEngineConfigurationChange)) == .engineConfigurationChanged)
        #expect(AudioSessionEvent(notification: Notification(name: Notification.Name("Unrelated"))) == nil)
    }
}

struct AudioInterruptionPolicyTests {
    private func commands(_ event: AudioSessionEvent, _ state: AudioInterruptionPolicy.PipelineStatus = .running) -> [PipelineCommand] {
        AudioInterruptionPolicy.commands(for: event, status: state)
    }

    @Test func phoneCallInterruptsPracticeAndResumesDetectionAfterward() {
        #expect(commands(.interruptionBegan) == [.interruptPractice(.audioInterruption), .suspend])
        #expect(commands(.interruptionEnded(shouldResume: true), .suspended) == [.restart])
        // 系統沒有建議恢復（例如其他 App 開始播放音樂）：等使用者按「恢復收音」
        #expect(commands(.interruptionEnded(shouldResume: false), .suspended).isEmpty)
    }

    @Test func pluggingOrUnpluggingHeadphonesInterruptsPracticeAndRebuildsEngine() {
        #expect(commands(.routeChanged(.deviceConnected)) == [.interruptPractice(.routeChange), .restart])
        // 拔耳機時依 iOS 慣例暫停伴奏，避免突然從喇叭放出聲音
        #expect(commands(.routeChanged(.deviceDisconnected)) == [.interruptPractice(.routeChange), .pauseAccompaniment, .restart])
        #expect(commands(.routeChanged(.other)).isEmpty)
    }

    @Test func backgroundingSuspendsAndForegroundingRestarts() {
        #expect(commands(.appBackgrounded) == [.interruptPractice(.appBackgrounded), .suspend])
        #expect(commands(.appForegrounded, .suspended) == [.restart])
        #expect(commands(.appForegrounded, .running).isEmpty)
    }

    @Test func mediaServicesResetAndConfigurationChangeRestartEngine() {
        #expect(commands(.mediaServicesReset) == [.interruptPractice(.mediaServicesReset), .restart])
        #expect(commands(.engineConfigurationChanged) == [.restart])
    }

    @Test func configurationChangeDuringSongInterruptsSinging() {
        // 伴奏播放器跟著引擎重建，原本的演唱接不回去；不中斷的話畫面會永遠停在「預備…」
        #expect(AudioInterruptionPolicy.commands(for: .engineConfigurationChanged, status: .running, isSongPlaying: true)
                == [.interruptPractice(.engineFailure), .restart])
        #expect(AudioInterruptionPolicy.commands(for: .engineConfigurationChanged, status: .running, isSongPlaying: false)
                == [.restart])
    }

    @Test func eventsAreIgnoredBeforePipelineStarts() {
        for event: AudioSessionEvent in [.interruptionBegan, .routeChanged(.deviceConnected), .engineConfigurationChanged,
                                         .mediaServicesReset, .appBackgrounded, .appForegrounded] {
            #expect(commands(event, .idle).isEmpty, "\(event)")
        }
    }

    @Test func routeChangeWhileSuspendedWaitsForResume() {
        // 暫停中不重建引擎（恢復時一律重建），但若練習仍在進行就要標記中斷
        #expect(commands(.routeChanged(.deviceDisconnected), .suspended) == [.interruptPractice(.routeChange), .pauseAccompaniment])
        #expect(commands(.engineConfigurationChanged, .suspended).isEmpty)
    }
}
