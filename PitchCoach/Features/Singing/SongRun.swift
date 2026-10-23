import Accompaniment
import Foundation
import MusicTheory
import Observation
import PitchDetection
import QuartzCore
import SingingEngine

/// KTV 音高條上的一個點：歌曲時間（秒）與顯示用的音高（MIDI 小數；容許八度時已折算到目標的八度）。
struct LivePitchPoint: Sendable {
    let time: Double
    let midi: Double
    /// 相對當下目標音的偏差；沒有目標音（休止或歌曲外）時為 nil。
    let cents: Double?
}

/// 一次演唱（或延遲校正）的執行：播放伴奏 → 等歌曲起點回報 → 以 SongClock 換算歌曲時間 →
/// 收集 frame → 歌曲結束時判定。
@MainActor
@Observable
final class SongRun {
    enum Phase: Equatable {
        case countIn
        case singing
        case finished
    }

    let timeline: SongTimeline
    let reference: TuningReference
    let options: SingingOptions
    private(set) var phase: Phase = .countIn
    private(set) var result: SingingResult?
    /// KTV 音高條每幀重繪時讀取，不需觸發 Observation。
    @ObservationIgnored private(set) var livePoints: [LivePitchPoint] = []
    @ObservationIgnored private(set) var clock: SongClock?
    @ObservationIgnored private var evaluator: SingingEvaluator
    @ObservationIgnored private let pipeline: AudioPipeline
    @ObservationIgnored private let calibrationOffset: Double
    @ObservationIgnored private var subscriptions: [UUID] = []
    @ObservationIgnored var onFinished: (@MainActor (SingingResult) -> Void)?

    init(timeline: SongTimeline, reference: TuningReference, options: SingingOptions, pipeline: AudioPipeline,
         calibrationOffset: Double) {
        self.timeline = timeline
        self.reference = reference
        self.options = options
        self.pipeline = pipeline
        self.calibrationOffset = calibrationOffset
        evaluator = SingingEvaluator(timeline: timeline, reference: reference, options: options)
    }

    func start() {
        subscriptions = [
            pipeline.addSongEventHandler { [weak self] report in self?.handle(report) },
            pipeline.addTimedFrameHandler { [weak self] frame, hostTime in self?.process(frame, hostTime: hostTime) },
        ]
        pipeline.playSong(timeline.playerScore(reference: reference))
    }

    /// 目前的歌曲時間（秒）；預備拍期間為 nil。
    var currentSongTime: Double? {
        clock.map { CACurrentMediaTime() - $0.heardSongStartHostTime - $0.calibrationOffset }
    }

    /// 中斷：停止伴奏，回傳已結束音符的判定。
    func interrupt() -> SingingResult {
        let time = currentSongTime.map { Duration.nanoseconds(Int64($0 * 1e9)) } ?? .zero
        stop()
        phase = .finished
        let partial = evaluator.result(through: time)
        result = partial
        return partial
    }

    func stop() {
        pipeline.stopSong()
        subscriptions.forEach {
            pipeline.removeSongEventHandler($0)
            pipeline.removeFrameHandler($0)
        }
        subscriptions = []
    }

    private func handle(_ report: SongPlayer.Report) {
        switch report.event {
        case .songStarted:
            let sampleRate = pipeline.sampleRate ?? 48000
            // 學生聽到歌曲起點 = render 時間 ＋ iOS 回報的輸出延遲（藍牙約 150–250 ms）
            clock = SongClock(heardSongStartHostTime: report.hostTime + pipeline.outputLatency,
                              inputLatency: pipeline.inputLatency, calibrationOffset: calibrationOffset,
                              windowDuration: 2048 / sampleRate, hopDuration: 512 / sampleRate)
            phase = .singing
        case .finished:
            guard phase != .finished else { return }
            stop()
            phase = .finished
            let final = evaluator.result()
            result = final
            onFinished?(final)
        }
    }

    private func process(_ frame: PitchFrame, hostTime: Double) {
        guard phase == .singing, let clock else { return }
        let sung = clock.sungFrame(frame, windowEndHostTime: hostTime)
        evaluator.process(sung)
        guard let frequency = sung.frequency else { return }
        let time = sung.time.seconds
        let target = timeline.notes.first { $0.start.seconds <= time && time < $0.end.seconds }
        var midi = Double(Note.a4Midi) + 12 * log2(frequency / reference.a4)
        let cents = target.map { evaluator.cents(for: frequency, target: $0.pitch) }
        if let target, let cents, options.allowsOctaveShift {
            midi = Double(target.pitch.midi) + cents / 100
        }
        livePoints.append(LivePitchPoint(time: time, midi: midi, cents: cents))
    }
}
