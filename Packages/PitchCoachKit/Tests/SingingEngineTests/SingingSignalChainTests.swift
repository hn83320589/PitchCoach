import Foundation
import Testing
import MusicTheory
import SignalKit
@testable import SingingEngine

/// 以人聲模擬訊號走完整條處理鏈（合成 → 串流偵測 → 歌曲時鐘 → 判定）。
struct SingingSignalChainTests {
    private func evaluate(_ timeline: SongTimeline, _ samples: [Float], options: SingingOptions = SingingOptions()) -> SingingResult {
        var evaluator = SingingEvaluator(timeline: timeline, reference: .default, options: options)
        sungFrames(samples).forEach { evaluator.process($0) }
        return evaluator.result()
    }

    /// AC-15：基頻＋泛音＋母音共振峰＋5.5 Hz ±60 cents 顫音。
    @Test(arguments: [(VoiceType.male, Vowel.a, 52), (.female, .i, 69), (.child, .u, 76)])
    func vibratoVoiceYieldsCenterRateAndDepth(_ voiceType: VoiceType, _ vowel: Vowel, _ midi: Int) throws {
        let note = Note(midi: midi)
        let center = NoteConverter.frequency(of: note, reference: .default)
        let voice = VoiceSynthesizer(voiceType: voiceType, vowel: vowel, sampleRate: sampleRate)
        let samples = voice.render(count: Int(sampleRate * 1.6)) { t in
            t >= 0.05 && t < 1.55 ? VoiceSynthesizer.vibrato(center: center, rate: 5.5, depthCents: 60, phase: 0.3)(t) : nil
        }
        let song = try SongTimeline(melody: Melody(notes: [MelodyNote(pitch: nil, beats: 0.05), MelodyNote(pitch: note, beats: 1.5)]),
                                    beatsPerMinute: 60, reference: .default)
        let result = evaluate(song, samples).notes[0]
        let vibrato = try #require(result.vibrato, "\(voiceType) /\(vowel)/ 應偵測到顫音")
        #expect(abs(result.centsDeviation!) < 5, "中心音高 \(result.centsDeviation!)")
        #expect(abs(vibrato.rate - 5.5) < 0.5, "速度 \(vibrato.rate)")
        #expect(abs(vibrato.depthCents - 60) < 10, "幅度 \(vibrato.depthCents)")
        #expect(result.pitchVerdict == .accurate)
    }

    /// AC-16：每個音符前 20% 從低 100 cents 滑上來。
    @Test func glidingVoiceIsStillAccurate() throws {
        let song = try timeline("G4:1 A4:1 B4:1 C5:1")
        let voice = VoiceSynthesizer(voiceType: .female, vowel: .a, sampleRate: sampleRate)
        let samples = voice.render(count: Int(sampleRate * 4)) { t in
            let index = min(3, Int(t))
            let target = NoteConverter.frequency(of: song.notes[index].pitch, reference: .default)
            let local = t - Double(index)
            return target * pow(2, (local < 0.2 ? -100 + 500 * local : 0) / 1200)
        }
        let result = evaluate(song, samples)
        #expect(result.notes.map(\.pitchVerdict) == [.accurate, .accurate, .accurate, .accurate])
    }

    /// AC-17：整首以人聲唱低一個八度。
    @Test func lowOctaveVoiceDependsOnOctaveTolerance() throws {
        let song = try timeline("C5:1 E5:1 G5:1")
        let voice = VoiceSynthesizer(voiceType: .male, vowel: .u, sampleRate: sampleRate)
        let samples = voice.render(count: Int(sampleRate * 3)) { t in
            NoteConverter.frequency(of: song.notes[min(2, Int(t))].pitch, reference: .default) / 2
        }
        #expect(evaluate(song, samples, options: SingingOptions(allowsOctaveShift: true)).notes.allSatisfy { $0.pitchVerdict == .accurate })
        #expect(evaluate(song, samples).notes.allSatisfy { $0.pitchVerdict == .flat })
    }
}
