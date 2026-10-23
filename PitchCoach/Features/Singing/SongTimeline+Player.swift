import Accompaniment
import MusicTheory
import SingingEngine

extension SongTimeline {
    /// 轉成 SongPlayer 的樂譜（秒與 Hz）。時間軸已套用移調。
    func playerScore(reference: TuningReference) -> SongPlayerScore {
        SongPlayerScore(
            notes: notes.map {
                SongPlayerScore.Note(start: $0.start.seconds, end: $0.end.seconds,
                                     frequency: NoteConverter.frequency(of: $0.pitch, reference: reference))
            },
            beatDuration: beatDuration.seconds,
            countInBeats: Int((countIn.seconds / beatDuration.seconds).rounded()),
            duration: duration.seconds)
    }
}
