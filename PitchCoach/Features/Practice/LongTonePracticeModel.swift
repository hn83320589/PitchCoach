import Foundation
import MusicTheory
import Observation
import PitchDetection
import PracticeEngine

/// 長音練習流程：設定 → 進行中 → 結果。判定交給 LongToneEvaluator，中斷規則交給 PracticeLifecycle。
@MainActor
@Observable
final class LongTonePracticeModel {
    enum Phase: Equatable {
        case setup
        case running
        case finished
    }

    var target = Note(midi: 69)
    private(set) var phase: Phase = .setup
    private(set) var progress: LongToneProgress = .waitingForSound
    private(set) var result: LongToneResult?
    private(set) var interruptionReason: PracticeInterruptionReason?
    private(set) var saveError: String?

    @ObservationIgnored private var evaluator: LongToneEvaluator?
    @ObservationIgnored private var lifecycle = PracticeLifecycle()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var reference = TuningReference.default
    @ObservationIgnored private let save: @MainActor (PracticeSessionRecord) throws -> Void

    init(save: @escaping @MainActor (PracticeSessionRecord) throws -> Void) {
        self.save = save
    }

    var duration: Duration { .seconds(10) }

    func start(reference: TuningReference) {
        self.reference = reference
        evaluator = LongToneEvaluator(target: target, reference: reference, duration: duration)
        lifecycle = PracticeLifecycle()
        lifecycle.handle(.start)
        startedAt = Date()
        progress = .waitingForSound
        result = nil
        interruptionReason = nil
        saveError = nil
        phase = .running
    }

    func process(_ frame: PitchFrame) {
        guard phase == .running, var evaluator else { return }
        progress = evaluator.process(frame)
        self.evaluator = evaluator
        if progress == .finished, lifecycle.handle(.complete) {
            finish(interruption: nil)
        }
    }

    func interrupt(_ reason: PracticeInterruptionReason) {
        guard lifecycle.handle(.interrupt(reason)) else { return }
        finish(interruption: reason)
    }

    /// 使用者放棄：不存檔。
    func cancel() {
        lifecycle.handle(.cancel)
        evaluator = nil
        phase = .setup
    }

    func reset() {
        phase = .setup
    }

    private func finish(interruption: PracticeInterruptionReason?) {
        guard let evaluator else { return }
        let result = evaluator.result()
        self.result = result
        interruptionReason = interruption
        phase = .finished
        // 還沒開始發聲就被中斷：沒有可保留的資料
        guard result.analyzedDuration > .zero || result.statFrameCount > 0 else { return }
        do {
            try save(PracticeSessionRecord(longTone: result, startedAt: startedAt, reference: reference, interruption: interruption))
        } catch {
            saveError = "練習紀錄儲存失敗：\(error.localizedDescription)"
        }
    }
}
