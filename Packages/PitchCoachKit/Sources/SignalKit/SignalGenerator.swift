import Foundation

/// 諧波成分：第 `harmonic` 倍頻、振幅與初始相位（弧度）。
public struct Partial: Sendable, Equatable {
    public let harmonic: Int
    public let amplitude: Double
    public let phase: Double

    public init(harmonic: Int, amplitude: Double, phase: Double = 0) {
        self.harmonic = harmonic
        self.amplitude = amplitude
        self.phase = phase
    }
}

/// 合成測試訊號。內部以 Double 計算，輸出 Float（與 AVAudioEngine 的格式相同）。
public enum SignalGenerator {
    public static func sine(
        frequency: Double, sampleRate: Double, count: Int, amplitude: Double = 0.5, phase: Double = 0
    ) -> [Float] {
        harmonic(fundamental: frequency, partials: [Partial(harmonic: 1, amplitude: amplitude, phase: phase)],
                 sampleRate: sampleRate, count: count)
    }

    public static func harmonic(fundamental: Double, partials: [Partial], sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { i in
            let t = Double(i) / sampleRate
            let value = partials.reduce(0.0) { sum, p in
                sum + p.amplitude * sin(2 * .pi * fundamental * Double(p.harmonic) * t + p.phase)
            }
            return Float(value)
        }
    }

    /// 高斯白噪音（Box–Muller）。
    public static func whiteNoise(count: Int, rms: Double, using rng: inout some RandomNumberGenerator) -> [Float] {
        (0..<count).map { _ in
            let u1 = Double.random(in: Double.leastNonzeroMagnitude...1, using: &rng)
            let u2 = Double.random(in: 0..<1, using: &rng)
            return Float(rms * sqrt(-2 * log(u1)) * cos(2 * .pi * u2))
        }
    }

    /// 加入白噪音，使訊雜比（以實際量到的 RMS 計）恰為 `snrDB`。
    public static func addNoise(to signal: [Float], snrDB: Double, using rng: inout some RandomNumberGenerator) -> [Float] {
        let raw = whiteNoise(count: signal.count, rms: 1, using: &rng)
        let targetRMS = rms(signal) / pow(10, snrDB / 20)
        let scale = Float(targetRMS / rms(raw))
        return zip(signal, raw).map { $0 + $1 * scale }
    }

    public static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return sqrt(sumOfSquares / Double(samples.count))
    }
}
