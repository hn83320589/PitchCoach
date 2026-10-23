import Foundation

public struct MetronomeSettings: Sendable, Equatable {
    public static let tempoRange = 40...208

    public var isEnabled: Bool
    /// 夾在 40–208 BPM。
    public var beatsPerMinute: Int {
        didSet { beatsPerMinute = Self.clamp(beatsPerMinute) }
    }
    /// 0–1。
    public var volume: Float

    public init(isEnabled: Bool = false, beatsPerMinute: Int = 60, volume: Float = 0.6) {
        self.isEnabled = isEnabled
        self.beatsPerMinute = Self.clamp(beatsPerMinute)
        self.volume = volume
    }

    private static func clamp(_ bpm: Int) -> Int {
        min(tempoRange.upperBound, max(tempoRange.lowerBound, bpm))
    }
}

/// 樣本精準的節拍器合成器。
///
/// - 拍點以「距上一拍的樣本數」累計，小數部分保留，長時間不漂移
/// - click 用指數衰減的噪音爆發，沒有明確週期，漏進麥克風時不會被當成音高
///
/// `render` 不配置記憶體，只能由音訊 IO 執行緒呼叫。
public final class MetronomeSynthesizer: @unchecked Sendable {
    public let settings = RealtimeParameter(MetronomeSettings())

    private let sampleRate: Double
    private let click: UnsafeMutablePointer<Float>
    private let clickLength: Int
    private var wasEnabled = false
    private var samplesSinceBeat = 0.0
    private var clickPosition = Int.max

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        clickLength = Int(sampleRate * 0.015)
        click = .allocate(capacity: clickLength)
        // 固定種子的 xorshift 噪音 × 指數衰減（時間常數 3 ms）
        var state: UInt32 = 0x9E37_79B9
        for i in 0..<clickLength {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            let noise = Float(state) / Float(UInt32.max) * 2 - 1
            let envelope = Float(exp(-Double(i) / (sampleRate * 0.003)))
            click[i] = (noise == 0 ? 0.5 : noise) * envelope
        }
    }

    deinit {
        click.deallocate()
    }

    public func render(into output: UnsafeMutablePointer<Float>, frameCount: Int) {
        let current = settings.readForRealtime()
        guard current.isEnabled else {
            wasEnabled = false
            clickPosition = .max
            output.initialize(repeating: 0, count: frameCount)
            return
        }
        let samplesPerBeat = sampleRate * 60 / Double(current.beatsPerMinute)
        if !wasEnabled {
            wasEnabled = true
            samplesSinceBeat = samplesPerBeat   // 開啟的瞬間就是第一拍
        }
        for i in 0..<frameCount {
            if samplesSinceBeat >= samplesPerBeat {
                samplesSinceBeat -= samplesPerBeat
                clickPosition = 0
            }
            if clickPosition < clickLength {
                output[i] = click[clickPosition] * current.volume
                clickPosition += 1
            } else {
                output[i] = 0
            }
            samplesSinceBeat += 1
        }
    }
}
