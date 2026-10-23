import Foundation
import Testing
@testable import PitchDetection
import SignalKit

/// 歌唱模式的共振峰風險（docs/SINGING_MODE.md §6）：母音共振峰讓某個高次泛音強於基頻時，
/// 偵測器不可選到高次泛音的週期。
struct VoiceDetectionTests {
    private func midiFrequency(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    @Test(arguments: VoiceType.allCases)
    func steadyVowelsInVoiceRangeHaveNoOctaveErrors(_ voiceType: VoiceType) throws {
        let detector = makeDetector(sampleRate: 48000)
        for vowel in Vowel.allCases {
            let voice = VoiceSynthesizer(voiceType: voiceType, vowel: vowel, sampleRate: 48000)
            for midi in voiceType.range {
                let frequency = midiFrequency(midi)
                let samples = voice.render(count: 4800 + 2048) { _ in frequency }
                let estimate = try #require(detector.detect(Array(samples[4800...])), "\(voiceType) /\(vowel)/ \(frequency) Hz 沒有輸出")
                #expect(!isOctaveError(estimate.frequency, frequency), "\(voiceType) /\(vowel)/ \(frequency) Hz → \(estimate.frequency)")
                #expect(abs(centsError(estimate.frequency, frequency)) < 1, "\(voiceType) /\(vowel)/ \(frequency) Hz → \(estimate.frequency)")
            }
        }
    }

    /// 5.5 Hz ±60 cents 的顫音：每個 frame 都應追蹤到音高曲線（不發生八度錯誤），
    /// 且讀數不超出顫音範圍（分析窗會平均掉一部分幅度，所以只會更小）。
    @Test func vibratoFramesFollowContourWithoutOctaveErrors() throws {
        let center = 196.0
        let voice = VoiceSynthesizer(voiceType: .male, vowel: .a, sampleRate: 48000)
        let samples = voice.render(count: 48000, pitch: VoiceSynthesizer.vibrato(center: center, rate: 5.5, depthCents: 60))
        let analyzer = StreamingPitchAnalyzer(configuration: PitchDetectorConfiguration(sampleRate: 48000))
        var deviations: [Double] = []
        samples.withUnsafeBufferPointer { buffer in
            analyzer.process(buffer, startingAt: 0) { frame in
                if frame.time > .milliseconds(100), let frequency = frame.frequency {
                    deviations.append(centsError(frequency, center))
                }
            }
        }
        #expect(deviations.count > 80)
        #expect(deviations.allSatisfy { abs($0) < 62 }, "最大偏差 \(deviations.map(abs).max() ?? 0)")
        #expect((deviations.max() ?? 0) > 45 && (deviations.min() ?? 0) < -45, "應追蹤到顫音的起伏")
    }
}
