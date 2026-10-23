import Foundation

/// 母音的前三個共振峰（成年男聲，Hz）與頻寬。
public enum Vowel: String, CaseIterable, Sendable {
    case a, i, u

    var formants: [(frequency: Double, bandwidth: Double)] {
        switch self {
        case .a: [(730, 80), (1090, 90), (2440, 120)]
        case .i: [(270, 60), (2290, 100), (3010, 120)]
        case .u: [(300, 60), (870, 90), (2240, 120)]
        }
    }
}

/// 聲音類型：決定共振峰的整體位置（女聲、童聲的聲道較短，共振峰較高）。
public enum VoiceType: String, CaseIterable, Sendable {
    case male, female, child

    var formantScale: Double {
        switch self {
        case .male: 1.0
        case .female: 1.17
        case .child: 1.3
        }
    }

    /// 演唱音域（MIDI）：男聲 C3–E4、女聲 A3–A5、童聲 C4–C6。
    public var range: ClosedRange<Int> {
        switch self {
        case .male: 48...64
        case .female: 57...81
        case .child: 60...84
        }
    }
}

/// 人聲模擬訊號：聲源（1/h 遞減的泛音）經過母音共振峰塑形，可加顫音、滑音與音量包絡。
///
/// 共振峰會讓靠近 F1／F2 的高次泛音強於基頻（例如男聲 /a/ 基頻 130 Hz 時，第 6 泛音
/// 約為基頻的 2 倍），用來驗證偵測器不會選到高次泛音。
public struct VoiceSynthesizer: Sendable {
    public let voiceType: VoiceType
    public let vowel: Vowel
    public let sampleRate: Double

    public init(voiceType: VoiceType, vowel: Vowel, sampleRate: Double) {
        self.voiceType = voiceType
        self.vowel = vowel
        self.sampleRate = sampleRate
    }

    /// 各次泛音的相對振幅（基頻為第 0 個），總和正規化為 1；只含低於 Nyquist 90% 的泛音。
    public func harmonicAmplitudes(fundamental: Double) -> [Double] {
        let count = max(1, Int(0.45 * sampleRate / fundamental))
        let raw = (1...count).map { h in
            let frequency = Double(h) * fundamental
            return envelope(at: frequency) / Double(h)
        }
        let total = raw.reduce(0, +)
        return raw.map { $0 / total }
    }

    /// 共振峰包絡：三個二階共振的乘積，直流增益為 1。
    func envelope(at frequency: Double) -> Double {
        vowel.formants.reduce(1.0) { gain, formant in
            let center = formant.frequency * voiceType.formantScale
            let bandwidth = formant.bandwidth * voiceType.formantScale
            let denominator = sqrt(pow(center * center - frequency * frequency, 2) + pow(bandwidth * frequency, 2))
            return gain * center * center / denominator
        }
    }

    /// - Parameters:
    ///   - pitch: 時間（秒）→ 基頻（Hz）；nil 表示靜音
    ///   - loudness: 時間（秒）→ 音量倍率（0–1），用來模擬同音重複時的重新咬字
    public func render(count: Int, amplitude: Double = 0.3,
                       pitch: (Double) -> Double?, loudness: (Double) -> Double = { _ in 1 }) -> [Float] {
        let fadeStep = 1 / (0.015 * sampleRate)
        var output = [Float](repeating: 0, count: count)
        var phase = 0.0
        var gate = 0.0
        var amplitudes: [Double] = []
        var lastFrequency = 0.0
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let frequency = pitch(time)
            gate = frequency == nil ? max(0, gate - fadeStep) : min(1, gate + fadeStep)
            if let frequency {
                // 每 32 個樣本依瞬時頻率更新泛音振幅（顫音會改變各泛音落在共振峰的位置）
                if index % 32 == 0 || amplitudes.isEmpty { amplitudes = harmonicAmplitudes(fundamental: frequency) }
                lastFrequency = frequency
            }
            guard gate > 0, lastFrequency > 0 else { continue }
            var value = 0.0
            for (h, a) in amplitudes.enumerated() {
                value += a * sin(2 * .pi * Double(h + 1) * phase)
            }
            output[index] = Float(amplitude * gate * loudness(time) * value)
            phase += lastFrequency / sampleRate
            if phase >= 1 { phase -= 1 }
        }
        return output
    }
}

extension VoiceSynthesizer {
    /// 顫音的音高曲線：中心頻率乘上 2^(depth·sin(2πrt)/1200)。
    public static func vibrato(center: Double, rate: Double, depthCents: Double, phase: Double = 0) -> (Double) -> Double {
        { time in center * pow(2, depthCents * sin(2 * .pi * rate * time + phase) / 1200) }
    }
}
