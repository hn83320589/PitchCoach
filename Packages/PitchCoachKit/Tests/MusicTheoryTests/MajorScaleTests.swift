import Testing
@testable import MusicTheory

struct MajorScaleTests {
    private let ref442 = TuningReference.default

    @Test func allTwelveKeysFollowMajorScaleIntervals() throws {
        #expect(MajorKey.allCases.count == 12)
        for key in MajorKey.allCases {
            let scale = try MajorScale(key: key, startOctave: 4, direction: .ascending, reference: ref442)
            let intervals = zip(scale.steps.dropFirst(), scale.steps).map { $0.midi - $1.midi }
            #expect(intervals == [2, 2, 1, 2, 2, 2, 1], "\(key)")
            #expect(scale.steps[0].pitchClass == key.tonic)
        }
    }

    @Test func ascendingHasEightStepsAndRoundTripHasFifteen() throws {
        let up = try MajorScale(key: .c, startOctave: 4, direction: .ascending, reference: ref442)
        let round = try MajorScale(key: .c, startOctave: 4, direction: .ascendingDescending, reference: ref442)
        #expect(up.steps.count == 8)
        #expect(round.steps.count == 15)
        // 下行是上行去掉頂端主音後反轉
        #expect(Array(round.steps[8...]) == Array(up.steps.dropLast().reversed()))
    }

    @Test func noteNamesFollowKeySignature() throws {
        func names(_ key: MajorKey) throws -> [String] {
            let scale = try MajorScale(key: key, startOctave: 4, direction: .ascending, reference: ref442)
            return scale.steps.map { scale.displayName(of: $0) }
        }
        #expect(try names(.f) == ["F4", "G4", "A4", "B♭4", "C5", "D5", "E5", "F5"])
        #expect(try names(.fSharp) == ["F#4", "G#4", "A#4", "B4", "C#5", "D#5", "E#5", "F#5"])
        #expect(try names(.dFlat) == ["D♭4", "E♭4", "F4", "G♭4", "A♭4", "B♭4", "C5", "D♭5"])
    }

    @Test func availableStartOctavesStayWithinDetectionRange() {
        // A4 = 415 時 C2 ≈ 61.7 Hz，低於 65 Hz 不可選；A4 = 442 時 C2 ≈ 65.7 Hz 可選
        let ref415 = try! TuningReference(a4: 415)
        #expect(!MajorScale.availableStartOctaves(key: .c, reference: ref415).contains(2))
        #expect(MajorScale.availableStartOctaves(key: .c, reference: ref442).contains(2))

        // A4 = 442 時 C7 ≈ 2102.6 Hz 超過 2100 Hz，所以 C6 起的音階不可選；A4 = 440 時 C7 = 2093 Hz 可選
        let ref440 = try! TuningReference(a4: 440)
        #expect(!MajorScale.availableStartOctaves(key: .c, reference: ref442).contains(6))
        #expect(MajorScale.availableStartOctaves(key: .c, reference: ref440).contains(6))
    }

    @Test func initRejectsStartOctaveOutsideRange() {
        #expect(throws: ScaleError.outOfDetectionRange) {
            try MajorScale(key: .c, startOctave: 6, direction: .ascending, reference: ref442)
        }
    }
}
