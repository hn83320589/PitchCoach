import Foundation
import Testing
import MusicTheory
import PitchDetection
import SingingEngine
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

    @Test func singingResultKeepsAccuraciesOutcomesAndPlausibleDeviations() throws {
        let timeline = try SongTimeline(melody: MelodyParser.parse("C4:1 D4:1 E4:1"), beatsPerMinute: 60, reference: .default)
        var evaluator = SingingEvaluator(timeline: timeline, reference: .default, options: SingingOptions())
        // C4 準、D4 低八度（−1200，不列入各音偏差）、E4 沒唱
        for (index, cents) in [(0, 6.0), (1, -1200.0)] {
            for t in stride(from: Double(index), to: Double(index + 1), by: 0.01) {
                let note = timeline.notes[index].pitch
                evaluator.process(SungFrame(time: .milliseconds(Int64(t * 1000)),
                                            frequency: NoteConverter.frequency(of: note, reference: .default) * pow(2, cents / 1200),
                                            levelDB: -20, levelTime: .milliseconds(Int64(t * 1000))))
            }
        }
        let summary = SessionSummary(singing: evaluator.result(), title: "測試", startedAt: start, activeDuration: 3)
        #expect(summary.kind == .singing)
        #expect(summary.status == .completed)
        #expect(summary.title == "測試")
        #expect(abs(summary.singingPitchAccuracy! - 1.0 / 3) < 1e-9)
        #expect(summary.noteOutcomes.map(\.accurate) == [true, false, false])
        #expect(summary.noteStats.map(\.note.midi) == [60])
    }
}
