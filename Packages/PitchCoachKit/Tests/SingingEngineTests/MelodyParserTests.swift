import Testing
import MusicTheory
@testable import SingingEngine

struct MelodyParserTests {
    private func parse(_ text: String) throws(MelodyParseError) -> Melody {
        try MelodyParser.parse(text)
    }

    private func error(_ text: String) -> MelodyParseError? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return error
        }
    }

    @Test func parsesNoteNamesOctavesAndBeats() throws {
        let melody = try parse("C4:1 D4:1 E4:2")
        #expect(melody.notes == [MelodyNote(pitch: Note(midi: 60), beats: 1), MelodyNote(pitch: Note(midi: 62), beats: 1),
                                 MelodyNote(pitch: Note(midi: 64), beats: 2)])
    }

    @Test func acceptsSharpsFlatsUnicodeAccidentalsAndLowercase() throws {
        let melody = try parse("F#4:1 Bb4:0.5 C♯5:1 e♭4:1.5 g3:1")
        #expect(melody.notes.map { $0.pitch?.midi } == [66, 70, 73, 63, 55])
        #expect(melody.notes.map(\.beats) == [1, 0.5, 1, 1.5, 1])
    }

    @Test func acceptsRestsAndAnyWhitespace() throws {
        let melody = try parse("  C4:1\nR:1\t D4:2\n")
        #expect(melody.notes == [MelodyNote(pitch: Note(midi: 60), beats: 1), MelodyNote(pitch: nil, beats: 1),
                                 MelodyNote(pitch: Note(midi: 62), beats: 2)])
    }

    @Test func invalidNoteNameReportsIndexTokenAndReason() {
        let failure = error("C4:1 D4:1 H4:1 E4:1")
        #expect(failure == MelodyParseError(noteIndex: 3, token: "H4:1", reason: .invalidNoteName("H")))
        #expect(failure?.message == "第 3 個音符「H4:1」：無法辨識的音名「H」（請用 A–G，或 R 表示休止符）")
    }

    @Test func missingOrInvalidDurationIsReported() {
        #expect(error("C4 D4:1")?.reason == .missingDuration)
        #expect(error("C4 D4:1")?.noteIndex == 1)
        for token in ["C4:0", "C4:-1", "C4:abc", "C4:20", "C4:"] {
            #expect(error("C4:1 " + token)?.reason == .invalidDuration(String(token.dropFirst(3))), "\(token)")
            #expect(error("C4:1 " + token)?.noteIndex == 2)
        }
    }

    @Test func missingOrInvalidOctaveIsReported() {
        #expect(error("C:1")?.reason == .missingOctave)
        #expect(error("C#:1")?.reason == .missingOctave)
        #expect(error("D4:1 Cx:1")?.reason == .invalidOctave("x"))
        #expect(error("D4:1 Cx:1")?.noteIndex == 2)
    }

    @Test func notesOutsideSingableRangeAreRejected() {
        #expect(error("C4:1 C8:1")?.reason == .outOfRange)
        #expect(error("B1:1")?.reason == .outOfRange)
        #expect(error("C2:1 C7:1") == nil)
    }

    @Test func emptyInputIsAnError() {
        #expect(error("   \n ")?.reason == .empty)
        #expect(error("")?.message == "旋律是空的")
    }

    @Test func transposingShiftsEveryPitchAndKeepsRests() throws {
        let melody = try parse("C4:1 R:1 E4:2").transposed(by: -3)
        #expect(melody.notes.map { $0.pitch?.midi } == [57, nil, 61])
        #expect(melody.notes.map(\.beats) == [1, 1, 2])
    }
}
