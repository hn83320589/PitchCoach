import Foundation
import Testing
@testable import SingingEngine

struct VibratoAnalyzerTests {
    /// 約每 10.7 ms 一點（hop 512 @ 48 kHz）
    private func series(duration: Double, _ cents: (Double) -> Double) -> (times: [Double], cents: [Double]) {
        let times = Array(stride(from: 0, to: duration, by: 512 / 48000.0))
        return (times, times.map(cents))
    }

    @Test func recoversRateDepthAndCenterOfSinusoidalVibrato() throws {
        let data = series(duration: 0.7) { 7 + 60 * sin(2 * .pi * 5.5 * $0 + 0.4) }
        let estimate = try #require(VibratoAnalyzer.analyze(times: data.times, cents: data.cents, compensation: { _ in 1 }))
        #expect(abs(estimate.rate - 5.5) < 0.05)
        #expect(abs(estimate.depthCents - 60) < 0.5)
        #expect(abs(estimate.centerCents - 7) < 0.5)
    }

    @Test func centerIgnoresLinearDriftAcrossNote() throws {
        // 音高從 −6 漂到 +6（平均 0），疊加 6 Hz ±40 cents 的顫音
        let data = series(duration: 0.8) { -6 + 15 * $0 + 40 * sin(2 * .pi * 6 * $0) }
        let estimate = try #require(VibratoAnalyzer.analyze(times: data.times, cents: data.cents, compensation: { _ in 1 }))
        #expect(abs(estimate.centerCents) < 0.5)
        #expect(abs(estimate.rate - 6) < 0.05)
    }

    @Test func steadyOrNoisyPitchIsNotVibrato() {
        var state: UInt64 = 7
        let data = series(duration: 0.8) { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 40) / Double(1 << 24) * 6 - 3     // ±3 cents 雜訊
        }
        #expect(VibratoAnalyzer.analyze(times: data.times, cents: data.cents, compensation: { _ in 1 }) == nil)
    }

    @Test func seriesShorterThanOneAndAHalfCyclesIsNotAnalyzed() {
        let data = series(duration: 0.2) { 60 * sin(2 * .pi * 5.5 * $0) }   // 1.1 個週期
        #expect(VibratoAnalyzer.analyze(times: data.times, cents: data.cents, compensation: { _ in 1 }) == nil)
    }

    @Test func analysisWindowCompensationIsUnityAtZeroAndDecreasesWithRate() {
        let gain = VibratoAnalyzer.windowGain(windowDuration: 2048 / 48000.0)
        #expect(abs(gain(0) - 1) < 1e-9)
        #expect(gain(5.5) < 1 && gain(5.5) > 0.9)
        #expect(gain(9) < gain(5.5))
    }
}
