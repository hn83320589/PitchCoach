import Foundation
import MusicTheory
import Observation
import PitchDetection
import PracticeEngine

/// 音階練習流程：設定 → 進行中 → 結果。
@MainActor
@Observable
final class ScalePracticeModel {
    enum Phase: Equatable {
        case setup
        case running
        case finished
    }

    var key: MajorKey = .c
    var startOctave = 4
    var direction: ScaleDirection = .ascending

    private(set) var phase: Phase = .setup
    private(set) var scale: MajorScale?
    private(set) var currentStep = 0
    private(set) var currentCents: Double?
    private(set) var holdProgress = 0.0
    private(set) var reachedSteps: Set<Int> = []
    private(set) var result: ScaleResult?
    private(set) var interruptionReason: PracticeInterruptionReason?
    private(set) var saveError: String?
    private(set) var setupError: String?

    @ObservationIgnored private var evaluator: ScaleEvaluator?
    @ObservationIgnored private var lifecycle = PracticeLifecycle()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var firstFrameTime: Duration?
    @ObservationIgnored private var lastFrameTime: Duration?
    @ObservationIgnored private var reference = TuningReference.default
    /// 由畫面在出現時注入（需要 Environment 的 modelContext，init 時還拿不到）。
    @ObservationIgnored var save: (@MainActor (PracticeSessionRecord) throws -> Void)?

    func availableOctaves(reference: TuningReference) -> [Int] {
        MajorScale.availableStartOctaves(key: key, reference: reference)
    }

    func start(reference: TuningReference) {
        let scale: MajorScale
        do {
            scale = try MajorScale(key: key, startOctave: startOctave, direction: direction, reference: reference)
        } catch {
            setupError = "這個調在第 \(startOctave) 八度超出偵測範圍（65–2,100 Hz），請換一個八度。"
            return
        }
        self.reference = reference
        self.scale = scale
        evaluator = ScaleEvaluator(scale: scale, reference: reference)
        lifecycle = PracticeLifecycle()
        lifecycle.handle(.start)
        startedAt = Date()
        firstFrameTime = nil
        lastFrameTime = nil
        currentStep = 0
        currentCents = nil
        holdProgress = 0
        reachedSteps = []
        result = nil
        interruptionReason = nil
        saveError = nil
        setupError = nil
        phase = .running
    }

    func process(_ frame: PitchFrame) {
        guard phase == .running, var evaluator else { return }
        if firstFrameTime == nil { firstFrameTime = frame.time }
        lastFrameTime = frame.time
        let event = evaluator.process(frame)
        self.evaluator = evaluator
        switch event {
        case .listening(let step, let cents, let progress):
            currentStep = step
            currentCents = cents
            holdProgress = progress
        case .advanced(let from, let to):
            reachedSteps.insert(from)
            currentStep = to
            currentCents = nil
            holdProgress = 0
        case .finished:
            reachedSteps.insert(currentStep)
            if lifecycle.handle(.complete) { finish(interruption: nil) }
        }
    }

    func skipCurrentStep() {
        guard phase == .running, var evaluator else { return }
        evaluator.skipCurrentStep()
        self.evaluator = evaluator
        if evaluator.isFinished {
            if lifecycle.handle(.complete) { finish(interruption: nil) }
        } else {
            currentStep = evaluator.currentStepIndex
            currentCents = nil
            holdProgress = 0
        }
    }

    func interrupt(_ reason: PracticeInterruptionReason) {
        guard lifecycle.handle(.interrupt(reason)) else { return }
        finish(interruption: reason)
    }

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
        guard let firstFrameTime, let lastFrameTime else { return }   // 沒收到任何 frame：沒有可保留的資料
        let activeDuration = (lastFrameTime - firstFrameTime).seconds
        guard let save else {
            saveError = "練習紀錄儲存失敗：尚未設定儲存位置。"
            return
        }
        do {
            try save(PracticeSessionRecord(scale: result, startedAt: startedAt, activeDuration: activeDuration,
                                           reference: reference, interruption: interruption))
        } catch {
            saveError = "練習紀錄儲存失敗：\(error.localizedDescription)"
        }
    }
}
