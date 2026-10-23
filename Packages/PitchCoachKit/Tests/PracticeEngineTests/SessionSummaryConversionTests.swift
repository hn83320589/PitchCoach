import Foundation
import Testing
import MusicTheory
import PitchDetection
@testable import PracticeEngine

struct SessionSummaryConversionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func longToneResultBecomesSummaryWithTargetNoteStat() throws {
        var evaluator = LongToneEvaluator(target: a4, reference: .default, duration: .milliseconds(100))
        for (index, cents) in [0.0, 4, 8, 20, 70].enumerated() {
            _ = evaluator.process(frame(index * 10, cents: cents))
        }
        let result = evaluator.result()
        let summary = SessionSummary(longTone: result, startedAt: start)

        #expect(summary.kind == .longTone)
        #expect(summary.status == .interrupted)            // 未滿 100 ms
        #expect(summary.activeDuration == 0.04)
        #expect(summary.longToneAccuracy == result.inToleranceRatio)
        #expect(summary.longToneMeanCents == result.meanCents)
        let stat = try #require(summary.noteStats.first)
        #expect(summary.noteStats.count == 1)
        #expect(stat.note == a4)
        #expect(abs(stat.meanCents - 8) < 1e-9)            // (0 + 4 + 8 + 20) / 4；70 為錯音不計
        #expect(stat.frameCount == 4)
    }

    @Test func scaleResultKeepsOnlyStepsWithFrames() throws {
        let scale = try MajorScale(key: .c, startOctave: 4, direction: .ascending, reference: .default)
        var evaluator = ScaleEvaluator(scale: scale, reference: .default)
        for ms in stride(from: 0, through: 300, by: 10) { _ = evaluator.process(frame(ms, cents: 6, note: scale.steps[0])) }
        for ms in stride(from: 400, through: 450, by: 10) { _ = evaluator.process(frame(ms, cents: -3, note: scale.steps[1])) }
        let summary = SessionSummary(scale: evaluator.result(), startedAt: start, activeDuration: 0.45)

        #expect(summary.kind == .scale)
        #expect(summary.status == .interrupted)
        #expect(summary.scaleReachedSteps == 1)
        #expect(summary.scaleTotalSteps == 8)
        #expect(summary.noteStats.map(\.note) == [scale.steps[0], scale.steps[1]])
        #expect(summary.noteStats.map(\.frameCount) == [31, 6])
    }

    @Test func explicitStatusOverridesCompleteness() {
        let evaluator = LongToneEvaluator(target: a4, reference: .default)
        let summary = SessionSummary(longTone: evaluator.result(), startedAt: start, status: .completed)
        #expect(summary.status == .completed)
        #expect(summary.noteStats.isEmpty)
    }
}
