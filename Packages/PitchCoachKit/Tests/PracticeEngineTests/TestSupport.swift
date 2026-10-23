import Foundation
import MusicTheory
import PitchDetection

let a4 = Note(midi: 69)

/// 在 `ms` 毫秒產生一個 frame，音高為 `note` 偏 `cents`；`cents` 為 nil 表示無音高。
func frame(_ ms: Int, cents: Double?, note: Note = a4, reference: TuningReference = .default) -> PitchFrame {
    PitchFrame(time: .milliseconds(ms), estimate: cents.map {
        PitchEstimate(frequency: NoteConverter.frequency(of: note, reference: reference) * pow(2, $0 / 1200),
                      clarity: 0.99, levelDB: -20)
    })
}

/// 從 `start` 到 `end`（含）每 `step` 毫秒一個 frame。
func frames(from start: Int, through end: Int, step: Int = 1, cents: Double?, note: Note = a4) -> [PitchFrame] {
    stride(from: start, through: end, by: step).map { frame($0, cents: cents, note: note) }
}
