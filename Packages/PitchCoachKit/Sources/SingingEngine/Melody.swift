import MusicTheory

public struct MelodyNote: Equatable, Sendable {
    /// nil 表示休止符。
    public let pitch: Note?
    public let beats: Double

    public init(pitch: Note?, beats: Double) {
        self.pitch = pitch
        self.beats = beats
    }
}

public struct Melody: Equatable, Sendable {
    public let notes: [MelodyNote]

    public init(notes: [MelodyNote]) {
        self.notes = notes
    }

    /// 整首移調；休止符與拍數不變。
    public func transposed(by semitones: Int) -> Melody {
        Melody(notes: notes.map { MelodyNote(pitch: $0.pitch.map { Note(midi: $0.midi + semitones) }, beats: $0.beats) })
    }
}
