import Foundation
import Testing
import MusicTheory
@testable import SingingEngine

struct SongTimelineTests {
    @Test func beatsBecomeSecondsAndRestsShiftLaterNotes() throws {
        // 120 BPM → 一拍 0.5 秒
        let melody = try MelodyParser.parse("C4:1 D4:0.5 R:1.5 E4:2")
        let timeline = try SongTimeline(melody: melody, beatsPerMinute: 120, reference: .default)
        #expect(timeline.notes.map(\.start) == [.zero, .milliseconds(500), .milliseconds(1500)])
        #expect(timeline.notes.map(\.end) == [.milliseconds(500), .milliseconds(750), .milliseconds(2500)])
        #expect(timeline.notes.map(\.melodyIndex) == [0, 1, 3])
        #expect(timeline.duration == .milliseconds(2500))
        #expect(timeline.countIn == .seconds(2))           // 預備拍 4 拍
    }

    @Test func transpositionChangesPitchButNotTiming() throws {
        let melody = try MelodyParser.parse("C4:1 G4:1")
        let original = try SongTimeline(melody: melody, beatsPerMinute: 90, reference: .default)
        let transposed = try SongTimeline(melody: melody, beatsPerMinute: 90, transposition: 5, reference: .default)
        #expect(transposed.notes.map(\.pitch.midi) == [65, 72])
        #expect(transposed.notes.map(\.start) == original.notes.map(\.start))
        #expect(transposed.notes.map(\.end) == original.notes.map(\.end))
    }

    @Test func invalidTranspositionOrRangeIsRejected() throws {
        let melody = try MelodyParser.parse("C4:1 C7:1")
        #expect(throws: SongTimelineError.transpositionOutOfRange(7)) {
            try SongTimeline(melody: melody, beatsPerMinute: 90, transposition: 7, reference: .default)
        }
        // C7 升 1 個半音 = C#7 ≈ 2,228 Hz，超出偵測範圍；回報第 2 個音符
        #expect(throws: SongTimelineError.outOfDetectionRange(noteIndex: 2)) {
            try SongTimeline(melody: melody, beatsPerMinute: 90, transposition: 1, reference: .default)
        }
    }
}
