import Foundation
import MusicTheory
import PitchDetection
import SignalKit
@testable import SingingEngine

let sampleRate = 48000.0

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
}

/// 測試用的時鐘：歌曲起點 = 串流起點，沒有延遲與校正。
let identityClock = SongClock(heardSongStartHostTime: 0, inputLatency: 0, calibrationOffset: 0,
                              windowDuration: 2048 / sampleRate, hopDuration: 512 / sampleRate)

/// 把樣本送進串流偵測，換算成歌曲時間的 SungFrame（完整處理鏈）。
func sungFrames(_ samples: [Float]) -> [SungFrame] {
    let analyzer = StreamingPitchAnalyzer(configuration: PitchDetectorConfiguration(sampleRate: sampleRate))
    var frames: [SungFrame] = []
    samples.withUnsafeBufferPointer { buffer in
        analyzer.process(buffer, startingAt: 0) { frame in
            frames.append(identityClock.sungFrame(frame, windowEndHostTime: seconds(frame.time)))
        }
    }
    return frames
}

/// 直接以 cents 建構的 SungFrame（每 10 ms 一個），用於判定規則的單元測試。
func syntheticFrames(from start: Double, to end: Double, step: Double = 0.01, target: Note,
                     reference: TuningReference = .default, cents: (Double) -> Double?) -> [SungFrame] {
    stride(from: start, to: end, by: step).map { t in
        let frequency = cents(t).map { NoteConverter.frequency(of: target, reference: reference) * pow(2, $0 / 1200) }
        let time = Duration.nanoseconds(Int64((t * 1e9).rounded()))   // 四捨五入，避免 1.92e9 截成 1919999999
        return SungFrame(time: time, frequency: frequency, levelDB: frequency == nil ? -80 : -20,
                         levelTime: time)
    }
}

func timeline(_ notation: String, bpm: Int = 60, transposition: Int = 0) throws -> SongTimeline {
    try SongTimeline(melody: MelodyParser.parse(notation), beatsPerMinute: bpm, transposition: transposition, reference: .default)
}
