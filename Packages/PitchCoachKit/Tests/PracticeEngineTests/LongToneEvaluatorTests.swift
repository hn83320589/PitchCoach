import Foundation
import Testing
import MusicTheory
import PitchDetection
@testable import PracticeEngine

struct LongToneEvaluatorTests {
    private func evaluate(_ cents: [Double?], duration: Duration = .milliseconds(100), startMs: Int = 0) -> LongToneEvaluator {
        var evaluator = LongToneEvaluator(target: a4, reference: .default, duration: duration)
        for (index, value) in cents.enumerated() {
            _ = evaluator.process(frame(startMs + index * 10, cents: value))
        }
        return evaluator
    }

    /// 手算：10 個 frame，cents = [0, 5, 10, 12, −8, —, 60, −10, 3, 20]
    /// - ±10 以內（含邊界）：0, 5, 10, −8, −10, 3 → 6 / 10 = 0.6
    /// - 平均與標準差只用有音高且 |c| ≤ 50 者：[0, 5, 10, 12, −8, −10, 3, 20]
    ///   平均 = 32 / 8 = 4.0；母體變異數 = (16+1+36+64+144+196+1+256) / 8 = 89.25 → 標準差 9.4472
    /// - 有音高比例：9 / 10（60 cents 雖是錯音仍算有音高）
    @Test func metricsMatchHandCalculation() throws {
        let evaluator = evaluate([0, 5, 10, 12, -8, nil, 60, -10, 3, 20])
        let result = evaluator.result()
        #expect(abs(result.inToleranceRatio - 0.6) < 1e-12)
        #expect(abs(try #require(result.meanCents) - 4.0) < 1e-9)
        #expect(abs(try #require(result.standardDeviationCents) - 89.25.squareRoot()) < 1e-9)
        #expect(abs(result.voicedRatio - 0.9) < 1e-12)
        #expect(result.statFrameCount == 8)
    }

    @Test func toleranceBoundaryOf10CentsIsInclusive() {
        let result = evaluate([10, -10, 10.01, -10.01]).result()
        #expect(abs(result.inToleranceRatio - 0.5) < 1e-12)
    }

    @Test func timingStartsAtFirstVoicedFrame() {
        var evaluator = LongToneEvaluator(target: a4, reference: .default, duration: .milliseconds(100))
        #expect(evaluator.process(frame(0, cents: nil)) == .waitingForSound)
        #expect(evaluator.process(frame(10, cents: nil)) == .waitingForSound)
        guard case .running(let elapsed, let cents) = evaluator.process(frame(20, cents: 3)) else {
            Issue.record("第一個有音高的 frame 應開始計時"); return
        }
        #expect(elapsed == .zero)
        #expect(abs((cents ?? .nan) - 3) < 1e-9)
        #expect(evaluator.process(frame(70, cents: nil)) == .running(elapsed: .milliseconds(50), cents: nil))
    }

    @Test func finishesAtDurationAndIgnoresLaterFrames() {
        var evaluator = LongToneEvaluator(target: a4, reference: .default, duration: .milliseconds(100))
        for ms in stride(from: 0, through: 90, by: 10) { _ = evaluator.process(frame(ms, cents: 0)) }
        #expect(evaluator.process(frame(100, cents: 40)) == .finished)
        #expect(evaluator.process(frame(110, cents: 40)) == .finished)
        let result = evaluator.result()
        #expect(result.isComplete)
        #expect(result.inToleranceRatio == 1)
        #expect(result.analyzedDuration == .milliseconds(100))
    }

    @Test func interruptedResultCoversElapsedPortionOnly() throws {
        let result = evaluate([0, 2, 4, 6, 8], duration: .seconds(10)).result()
        #expect(!result.isComplete)
        #expect(result.analyzedDuration == .milliseconds(40))
        #expect(result.inToleranceRatio == 1)
        #expect(abs(try #require(result.meanCents) - 4) < 1e-9)
    }

    @Test func deviationCurveIsDownsampledTo20Hz() throws {
        // 200 ms、每 10 ms 一個 frame → 4 個 50 ms 區間；第 3 區間全部無音高
        let cents: [Double?] = [0, 0, 0, 0, 10] + [-5, -5, -5, -5, -5] + [nil, nil, nil, nil, nil] + [60, 4, 4, 4, 4]
        let curve = evaluate(cents, duration: .milliseconds(200)).result().curve
        #expect(curve.count == 4)
        #expect(abs(try #require(curve[0]) - 2) < 1e-9)
        #expect(abs(try #require(curve[1]) + 5) < 1e-9)
        #expect(curve[2] == nil)
        #expect(abs(try #require(curve[3]) - 4) < 1e-9)   // 60 cents 為錯音，不畫進曲線
    }

    @Test func noUsableFramesGivesNilStatistics() {
        let result = evaluate([70, -80, 90]).result()
        #expect(result.inToleranceRatio == 0)
        #expect(result.meanCents == nil)
        #expect(result.standardDeviationCents == nil)
    }
}
