import Foundation
import Testing
import MusicTheory
@testable import SingingEngine

struct SingingEvaluatorTests {
    private func evaluate(_ timeline: SongTimeline, _ frames: [SungFrame], options: SingingOptions = SingingOptions()) -> SingingResult {
        var evaluator = SingingEvaluator(timeline: timeline, reference: .default, options: options)
        frames.forEach { evaluator.process($0) }
        return evaluator.result()
    }

    @Test func notePitchIsMedianOfMiddleSeventyPercent() throws {
        let song = try timeline("A4:1")            // 60 BPM → 0–1 秒
        // 頭尾 15% 是 +80 cents 的雜音，中段 +10
        let frames = syntheticFrames(from: 0, to: 1, target: Note(midi: 69)) { t in t < 0.15 || t >= 0.85 ? 80 : 10 }
        let note = evaluate(song, frames).notes[0]
        #expect(abs(note.centsDeviation! - 10) < 1e-6)
        #expect(note.pitchVerdict == .accurate)
    }

    @Test func glideIntoFirstTwentyPercentStillCountsAsAccurate() throws {
        // AC-16：前 20% 從 −100 cents 線性滑到 0
        let song = try timeline("C4:1 E4:1")
        var frames = syntheticFrames(from: 0, to: 1, target: Note(midi: 60)) { t in t < 0.2 ? -100 + 500 * t : 0 }
        frames += syntheticFrames(from: 1, to: 2, target: Note(midi: 64)) { t in t - 1 < 0.2 ? -100 + 500 * (t - 1) : 0 }
        let result = evaluate(song, frames)
        #expect(result.notes.map(\.pitchVerdict) == [.accurate, .accurate])
        #expect(result.notes.allSatisfy { abs($0.centsDeviation!) < 1 })
    }

    @Test func toleranceOf25CentsDecidesAccurateSharpOrFlat() throws {
        let song = try timeline("A4:1 A4:1 A4:1 A4:1")
        var frames: [SungFrame] = []
        for (index, cents) in [25.0, -25.0, 25.1, -25.1].enumerated() {
            frames += syntheticFrames(from: Double(index), to: Double(index + 1), target: Note(midi: 69)) { _ in cents }
        }
        #expect(evaluate(song, frames).notes.map(\.pitchVerdict) == [.accurate, .accurate, .sharp, .flat])
    }

    @Test func noteWithoutAnyPitchIsNotSungAndShortMiddleFallsBackToWholeNote() throws {
        let song = try timeline("A4:1 A4:1")
        var frames = syntheticFrames(from: 0, to: 1, target: Note(midi: 69)) { _ in nil }
        // 第二個音只在頭 12% 有音高（中段沒有）：改用整個音符期間判定，而非「沒唱」
        frames += syntheticFrames(from: 1, to: 2, target: Note(midi: 69)) { t in t - 1 < 0.12 ? 5 : nil }
        let notes = evaluate(song, frames).notes
        #expect(notes[0].pitchVerdict == .notSung)
        #expect(notes[0].rhythmVerdict == .notSung)
        #expect(notes[1].pitchVerdict == .accurate)
    }

    @Test func octaveToleranceDecidesWhetherLowOctaveCounts() throws {
        // AC-17：整首唱低一個八度（偏差 −1200 + 8 cents）
        let song = try timeline("C5:1 D5:1 E5:1")
        var frames: [SungFrame] = []
        for (index, midi) in [72, 74, 76].enumerated() {
            frames += syntheticFrames(from: Double(index), to: Double(index + 1), target: Note(midi: midi)) { _ in -1192 }
        }
        let tolerant = evaluate(song, frames, options: SingingOptions(allowsOctaveShift: true))
        #expect(tolerant.notes.map(\.pitchVerdict) == [.accurate, .accurate, .accurate])
        #expect(tolerant.notes.allSatisfy { abs($0.centsDeviation! - 8) < 1e-6 })

        let strict = evaluate(song, frames)
        #expect(strict.notes.map(\.pitchVerdict) == [.flat, .flat, .flat])
        #expect(strict.notes.allSatisfy { abs($0.centsDeviation! + 1192) < 1e-6 })
    }

    @Test func transpositionMovesTargetsAndVerdicts() throws {
        // AC-21：學生唱原調 C4 E4；移調 +2 後目標變成 D4 F#4，原調的歌聲變成偏低
        let frames = syntheticFrames(from: 0, to: 1, target: Note(midi: 60)) { _ in 0 }
            + syntheticFrames(from: 1, to: 2, target: Note(midi: 64)) { _ in 0 }
        let original = evaluate(try timeline("C4:1 E4:1"), frames)
        let transposed = evaluate(try timeline("C4:1 E4:1", transposition: 2), frames)
        #expect(original.notes.map(\.pitchVerdict) == [.accurate, .accurate])
        #expect(transposed.notes.map(\.note.pitch.midi) == [62, 66])
        #expect(transposed.notes.map(\.pitchVerdict) == [.flat, .flat])
        #expect(transposed.notes.allSatisfy { abs($0.centsDeviation! + 200) < 1e-6 })
    }

    @Test func accuracyRatiosUseAllNotesAsDenominator() throws {
        let song = try timeline("C4:1 D4:1 E4:1 F4:1")
        var frames = syntheticFrames(from: 0, to: 1, target: Note(midi: 60)) { _ in 0 }   // 準、準時
        frames += syntheticFrames(from: 1, to: 2, target: Note(midi: 62)) { _ in 40 }     // 偏高、準時
        frames += syntheticFrames(from: 2, to: 3, target: Note(midi: 64)) { _ in nil }    // 沒唱
        frames += syntheticFrames(from: 3.2, to: 4, target: Note(midi: 65)) { _ in 0 }    // 準、延遲 200 ms
        let result = evaluate(song, frames)
        #expect(result.notes.map(\.rhythmVerdict) == [.onTime, .onTime, .notSung, .late])
        #expect(result.pitchAccuracy == 0.5)
        #expect(result.rhythmAccuracy == 0.5)
    }

    @Test func weakestRangeIsFiveSemitoneWindowWithHighestMissRate() throws {
        // C4 D4 E4 準；A4 B4 C5 偏高 → A4–C5（3 個音全不準）比 G4–B4（3 個中 2 個）更差
        let pitches = [60, 62, 64, 67, 69, 71, 72]
        let song = try timeline(pitches.map { Note(midi: $0).name() + ":1" }.joined(separator: " "))
        var frames: [SungFrame] = []
        for (index, midi) in pitches.enumerated() {
            frames += syntheticFrames(from: Double(index), to: Double(index + 1), target: Note(midi: midi)) { _ in midi >= 69 ? 40 : 0 }
        }
        let weakest = try #require(evaluate(song, frames).weakestRange)
        #expect(weakest.lowest.name() == "A4")
        #expect(weakest.highest.name() == "C5")
        #expect(weakest.missed == 3)
        #expect(weakest.total == 3)
    }
}
