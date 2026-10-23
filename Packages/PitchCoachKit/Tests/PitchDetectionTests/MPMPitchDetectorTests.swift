import Foundation
import Testing
@testable import PitchDetection
import SignalKit

struct MPMPitchDetectorTests {
    // MARK: - AC-02 純正弦，誤差 < 1 cent

    @Test func pureSineEverySemitoneAt44100IsWithinOneCent() throws {
        try assertPureSinesWithinOneCent(sampleRate: 44100)
    }

    @Test func pureSineEverySemitoneAt48000IsWithinOneCent() throws {
        try assertPureSinesWithinOneCent(sampleRate: 48000)
    }

    private func assertPureSinesWithinOneCent(sampleRate: Double) throws {
        let detector = makeDetector(sampleRate: sampleRate)
        for frequency in semitoneFrequencies {
            let signal = SignalGenerator.sine(frequency: frequency, sampleRate: sampleRate,
                                              count: detector.windowSize, phase: deterministicPhase(frequency))
            let estimate = try #require(detector.detect(signal), "\(frequency) Hz 沒有輸出")
            #expect(abs(centsError(estimate.frequency, frequency)) < 1, "\(frequency) Hz → \(estimate.frequency)")
        }
    }

    @Test func accuracyHoldsAcrossInputLevels() throws {
        let detector = makeDetector(sampleRate: 48000)
        for levelDB in stride(from: -40.0, through: 0, by: 10) {
            let amplitude = pow(10, levelDB / 20)
            let signal = SignalGenerator.sine(frequency: 442, sampleRate: 48000, count: detector.windowSize, amplitude: amplitude)
            let estimate = try #require(detector.detect(signal), "\(levelDB) dBFS 沒有輸出")
            #expect(abs(centsError(estimate.frequency, 442)) < 1)
        }
    }

    @Test func dcOffsetDoesNotAffectEstimate() throws {
        let detector = makeDetector(sampleRate: 48000)
        let signal = SignalGenerator.sine(frequency: 196, sampleRate: 48000, count: detector.windowSize, amplitude: 0.3)
            .map { $0 + 0.4 }
        let estimate = try #require(detector.detect(signal))
        #expect(abs(centsError(estimate.frequency, 196)) < 1)
    }

    // MARK: - AC-03 二次泛音比基頻強 2 倍，不發生八度錯誤

    @Test func strongSecondHarmonicCausesNoOctaveErrorAt44100() throws {
        try assertNoOctaveErrorWithStrongSecondHarmonic(sampleRate: 44100)
    }

    @Test func strongSecondHarmonicCausesNoOctaveErrorAt48000() throws {
        try assertNoOctaveErrorWithStrongSecondHarmonic(sampleRate: 48000)
    }

    private func assertNoOctaveErrorWithStrongSecondHarmonic(sampleRate: Double) throws {
        let detector = makeDetector(sampleRate: sampleRate)
        for frequency in semitoneFrequencies {
            let partials = [Partial(harmonic: 1, amplitude: 0.25), Partial(harmonic: 2, amplitude: 0.5, phase: 0.7)]
            let signal = SignalGenerator.harmonic(fundamental: frequency, partials: partials,
                                                  sampleRate: sampleRate, count: detector.windowSize)
            let estimate = try #require(detector.detect(signal), "\(frequency) Hz 沒有輸出")
            #expect(!isOctaveError(estimate.frequency, frequency), "\(frequency) Hz → \(estimate.frequency)")
            #expect(abs(centsError(estimate.frequency, frequency)) < 1, "\(frequency) Hz → \(estimate.frequency)")
        }
    }

    // MARK: - 弓弦振動（Helmholtz motion）近似鋸齒波：泛音一路延伸到 Nyquist，遠多於擬合模型的諧波數

    @Test func sawtoothWithHarmonicsUpToNyquistIsWithinOneCent() throws {
        for sampleRate in sampleRates {
            let detector = makeDetector(sampleRate: sampleRate)
            for frequency in semitoneFrequencies {
                let partials = (1...Int(0.45 * sampleRate / frequency)).map { Partial(harmonic: $0, amplitude: 0.3 / Double($0)) }
                let signal = SignalGenerator.harmonic(fundamental: frequency, partials: partials,
                                                      sampleRate: sampleRate, count: detector.windowSize)
                let estimate = try #require(detector.detect(signal), "\(frequency) Hz 沒有輸出")
                #expect(abs(centsError(estimate.frequency, frequency)) < 1, "\(frequency) Hz @\(sampleRate) → \(estimate.frequency)")
            }
        }
    }

    // MARK: - AC-04 白噪音 SNR 20 dB，誤差 < 3 cents

    @Test func whiteNoiseAt20dBSNRStaysWithinThreeCents() throws {
        let detector = makeDetector(sampleRate: 48000)
        var rng = SplitMix64(seed: 2026)
        for frequency in semitoneFrequencies {
            let clean = SignalGenerator.sine(frequency: frequency, sampleRate: 48000,
                                             count: detector.windowSize, phase: deterministicPhase(frequency))
            let noisy = SignalGenerator.addNoise(to: clean, snrDB: 20, using: &rng)
            let estimate = try #require(detector.detect(noisy), "\(frequency) Hz 沒有輸出")
            #expect(abs(centsError(estimate.frequency, frequency)) < 3, "\(frequency) Hz → \(estimate.frequency)")
        }
    }

    // MARK: - AC-05 靜音或純噪音不輸出音高

    @Test func silenceProducesNoPitch() {
        let detector = makeDetector(sampleRate: 48000)
        #expect(detector.detect([Float](repeating: 0, count: detector.windowSize)) == nil)
    }

    @Test func signalBelowLevelGateProducesNoPitch() {
        let detector = makeDetector(sampleRate: 48000)
        let quiet = SignalGenerator.sine(frequency: 440, sampleRate: 48000, count: detector.windowSize, amplitude: 0.0003)
        #expect(detector.detect(quiet) == nil)
    }

    @Test func whiteNoiseProducesNoPitch() {
        let detector = makeDetector(sampleRate: 48000)
        var rng = SplitMix64(seed: 99)
        for rms in [0.01, 0.1, 0.3] {
            for _ in 0..<50 {
                let noise = SignalGenerator.whiteNoise(count: detector.windowSize, rms: rms, using: &rng)
                #expect(detector.detect(noise) == nil, "rms \(rms)")
            }
        }
    }

    // MARK: - 其他行為

    @Test func frequenciesOutsideDetectionRangeProduceNoPitch() {
        let detector = makeDetector(sampleRate: 48000)
        for frequency in [40.0, 3000] {
            let signal = SignalGenerator.sine(frequency: frequency, sampleRate: 48000, count: detector.windowSize)
            #expect(detector.detect(signal) == nil, "\(frequency) Hz")
        }
    }

    @Test func clarityIsHighForSineAndReportedLevelMatchesInput() throws {
        let detector = makeDetector(sampleRate: 48000)
        let signal = SignalGenerator.sine(frequency: 440, sampleRate: 48000, count: detector.windowSize, amplitude: 0.1)
        let estimate = try #require(detector.detect(signal))
        #expect(estimate.clarity > 0.99)
        // 振幅 0.1 的正弦，RMS = 0.0707 → −23.0 dBFS
        #expect(abs(estimate.levelDB - (-23.01)) < 0.1)
    }
}
