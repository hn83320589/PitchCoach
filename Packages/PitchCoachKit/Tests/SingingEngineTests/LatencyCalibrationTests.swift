import Foundation
import Testing
import MusicTheory
@testable import SingingEngine

struct LatencyCalibrationTests {
    private func result(delay: Double, detected: Int) throws -> SingingResult {
        let timeline = try LatencyCalibration.timeline(reference: .default)
        var evaluator = SingingEvaluator(timeline: timeline, reference: .default, options: SingingOptions())
        var frames: [SungFrame] = []
        for note in timeline.notes.prefix(detected) {
            let start = seconds(note.start), end = seconds(note.end)
            frames += syntheticFrames(from: start - 0.15, to: start + delay, target: note.pitch) { _ in nil }
            frames += syntheticFrames(from: start + delay, to: end, target: note.pitch) { _ in 0 }
        }
        frames.sorted { $0.time < $1.time }.forEach { evaluator.process($0) }
        return evaluator.result()
    }

    @Test func offsetIsMedianOnsetDelayOfCalibrationTones() throws {
        let offset = try #require(LatencyCalibration.offset(from: result(delay: 0.06, detected: 8)))
        #expect(abs(offset - 0.06) < 0.002)
    }

    @Test func tooFewDetectedTonesGiveNoCalibration() throws {
        #expect(LatencyCalibration.offset(from: try result(delay: 0.06, detected: 4)) == nil)
    }
}
