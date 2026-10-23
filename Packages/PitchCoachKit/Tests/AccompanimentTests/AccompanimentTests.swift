import Foundation
import Testing
@testable import Accompaniment
import PitchDetection

struct MetronomeSynthesizerTests {
    private func render(_ synth: MetronomeSynthesizer, count: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: count)
        // 以 IO buffer 大小（256）分段，貼近實際呼叫方式
        var offset = 0
        while offset < count {
            let n = min(256, count - offset)
            buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress! + offset, frameCount: n) }
            offset += n
        }
        return buffer
    }

    /// 每個 click 的第一個非零樣本位置。
    private func onsets(_ samples: [Float]) -> [Int] {
        var result: [Int] = []
        var silentRun = Int.max
        for (index, value) in samples.enumerated() {
            if value != 0 {
                if silentRun > 1000 { result.append(index) }
                silentRun = 0
            } else {
                silentRun += 1
            }
        }
        return result
    }

    @Test func clicksLandOnExactBeatPositions() {
        let synth = MetronomeSynthesizer(sampleRate: 48000)
        synth.settings.set(MetronomeSettings(isEnabled: true, beatsPerMinute: 60, volume: 1))
        #expect(onsets(render(synth, count: 48000 * 3 + 10)) == [0, 48000, 96000, 144000])
    }

    @Test func fastTempoDoesNotDriftOverManyBeats() {
        let synth = MetronomeSynthesizer(sampleRate: 44100)
        synth.settings.set(MetronomeSettings(isEnabled: true, beatsPerMinute: 208, volume: 1))
        let samplesPerBeat = 44100.0 * 60 / 208
        let found = onsets(render(synth, count: Int(samplesPerBeat * 100) + 10))
        #expect(found.count == 101)
        for (beat, position) in found.enumerated() {
            #expect(abs(Double(position) - Double(beat) * samplesPerBeat) <= 1, "第 \(beat) 拍")
        }
    }

    @Test func tempoIsClampedTo40Through208() {
        #expect(MetronomeSettings(isEnabled: true, beatsPerMinute: 20, volume: 1).beatsPerMinute == 40)
        #expect(MetronomeSettings(isEnabled: true, beatsPerMinute: 300, volume: 1).beatsPerMinute == 208)
    }

    @Test func disabledMetronomeIsSilent() {
        let synth = MetronomeSynthesizer(sampleRate: 48000)
        #expect(render(synth, count: 48000).allSatisfy { $0 == 0 })
    }

    @Test func clickIsNotDetectedAsPitch() {
        // 節拍器聲漏進麥克風時，不應被當成音高
        let synth = MetronomeSynthesizer(sampleRate: 48000)
        synth.settings.set(MetronomeSettings(isEnabled: true, beatsPerMinute: 208, volume: 1))
        let samples = render(synth, count: 48000)
        let detector = MPMPitchDetector(configuration: PitchDetectorConfiguration(sampleRate: 48000))
        for start in stride(from: 0, to: samples.count - 2048, by: 512) {
            #expect(detector.detect(Array(samples[start..<(start + 2048)])) == nil, "offset \(start)")
        }
    }
}

struct DroneSynthesizerTests {
    private func render(_ synth: DroneSynthesizer, count: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: count)
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, frameCount: count) }
        return buffer
    }

    @Test func droneSoundsAtRequestedFrequency() throws {
        let synth = DroneSynthesizer(sampleRate: 48000)
        synth.settings.set(DroneSettings(isEnabled: true, frequency: 196, volume: 0.5))
        let samples = render(synth, count: 48000)
        let detector = MPMPitchDetector(configuration: PitchDetectorConfiguration(sampleRate: 48000))
        let estimate = try #require(detector.detect(Array(samples[24000..<26048])))
        #expect(abs(1200 * log2(estimate.frequency / 196)) < 0.1)
    }

    @Test func startsAndStopsWithFadeInsteadOfClick() {
        let synth = DroneSynthesizer(sampleRate: 48000)
        synth.settings.set(DroneSettings(isEnabled: true, frequency: 220, volume: 1))
        let start = render(synth, count: 48000)
        #expect(start.prefix(48).map(abs).max()! < 0.05)          // 前 1 ms 幾乎無聲
        #expect(start[20000..<21000].map(abs).max()! > 0.5)       // 淡入完成後達到音量

        synth.settings.set(DroneSettings(isEnabled: false, frequency: 220, volume: 1))
        let stop = render(synth, count: 4800)
        #expect(stop.prefix(48).map(abs).max()! > 0.3)            // 不會瞬間歸零
        #expect(stop.suffix(100).allSatisfy { $0 == 0 })          // 淡出後完全靜音
    }

    @Test func frequencyChangeKeepsPhaseContinuous() {
        let synth = DroneSynthesizer(sampleRate: 48000)
        synth.settings.set(DroneSettings(isEnabled: true, frequency: 220, volume: 1))
        let before = render(synth, count: 4800)
        synth.settings.set(DroneSettings(isEnabled: true, frequency: 330, volume: 1))
        let after = render(synth, count: 10)
        // 相鄰樣本最大可能差值約為 2π·f·A/fs；換頻時不應出現跳變
        #expect(abs(after[0] - before.last!) < 0.1)
    }
}

struct RealtimeParameterTests {
    @Test func readerSeesLatestValueAndKeepsLastWhenLockIsBusy() {
        let parameter = RealtimeParameter(1)
        #expect(parameter.readForRealtime() == 1)
        parameter.set(2)
        #expect(parameter.readForRealtime() == 2)
        let whileBusy = parameter.withLockHeldForTesting { parameter.readForRealtime() }
        #expect(whileBusy == 2)   // 拿不到鎖時沿用上次讀到的值，不阻塞
    }
}
