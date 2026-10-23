import Foundation
import MusicTheory

/// 樂譜上的一個音符（休止符不列入）。
public struct ScoredNote: Equatable, Sendable {
    /// 在旋律中的索引（從 0 起算，含休止符），用來對應使用者輸入的第幾個音符。
    public let melodyIndex: Int
    public let pitch: Note
    /// 相對歌曲起點（預備拍之後的第一拍）的時間。
    public let start: Duration
    public let end: Duration

    public var duration: Duration { end - start }
}

public enum SongTimelineError: Error, Equatable, Sendable {
    case transpositionOutOfRange(Int)
    /// 移調後超出偵測範圍；noteIndex 從 1 起算（與 MelodyParseError 一致）。
    case outOfDetectionRange(noteIndex: Int)
}

/// 把旋律的拍數換算成時間，並套用移調。
public struct SongTimeline: Equatable, Sendable {
    public static let transpositionRange = -6...6

    public let notes: [ScoredNote]
    public let beatsPerMinute: Int
    public let transposition: Int
    /// 歌曲本身的長度（不含預備拍）。
    public let duration: Duration
    /// 預備拍長度；歌曲時間 0 之前播放。
    public let countIn: Duration
    public let beatDuration: Duration

    public init(melody: Melody, beatsPerMinute: Int, countInBeats: Int = 4, transposition: Int = 0,
                reference: TuningReference) throws(SongTimelineError) {
        guard Self.transpositionRange.contains(transposition) else {
            throw .transpositionOutOfRange(transposition)
        }
        let secondsPerBeat = 60 / Double(beatsPerMinute)
        func time(_ beats: Double) -> Duration {
            .nanoseconds(Int64((beats * secondsPerBeat * 1e9).rounded()))
        }

        var scored: [ScoredNote] = []
        var position = 0.0
        for (index, note) in melody.transposed(by: transposition).notes.enumerated() {
            if let pitch = note.pitch {
                guard PitchRange.detectable.contains(NoteConverter.frequency(of: pitch, reference: reference)) else {
                    throw .outOfDetectionRange(noteIndex: index + 1)
                }
                // 以累計拍數換算起訖時間，避免逐音累加的捨入誤差
                scored.append(ScoredNote(melodyIndex: index, pitch: pitch, start: time(position), end: time(position + note.beats)))
            }
            position += note.beats
        }
        notes = scored
        self.beatsPerMinute = beatsPerMinute
        self.transposition = transposition
        duration = time(position)
        countIn = time(Double(countInBeats))
        beatDuration = time(1)
    }
}
