import Foundation
@testable import PitchDetection
import SignalKit

/// 題目要求：65 Hz 到 2,100 Hz 每個半音各取一個（65·2^(k/12)，k = 0…60，再加上 2,100 Hz 端點）。
let semitoneFrequencies: [Double] = (0...60).map { 65 * pow(2, Double($0) / 12) } + [2100]

let sampleRates: [Double] = [44100, 48000]

func centsError(_ estimate: Double, _ truth: Double) -> Double {
    1200 * log2(estimate / truth)
}

/// 偏差在 1200 ± 100 cents（或其倍數）附近即視為八度錯誤。
func isOctaveError(_ estimate: Double, _ truth: Double) -> Bool {
    let cents = abs(centsError(estimate, truth))
    return cents > 600
}

func makeDetector(sampleRate: Double) -> MPMPitchDetector {
    MPMPitchDetector(configuration: PitchDetectorConfiguration(sampleRate: sampleRate))
}

/// 每個頻率用不同但固定的初始相位，避免所有測試都從相位 0 開始。
func deterministicPhase(_ frequency: Double) -> Double {
    (frequency * 7.919).truncatingRemainder(dividingBy: 2 * .pi)
}
