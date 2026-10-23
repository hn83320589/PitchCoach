import Foundation
import Testing
@testable import PitchDetection
import SignalKit

/// AC-06：以固定種子產生 500 組隨機頻率與隨機泛音組成的訊號。
///
/// 訊號分佈（docs/ARCHITECTURE.md §12）：
/// - 基頻：65–2,100 Hz 對數均勻分佈
/// - 取樣率：44.1 kHz 或 48 kHz 隨機
/// - 基頻振幅 1.0；2–8 次泛音振幅各為 U[0, 1]；所有成分相位隨機
/// - 只加入低於 Nyquist 頻率 90% 的泛音；整體正規化到峰值約 0.5
struct MPMPropertyTests {
    private static let caseCount = 500
    private static let seed: UInt64 = 20261023

    @Test func randomHarmonicSignalsHaveNoOctaveErrorsAndStayWithinFiveCents() throws {
        var rng = SplitMix64(seed: Self.seed)
        var detectors: [Double: MPMPitchDetector] = [:]
        var octaveErrors = 0
        var worstCents = 0.0

        for index in 0..<Self.caseCount {
            let sampleRate = sampleRates.randomElement(using: &rng)!
            let detector = detectors[sampleRate] ?? makeDetector(sampleRate: sampleRate)
            detectors[sampleRate] = detector

            let frequency = 65 * pow(2100.0 / 65, Double.random(in: 0...1, using: &rng))
            var partials = [Partial(harmonic: 1, amplitude: 1, phase: .random(in: 0..<(2 * .pi), using: &rng))]
            for harmonic in 2...8 {
                let amplitude = Double.random(in: 0...1, using: &rng)
                let phase = Double.random(in: 0..<(2 * .pi), using: &rng)
                if frequency * Double(harmonic) < 0.45 * sampleRate {
                    partials.append(Partial(harmonic: harmonic, amplitude: amplitude, phase: phase))
                }
            }
            let total = partials.reduce(0) { $0 + $1.amplitude }
            let normalized = partials.map { Partial(harmonic: $0.harmonic, amplitude: 0.5 * $0.amplitude / total, phase: $0.phase) }
            let signal = SignalGenerator.harmonic(fundamental: frequency, partials: normalized,
                                                  sampleRate: sampleRate, count: detector.windowSize)

            let estimate = try #require(detector.detect(signal), "case \(index): \(frequency) Hz 沒有輸出")
            if isOctaveError(estimate.frequency, frequency) { octaveErrors += 1 }
            let cents = abs(centsError(estimate.frequency, frequency))
            worstCents = max(worstCents, cents)
            #expect(cents < 5, "case \(index): \(frequency) Hz @\(sampleRate) → \(estimate.frequency)")
        }

        #expect(octaveErrors == 0)
        print("性質測試：\(Self.caseCount) 組，八度錯誤 \(octaveErrors) 組，最大誤差 \(worstCents) cents")
    }
}
