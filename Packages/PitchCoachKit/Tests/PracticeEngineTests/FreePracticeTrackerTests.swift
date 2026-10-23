import Foundation
import Testing
import PitchDetection
@testable import PracticeEngine

/// 自由練習（調音器畫面開著並演奏）的時間計算：
/// - 有音高的 frame 之間停頓 ≤ 5 秒算演奏時間（換弓、翻譜），> 5 秒不算
/// - 停頓超過 60 秒結束這一段
/// - 少於 30 秒不記錄
struct FreePracticeTrackerTests {
    private func feed(_ tracker: inout FreePracticeTracker, _ input: [PitchFrame]) -> [FreePracticeSegment] {
        input.compactMap { tracker.process($0) }
    }

    @Test func continuousPlayingIsCountedFromFirstToLastVoicedFrame() throws {
        var tracker = FreePracticeTracker()
        #expect(feed(&tracker, frames(from: 1000, through: 41000, step: 100, cents: 0)).isEmpty)
        #expect(tracker.isActive)
        let finished = tracker.finish()
        let segment = try #require(finished)
        #expect(segment.startTime == .milliseconds(1000))
        #expect(segment.activeDuration == .seconds(40))
        #expect(!tracker.isActive)
    }

    @Test func pausesUpToFiveSecondsAreCountedLongerOnesAreNot() throws {
        var bridged = FreePracticeTracker()
        _ = feed(&bridged, frames(from: 0, through: 20000, step: 100, cents: 0)
                 + frames(from: 20100, through: 23900, step: 100, cents: nil)
                 + frames(from: 24000, through: 44000, step: 100, cents: 0))
        let bridgedSegment = bridged.finish()
        #expect(try #require(bridgedSegment).activeDuration == .seconds(44))

        var split = FreePracticeTracker()
        _ = feed(&split, frames(from: 0, through: 20000, step: 100, cents: 0)
                 + frames(from: 26000, through: 46000, step: 100, cents: 0))
        let splitSegment = split.finish()
        #expect(try #require(splitSegment).activeDuration == .seconds(40))
    }

    @Test func silenceLongerThanOneMinuteEndsSegment() {
        var tracker = FreePracticeTracker()
        let segments = feed(&tracker, frames(from: 0, through: 40000, step: 100, cents: 0)
                            + frames(from: 41000, through: 101000, step: 1000, cents: nil)
                            + frames(from: 102000, through: 112000, step: 100, cents: 0))
        #expect(segments.map(\.activeDuration) == [.seconds(40)])
        #expect(tracker.isActive)                 // 第二段已開始
        let second = tracker.finish()
        #expect(second == nil)                    // 第二段只有 10 秒，不記錄
    }

    @Test func shortPlayingIsNotRecorded() {
        var tracker = FreePracticeTracker()
        _ = feed(&tracker, frames(from: 0, through: 29000, step: 100, cents: 0))
        let segment = tracker.finish()
        #expect(segment == nil)
    }
}
