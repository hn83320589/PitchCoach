import Foundation
import Testing
@testable import MusicTheory

struct NoteConverterTests {
    private let ref442 = TuningReference.default
    private let ref440 = try! TuningReference(a4: 440)

    // MARK: - 驗收標準 AC-07

    @Test func frequency442AtReference442IsA4WithZeroCents() {
        let reading = NoteConverter.reading(frequency: 442, reference: ref442)
        #expect(reading.note.name() == "A4")
        #expect(abs(reading.cents) < 1e-9)
    }

    @Test func frequency442AtReference440IsA4WithPlus7Point85Cents() {
        let reading = NoteConverter.reading(frequency: 442, reference: ref440)
        #expect(reading.note.name() == "A4")
        // 1200 · log2(442 / 440) = 7.851…
        #expect(abs(reading.cents - 7.851) < 0.001)
    }

    // MARK: - 音名與八度

    @Test func octaveChangesBetweenB3AndC4() {
        #expect(Note(midi: 59).name() == "B3")
        #expect(Note(midi: 60).name() == "C4")
        let middleC = NoteConverter.reading(frequency: 261.63, reference: ref440)
        #expect(middleC.note.name() == "C4")
    }

    @Test func sharpNamesCoverAllTwelvePitchClasses() {
        let names = (60...71).map { Note(midi: $0).name() }
        #expect(names == ["C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4"])
    }

    @Test func flatSpellingIsAvailable() {
        #expect(Note(midi: 70).name(spelling: .flats) == "B♭4")
        #expect(Note(midi: 61).name(spelling: .flats) == "D♭4")
        #expect(Note(midi: 60).name(spelling: .flats) == "C4")
    }

    @Test func detectionRangeEndpointsAreC2AndC7() {
        #expect(NoteConverter.reading(frequency: 65.41, reference: ref440).note.name() == "C2")
        #expect(NoteConverter.reading(frequency: 2093.0, reference: ref440).note.name() == "C7")
    }

    // MARK: - cents 邊界：區間定義為 [-50, 50)

    @Test func exactlyPlus50CentsBelongsToUpperNote() {
        let a4 = ref440.a4
        let plus50 = a4 * pow(2, 50.0 / 1200)
        let reading = NoteConverter.reading(frequency: plus50, reference: ref440)
        #expect(reading.note.name() == "A#4")
        #expect(abs(reading.cents + 50) < 1e-6)

        let plus49 = a4 * pow(2, 49.99 / 1200)
        let below = NoteConverter.reading(frequency: plus49, reference: ref440)
        #expect(below.note.name() == "A4")
        #expect(abs(below.cents - 49.99) < 1e-6)
    }

    @Test func centsRelativeToGivenNoteIsNotWrapped() {
        // 相對指定目標音，不換到最近的音：A4 = 442 時 500 Hz 相對 A4 約 +213.5 cents
        let cents = NoteConverter.cents(frequency: 500, relativeTo: Note(midi: 69), reference: ref442)
        #expect(abs(cents - 1200 * log2(500.0 / 442)) < 1e-9)
    }

    @Test func frequencyRoundTripsThroughReading() {
        for midi in 24...108 {
            let note = Note(midi: midi)
            let frequency = NoteConverter.frequency(of: note, reference: ref442)
            let reading = NoteConverter.reading(frequency: frequency, reference: ref442)
            #expect(reading.note == note)
            #expect(abs(reading.cents) < 1e-9)
        }
    }
}
