import Foundation
import Testing
import MusicTheory
import PitchDetection
import SignalKit
@testable import SingingEngine

struct OnsetDetectorTests {
    private func evaluate(_ timeline: SongTimeline, _ frames: [SungFrame]) -> SingingResult {
        var evaluator = SingingEvaluator(timeline: timeline, reference: .default, options: SingingOptions())
        frames.forEach { evaluator.process($0) }
        return evaluator.result()
    }

    /// AC-18：合成演唱訊號，每個音符的實際起音時間已知（有的提早、有的延遲），
    /// 涵蓋換氣後起音、連唱換音、同音重複的重新咬字三種情況。
    @Test func synthesizedSingingOnsetsAreLocatedWithinThirtyMilliseconds() throws {
        let song = try timeline("C4:1 C4:1 G4:1 G4:1 A4:1 A4:1 G4:2", bpm: 100)   // 〈小星星〉開頭，一拍 0.6 秒
        // 實際起音相對樂譜的偏移（秒）
        let offsets = [0.0, 0.05, -0.04, 0.12, 0.0, -0.09, 0.03]
        let onsets = zip(song.notes, offsets).map { seconds($0.start) + $1 + 0.5 }   // 歌曲從 0.5 秒開始
        let pitches = song.notes.map { NoteConverter.frequency(of: $0.pitch, reference: .default) }
        let voice = VoiceSynthesizer(voiceType: .child, vowel: .a, sampleRate: sampleRate)
        let end = onsets.last! + 1.0
        let samples = voice.render(count: Int(sampleRate * (end + 0.3)), pitch: { t in
            guard t >= onsets[0], t < end else { return nil }
            // 第 3 個音（index 2）前換氣 80 ms：形成「發聲起點」
            if t < onsets[2], t > onsets[2] - 0.08 { return nil }
            return pitches[onsets.lastIndex { $0 <= t }!]
        }, loudness: { t in
            // 同音重複（index 1、3、5）：起音前 50 ms 音量降到 15%，模擬重新咬字
            for index in [1, 3, 5] where t < onsets[index] && t > onsets[index] - 0.05 { return 0.15 }
            return 1
        })
        // 歌曲時間 = 樣本時間 − 0.5 秒
        let frames = sungFrames(samples).map {
            SungFrame(time: $0.time - .milliseconds(500), frequency: $0.frequency, levelDB: $0.levelDB, levelTime: $0.levelTime - .milliseconds(500))
        }
        let result = evaluate(song, frames)
        for (index, note) in result.notes.enumerated() {
            let detected = try #require(note.onsetOffset, "第 \(index + 1) 個音沒有偵測到起音")
            #expect(abs(seconds(detected) - offsets[index]) < 0.03,
                    "第 \(index + 1) 個音：實際 \(offsets[index] * 1000) ms，偵測 \(seconds(detected) * 1000) ms")
        }
    }

    @Test func eightyMillisecondBoundaryDecidesOnTimeEarlyOrLate() throws {
        let song = try timeline("A4:1 R:1 A4:1 R:1 A4:1 R:1 A4:1")
        var frames: [SungFrame] = []
        for (index, offset) in [0.08, -0.08, 0.09, -0.09].enumerated() {
            let start = Double(index * 2)
            frames += syntheticFrames(from: start - 0.3, to: start + offset, target: Note(midi: 69)) { _ in nil }
            frames += syntheticFrames(from: start + offset, to: start + 0.9, target: Note(midi: 69)) { _ in 0 }
        }
        frames.sort { $0.time < $1.time }
        #expect(evaluate(song, frames).notes.map(\.rhythmVerdict) == [.onTime, .onTime, .late, .early])
    }

    @Test func legatoPitchChangeIsDetectedAtPitchCrossing() throws {
        // 連唱 C4 → E4，沒有換氣，換音晚了 60 ms
        let song = try timeline("C4:1 E4:1")
        let frames = syntheticFrames(from: 0, to: 1.06, target: Note(midi: 60)) { _ in 0 }
            + syntheticFrames(from: 1.06, to: 2, target: Note(midi: 64)) { _ in 0 }
        let note = evaluate(song, frames).notes[1]
        #expect(abs(seconds(note.onsetOffset!) - 0.06) < 0.011)
        #expect(note.rhythmVerdict == .onTime)
    }

    /// 同音連唱卻沒有重新咬字（小朋友常把〈小星星〉的「C C」唱成一個長音）：三種起音線索都不存在，
    /// 量不到起音時間，不能退回「搜尋窗內第一個接近目標的 frame」（那屬於前一個音，會得到假的「提早」）。
    @Test func repeatedNoteSungAsOneSustainedToneIsNotSeparated() throws {
        let song = try timeline("C4:1 C4:1 G4:1 G4:1", bpm: 100)   // 一拍 0.6 秒
        let starts = song.notes.map { seconds($0.start) + 0.5 }      // 歌曲從 0.5 秒開始
        let pitches = song.notes.map { NoteConverter.frequency(of: $0.pitch, reference: .default) }
        let voice = VoiceSynthesizer(voiceType: .child, vowel: .a, sampleRate: sampleRate)
        let end = starts.last! + 0.6
        // 每組同音之間音量與音高都不變，只有 C4 → G4 換音
        let samples = voice.render(count: Int(sampleRate * (end + 0.3))) { t in
            guard t >= starts[0], t < end else { return nil }
            return pitches[starts.lastIndex { $0 <= t }!]
        }
        let frames = sungFrames(samples).map {
            SungFrame(time: $0.time - .milliseconds(500), frequency: $0.frequency, levelDB: $0.levelDB, levelTime: $0.levelTime - .milliseconds(500))
        }
        let result = evaluate(song, frames)
        #expect(result.notes.map(\.rhythmVerdict) == [.onTime, .notSeparated, .onTime, .notSeparated])
        #expect(result.notes[1].onsetOffset == nil && result.notes[3].onsetOffset == nil)
        // 量不到起音的音不計入節奏正確率；音準照常判定
        #expect(result.rhythmAccuracy == 1)
        #expect(result.notes.allSatisfy { $0.pitchVerdict == .accurate })
    }

    @Test func fastRepeatedNotesWithoutRearticulationAreNotCountedOnTime() throws {
        // 200 BPM 的十六分音符：每音 75 ms，搜尋半寬只有 37.5 ms，退回規則會落在 ±80 ms 內而被誤判「準時」
        let song = try timeline("C4:0.25 C4:0.25 C4:0.25 C4:0.25", bpm: 200)
        let frames = syntheticFrames(from: -0.2, to: 0, target: Note(midi: 60)) { _ in nil }
            + syntheticFrames(from: 0, to: 0.4, target: Note(midi: 60)) { _ in 0 }
        let verdicts = evaluate(song, frames).notes.map(\.rhythmVerdict)
        #expect(verdicts == [.onTime, .notSeparated, .notSeparated, .notSeparated])
    }

    @Test func songClockUsesWindowCenterAndRemovesLatencies() {
        let clock = SongClock(heardSongStartHostTime: 100, inputLatency: 0.005, calibrationOffset: 0.02,
                              windowDuration: 0.04, hopDuration: 0.01)
        let frame = clock.sungFrame(PitchFrame(time: .seconds(3), estimate: nil, levelDB: -30), windowEndHostTime: 101.5)
        // 窗中心 101.48 − 輸入延遲 0.005 − 聽到起點 100 − 校正 0.02 = 1.455
        #expect(abs(seconds(frame.time) - 1.455) < 1e-9)
        // 電平屬於最後一個 hop：中心為窗尾 − 0.005
        #expect(abs(seconds(frame.levelTime) - 1.47) < 1e-9)
        #expect(frame.levelDB == -30)
    }
}
