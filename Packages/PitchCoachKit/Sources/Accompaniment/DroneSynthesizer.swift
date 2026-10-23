import Foundation

public struct DroneSettings: Sendable, Equatable {
    public var isEnabled: Bool
    public var frequency: Double
    /// 0–1。
    public var volume: Float

    public init(isEnabled: Bool = false, frequency: Double = 220, volume: Float = 0.4) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.volume = volume
    }
}

/// 持續低音合成器：基音＋柔和的 2、3 次泛音。
///
/// - 開關與音量變化以 20 ms 線性淡入淡出，避免爆音
/// - 以相位累加器產生波形，換頻時相位連續
///
/// `render` 不配置記憶體，只能由音訊 IO 執行緒呼叫。
public final class DroneSynthesizer: @unchecked Sendable {
    public let settings = RealtimeParameter(DroneSettings())

    private static let partials: [(harmonic: Double, amplitude: Double)] = [(1, 1), (2, 0.3), (3, 0.15)]

    private let sampleRate: Double
    private let gainStep: Float
    private let normalization: Double
    private var phase = 0.0     // 以週期為單位，0..<1
    private var gain: Float = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        gainStep = Float(1 / (0.02 * sampleRate))
        // 正規化到波形峰值 = 1
        var peak = 0.0
        for i in 0..<1000 {
            peak = max(peak, abs(Self.waveform(Double(i) / 1000)))
        }
        normalization = 1 / peak
    }

    public func render(into output: UnsafeMutablePointer<Float>, frameCount: Int) {
        let current = settings.readForRealtime()
        let target: Float = current.isEnabled ? current.volume : 0
        let increment = current.frequency / sampleRate
        for i in 0..<frameCount {
            if gain < target {
                gain = min(target, gain + gainStep)
            } else if gain > target {
                gain = max(target, gain - gainStep)
            }
            output[i] = gain == 0 ? 0 : Float(Self.waveform(phase) * normalization) * gain
            phase += increment
            if phase >= 1 { phase -= 1 }
        }
    }

    private static func waveform(_ phase: Double) -> Double {
        partials.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * $1.harmonic * phase) }
    }
}
