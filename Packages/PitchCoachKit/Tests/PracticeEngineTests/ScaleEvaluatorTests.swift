import Foundation
import Testing
import MusicTheory
import PitchDetection
@testable import PracticeEngine

/// 到位規則（docs/ARCHITECTURE.md §7.2）：
/// 1. 在範圍內 = 有音高且相對目標音 |c| ≤ 15.0
/// 2. 一段持續從第一個在範圍內的 frame（t₀）開始，在範圍內的 frame 滿足 t − t₀ ≥ 300 ms 時到位
/// 3. 範圍外（含無音高）的空檔 ≤ 50 ms 不重設計時；> 50 ms 才重設
/// 4. 只在「在範圍內」的 frame 上到位
struct ScaleEvaluatorTests {
    private let cMajor = try! MajorScale(key: .c, startOctave: 4, direction: .ascending, reference: .default)
    private var c4: Note { cMajor.steps[0] }

    private func feed(_ evaluator: inout ScaleEvaluator, _ input: [PitchFrame]) -> [ScaleEvent] {
        input.map { evaluator.process($0) }
    }

    private func advanceTimes(_ events: [ScaleEvent], _ input: [PitchFrame]) -> [Duration] {
        zip(events, input).compactMap { event, frame in
            if case .advanced = event { return frame.time }
            return nil
        }
    }

    // MARK: - 300 ms 邊界

