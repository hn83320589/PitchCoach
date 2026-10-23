import Foundation
import MusicTheory

/// 依路由的回授校正（docs/SINGING_MODE.md §7.2）。
///
/// 以目前的輸出路由播放 8 個短促的 A4 提示音，讓麥克風收音（喇叭直接收到；用耳機時把耳機貼近麥克風），
/// 起音偏移的中位數即為 iOS 回報的延遲之外、尚未補償的部分。
public enum LatencyCalibration {
    public static let noteCount = 8
    /// 至少要偵測到幾個提示音才採用（環境太吵或音量太小時不校正）。
    public static let minimumDetected = 5

    /// 90 BPM，每個 A4 半拍、間隔半拍休止。
    public static func timeline(reference: TuningReference) throws(SongTimelineError) -> SongTimeline {
        let notes = (0..<noteCount).flatMap { _ in [MelodyNote(pitch: Note(midi: 69), beats: 0.5), MelodyNote(pitch: nil, beats: 0.5)] }
        return try SongTimeline(melody: Melody(notes: notes), beatsPerMinute: 90, countInBeats: 2, reference: reference)
    }

    /// 校正值（秒）；偵測到的提示音不足時為 nil。
    public static func offset(from result: SingingResult) -> Double? {
        let offsets = result.notes.compactMap { $0.onsetOffset?.timeInterval }
        guard offsets.count >= minimumDetected else { return nil }
        return SingingEvaluator.median(offsets)
    }
}
