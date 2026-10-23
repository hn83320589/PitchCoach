import Foundation
import Testing
@testable import SignalKit

struct SignalKitTests {
    @Test func seededGeneratorIsDeterministic() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        var c = SplitMix64(seed: 43)
        let seqA = (0..<8).map { _ in a.next() }
        let seqB = (0..<8).map { _ in b.next() }
        let seqC = (0..<8).map { _ in c.next() }
        #expect(seqA == seqB)
        #expect(seqA != seqC)
    }

    @Test func harmonicSignalEqualsSumOfSines() {
        let partials = [Partial(harmonic: 1, amplitude: 0.3, phase: 0.1), Partial(harmonic: 2, amplitude: 0.6, phase: 1.2)]
        let signal = SignalGenerator.harmonic(fundamental: 220, partials: partials, sampleRate: 48000, count: 512)
        for i in [0, 17, 300, 511] {
            let t = Double(i) / 48000
            let expected = 0.3 * sin(2 * .pi * 220 * t + 0.1) + 0.6 * sin(2 * .pi * 440 * t + 1.2)
            #expect(abs(Double(signal[i]) - expected) < 1e-6)
        }
    }

    @Test func addNoiseAchievesRequestedSNR() {
        var rng = SplitMix64(seed: 7)
        let clean = SignalGenerator.sine(frequency: 440, sampleRate: 48000, count: 48000, amplitude: 0.5)
        let noisy = SignalGenerator.addNoise(to: clean, snrDB: 20, using: &rng)
        let noise = zip(noisy, clean).map { $0 - $1 }
        let measured = 20 * log10(SignalGenerator.rms(clean) / SignalGenerator.rms(noise))
        #expect(abs(measured - 20) < 0.1)
    }

    @Test func whiteNoiseHasRequestedRMSAndZeroMean() {
        var rng = SplitMix64(seed: 1)
        let noise = SignalGenerator.whiteNoise(count: 100_000, rms: 0.1, using: &rng)
        let mean = noise.reduce(0.0) { $0 + Double($1) } / Double(noise.count)
        #expect(abs(SignalGenerator.rms(noise) - 0.1) < 0.002)
        #expect(abs(mean) < 0.002)
    }
}