    @Test func holding299msDoesNotAdvance() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        let events = feed(&evaluator, frames(from: 0, through: 299, cents: 0, note: c4))
        #expect(!events.contains { if case .advanced = $0 { true } else { false } })
        #expect(evaluator.currentStepIndex == 0)
    }

    @Test func holding300msAdvances() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        let input = frames(from: 0, through: 300, cents: 0, note: c4)
        let events = feed(&evaluator, input)
        #expect(advanceTimes(events, input) == [.milliseconds(300)])
        #expect(events.last == .advanced(from: 0, to: 1))
        #expect(evaluator.currentStepIndex == 1)
    }

    // MARK: - ±15 cents 邊界

    @Test func exactly15CentsOnEitherSideCountsAsInTolerance() {
        for cents in [15.0, -15.0] {
            var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
            let input = frames(from: 0, through: 300, cents: cents, note: c4)
            #expect(advanceTimes(feed(&evaluator, input), input) == [.milliseconds(300)], "\(cents)")
        }
    }

    @Test func justBeyond15CentsNeverAdvances() {
        for cents in [15.01, -15.01] {
            var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
            let input = frames(from: 0, through: 1000, cents: cents, note: c4)
            #expect(advanceTimes(feed(&evaluator, input), input).isEmpty, "\(cents)")
        }
    }

    // MARK: - 邊界附近抖動

    @Test func excursionOf50msIsBridged() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        let input = frames(from: 0, through: 100, cents: 14, note: c4)
            + frames(from: 101, through: 150, cents: 16, note: c4)      // 最後一個範圍外 frame 距上次範圍內 50 ms
            + frames(from: 151, through: 300, cents: 14, note: c4)
        #expect(advanceTimes(feed(&evaluator, input), input) == [.milliseconds(300)])
    }

    @Test func excursionLongerThan50msRestartsHold() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        let input = frames(from: 0, through: 100, cents: 14, note: c4)
            + frames(from: 101, through: 151, cents: 16, note: c4)      // 51 ms → 重設
            + frames(from: 152, through: 500, cents: 14, note: c4)
        #expect(advanceTimes(feed(&evaluator, input), input) == [.milliseconds(452)])
    }

    @Test func framesWithoutPitchCountAsOutOfTolerance() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        let input = frames(from: 0, through: 100, cents: 0, note: c4)
            + frames(from: 101, through: 160, cents: nil, note: c4)     // 60 ms 無音高 → 重設
            + frames(from: 161, through: 500, cents: 0, note: c4)
        #expect(advanceTimes(feed(&evaluator, input), input) == [.milliseconds(461)])
    }

    @Test func advancesOnlyOnInToleranceFrame() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        let input = frames(from: 0, through: 280, cents: 0, note: c4)
            + frames(from: 281, through: 320, cents: 30, note: c4)      // 40 ms 空檔（不重設）期間不到位
            + frames(from: 321, through: 330, cents: 0, note: c4)
        #expect(advanceTimes(feed(&evaluator, input), input) == [.milliseconds(321)])
    }

    // MARK: - 統計與流程

    @Test func stepMeanExcludesFramesBeyond50Cents() throws {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        // 從上一音滑進來的 +70 cents 不計；持續從 t = 50 開始，t = 350 到位
        // 計入的 frame：+10 ×50（t = 50…99）、+4 ×251（t = 100…350）
        _ = feed(&evaluator, frames(from: 0, through: 49, cents: 70, note: c4))
        _ = feed(&evaluator, frames(from: 50, through: 99, cents: 10, note: c4))
        _ = feed(&evaluator, frames(from: 100, through: 350, cents: 4, note: c4))
        let step = evaluator.result().steps[0]
        #expect(step.reached)
        #expect(step.frameCount == 301)
        let expectedMean: Double = (10.0 * 50 + 4.0 * 251) / 301
        #expect(abs(try #require(step.meanCents) - expectedMean) < 1e-9)
    }

    @Test func playingEveryStepInTuneCompletesRoundTrip() {
        let scale = try! MajorScale(key: .g, startOctave: 3, direction: .ascendingDescending, reference: .default)
        var evaluator = ScaleEvaluator(scale: scale, reference: .default)
        var advances = 0
        var ms = 0
        for note in scale.steps {
            for event in feed(&evaluator, frames(from: ms, through: ms + 300, step: 10, cents: 2, note: note)) {
                if case .advanced = event { advances += 1 }
            }
            ms += 400
        }
        #expect(scale.steps.count == 15)
        #expect(advances == 14)
        #expect(evaluator.isFinished)
        let result = evaluator.result()
        #expect(result.isComplete)
        #expect(result.reachedCount == 15)
    }

    @Test func worstThreeNotesMergeAscendingAndDescendingOccurrences() throws {
        let scale = try! MajorScale(key: .c, startOctave: 4, direction: .ascendingDescending, reference: .default)
        var evaluator = ScaleEvaluator(scale: scale, reference: .default)
        // 每步偏差：E4 上行 +12、下行 +2（合併 +7）；B4 −11；F4 +9；D4 上行 −1、下行 −12（合併 −6.5）；其餘 0
        let deviations: [Double] = [0, -1, 12, 9, 0, 0, -11, 0, -11, 0, 0, 9, 2, -12, 0]
        var ms = 0
        for (note, cents) in zip(scale.steps, deviations) {
            _ = feed(&evaluator, frames(from: ms, through: ms + 300, step: 10, cents: cents, note: note))
            ms += 400
        }
        let worst = evaluator.result().worstNotes
        #expect(worst.map { $0.note.name() } == ["B4", "F4", "E4"])
        #expect(abs(worst[0].meanCents + 11) < 1e-9)
        #expect(abs(worst[2].meanCents - 7) < 1e-9)
    }

    @Test func skippingMarksStepUnreachedAndKeepsItsFrames() throws {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        _ = feed(&evaluator, frames(from: 0, through: 99, cents: 25, note: c4))
        evaluator.skipCurrentStep()
        #expect(evaluator.currentStepIndex == 1)
        let step = evaluator.result().steps[0]
        #expect(!step.reached)
        #expect(step.frameCount == 100)
        #expect(abs(try #require(step.meanCents) - 25) < 1e-9)
    }

    @Test func interruptedResultKeepsCompletedSteps() {
        var evaluator = ScaleEvaluator(scale: cMajor, reference: .default)
        _ = feed(&evaluator, frames(from: 0, through: 300, step: 10, cents: 0, note: cMajor.steps[0]))
        _ = feed(&evaluator, frames(from: 400, through: 700, step: 10, cents: 0, note: cMajor.steps[1]))
        _ = feed(&evaluator, frames(from: 800, through: 900, step: 10, cents: 5, note: cMajor.steps[2]))
        let result = evaluator.result()
        #expect(!result.isComplete)
        #expect(result.reachedCount == 2)
        #expect(result.steps.map(\.reached) == [true, true, false, false, false, false, false, false])
        #expect(result.steps[2].frameCount == 11)
    }
}
