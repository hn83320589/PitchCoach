import Foundation
import MusicTheory
import Observation
import PracticeEngine
import SingingEngine

/// 歌唱練習流程：選歌與設定 → 演唱（預備拍、KTV 音高條）→ 結果與存檔。
@MainActor
@Observable
final class SingingSessionModel {
    enum Phase: Equatable {
        case setup
        case running
        case finished
    }

    static let customSongID = "custom"

    var songID = Songbook.songs[0].id {
        didSet { if songID != oldValue, let song = selectedSong { beatsPerMinute = song.beatsPerMinute } }
    }
    var customNotation = "C4:1 D4:1 E4:1 F4:1 G4:2 E4:2"
    var beatsPerMinute = Songbook.songs[0].beatsPerMinute
    var transposition = 0
    var allowsOctaveShift = false

    private(set) var phase: Phase = .setup
    private(set) var run: SongRun?
    private(set) var result: SingingResult?
    private(set) var interruptionReason: PracticeInterruptionReason?
    private(set) var saveError: String?

    @ObservationIgnored private var lifecycle = PracticeLifecycle()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored var save: (@MainActor (PracticeSessionRecord) throws -> Void)?

    var selectedSong: Song? { Songbook.songs.first { $0.id == songID } }
    var title: String { selectedSong?.title ?? "自訂旋律" }

    enum TimelineState {
        case valid(SongTimeline)
        /// 給使用者看的錯誤訊息（自訂旋律格式錯誤時含第幾個音符）。
        case invalid(String)

        var timeline: SongTimeline? {
            if case .valid(let timeline) = self { return timeline }
            return nil
        }
    }

    /// 目前設定下的旋律；格式錯誤時為 MelodyParseError（含第幾個音符與原因）。
    var melody: Result<Melody, MelodyParseError> {
        Result { () throws(MelodyParseError) -> Melody in
            if let song = selectedSong { return try song.melody() }
            return try MelodyParser.parse(customNotation)
        }
    }

    /// 套用 BPM 與移調後的時間軸。
    func timeline(reference: TuningReference) -> TimelineState {
        let melody: Melody
        switch self.melody {
        case .failure(let error): return .invalid(error.message)
        case .success(let value): melody = value
        }
        do throws(SongTimelineError) {
            return .valid(try SongTimeline(melody: melody, beatsPerMinute: beatsPerMinute, transposition: transposition,
                                           reference: reference))
        } catch {
            switch error {
            case .transpositionOutOfRange(let value): return .invalid("移調 \(value) 超出 ±6 個半音")
            case .outOfDetectionRange(let index): return .invalid("移調後第 \(index) 個音符超出可偵測的音域")
            }
        }
    }

    func start(reference: TuningReference, pipeline: AudioPipeline, calibrationOffset: Double) {
        guard let timeline = timeline(reference: reference).timeline else { return }
        let options = SingingOptions(allowsOctaveShift: allowsOctaveShift)
        let run = SongRun(timeline: timeline, reference: reference, options: options, pipeline: pipeline,
                          calibrationOffset: calibrationOffset)
        run.onFinished = { [weak self] result in
            guard let self, self.lifecycle.handle(.complete) else { return }
            self.finish(result, reference: reference, interruption: nil)
        }
        lifecycle = PracticeLifecycle()
        lifecycle.handle(.start)
        startedAt = Date()
        result = nil
        interruptionReason = nil
        saveError = nil
        self.run = run
        phase = .running
        run.start()
    }

    func interrupt(_ reason: PracticeInterruptionReason, reference: TuningReference) {
        guard let run, lifecycle.handle(.interrupt(reason)) else { return }
        finish(run.interrupt(), reference: reference, interruption: reason)
    }

    func cancel() {
        lifecycle.handle(.cancel)
        run?.stop()
        run = nil
        phase = .setup
    }

    func reset() {
        run = nil
        phase = .setup
    }

    private func finish(_ result: SingingResult, reference: TuningReference, interruption: PracticeInterruptionReason?) {
        self.result = result
        interruptionReason = interruption
        phase = .finished
        guard !result.notes.isEmpty else { return }   // 還沒唱到任何音符就中斷：沒有可保留的資料
        guard let save else {
            saveError = "練習紀錄儲存失敗：尚未設定儲存位置。"
            return
        }
        let duration = Date().timeIntervalSince(startedAt)
        do {
            try save(PracticeSessionRecord(singing: result, title: title, transposition: transposition, startedAt: startedAt,
                                           activeDuration: duration, reference: reference, interruption: interruption))
        } catch {
            saveError = "練習紀錄儲存失敗：\(error.localizedDescription)"
        }
    }
}
