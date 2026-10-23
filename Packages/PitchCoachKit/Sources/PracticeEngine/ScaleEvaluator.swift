import Foundation
import MusicTheory
import PitchDetection

public enum ScaleEvent: Equatable, Sendable {
    /// `holdProgress` 為目前持續時間占到位所需時間的比例（0–1）。
    case listening(step: Int, cents: Double?, holdProgress: Double)
    case advanced(from: Int, to: Int)
    case finished
}

public struct ScaleStepResult: Equatable, Sendable {
    public let note: Note
    /// 依調號拼寫的音名，例如 "B♭4"。
    public let displayName: String
    public let meanCents: Double?
    public let frameCount: Int
    public let reached: Bool
    public let timeToReach: Duration?
}

public struct ScaleResult: Equatable, Sendable {
    public let scale: MajorScale
    public let steps: [ScaleStepResult]
    public let isComplete: Bool
    /// 偏差最大的 3 個音（同一音高在上下行出現時以 frame 數加權合併）。
    public let worstNotes: [NoteDeviation]

    public var reachedCount: Int { steps.filter(\.reached).count }
}

/// 音階練習判定（docs/ARCHITECTURE.md §7.2）。
///
/// 1. 在範圍內 = 有音高且相對目標音 |c| ≤ tolerance（含邊界）
/// 2. 持續從第一個在範圍內的 frame（t₀）開始，在範圍內的 frame 滿足 t − t₀ ≥ holdDuration 時到位
/// 3. 範圍外（含無音高）的空檔：目前 frame 距上一個在範圍內的 frame ≤ gapTolerance 時不重設，超過才重設
/// 4. 只在「在範圍內」的 frame 上到位
public struct ScaleEvaluator: Sendable {
    public let scale: MajorScale
    public let reference: TuningReference
    public let tolerance: Double
    public let holdDuration: Duration
    public let gapTolerance: Duration
    /// 偏差超過此值的 frame 視為還沒開始演奏這個音（例如從上一音滑過來），不計入平均。
    public let attemptThreshold: Double

    public private(set) var currentStepIndex = 0
    public var isFinished: Bool { currentStepIndex >= scale.steps.count }

    private var holdStart: Duration?
    private var lastInTolerance: Duration?
    private var stepStart: Duration?
    private var stepStatistics: [RunningStatistics]
    private var reached: [Bool]
    private var timeToReach: [Duration?]

    public init(scale: MajorScale, reference: TuningReference, tolerance: Double = 15,
                holdDuration: Duration = .milliseconds(300), gapTolerance: Duration = .milliseconds(50),
                attemptThreshold: Double = 50) {
        self.scale = scale
        self.reference = reference
        self.tolerance = tolerance
        self.holdDuration = holdDuration
        self.gapTolerance = gapTolerance
        self.attemptThreshold = attemptThreshold
        stepStatistics = Array(repeating: RunningStatistics(), count: scale.steps.count)
        reached = Array(repeating: false, count: scale.steps.count)
        timeToReach = Array(repeating: nil, count: scale.steps.count)
    }

    public mutating func process(_ frame: PitchFrame) -> ScaleEvent {
        guard !isFinished else { return .finished }
        let index = currentStepIndex
        if stepStart == nil { stepStart = frame.time }

        let cents = frame.frequency.map {
            NoteConverter.cents(frequency: $0, relativeTo: scale.steps[index], reference: reference)
        }
        if let cents, abs(cents) <= attemptThreshold + boundaryEpsilon {
            stepStatistics[index].add(cents)
        }

        let inTolerance = cents.map { abs($0) <= tolerance + boundaryEpsilon } ?? false
        // 空檔只在範圍外的 frame 上量測（StreamingPitchAnalyzer 每個 hop 都會輸出 frame，無音高時亦然）
        if inTolerance {
            if holdStart == nil { holdStart = frame.time }
            lastInTolerance = frame.time
            if frame.time - holdStart! >= holdDuration {
                reached[index] = true
                timeToReach[index] = frame.time - stepStart!
                moveToNextStep()
                return isFinished ? .finished : .advanced(from: index, to: index + 1)
            }
        } else if let last = lastInTolerance, frame.time - last > gapTolerance {
            holdStart = nil
            lastInTolerance = nil
        }

        let progress = holdStart.map { min(1, (frame.time - $0) / holdDuration) } ?? 0
        return .listening(step: index, cents: cents, holdProgress: progress)
    }

    /// 卡住時跳過目前的音：標記為未到位，已收集的 frame 仍計入統計。
    public mutating func skipCurrentStep() {
        guard !isFinished else { return }
        moveToNextStep()
    }

    public func result() -> ScaleResult {
        let steps = scale.steps.indices.map { index in
            ScaleStepResult(note: scale.steps[index], displayName: scale.displayName(of: scale.steps[index]),
                            meanCents: stepStatistics[index].meanIfAny, frameCount: stepStatistics[index].count,
                            reached: reached[index], timeToReach: timeToReach[index])
        }
        return ScaleResult(scale: scale, steps: steps, isComplete: isFinished, worstNotes: Self.worstNotes(in: steps))
    }

    private mutating func moveToNextStep() {
        currentStepIndex += 1
        holdStart = nil
        lastInTolerance = nil
        stepStart = nil
    }

    private static func worstNotes(in steps: [ScaleStepResult]) -> [NoteDeviation] {
        var weightedSums: [Note: (sum: Double, frames: Int)] = [:]
        for step in steps where step.frameCount > 0 {
            let mean = step.meanCents!
            let current = weightedSums[step.note] ?? (0, 0)
            weightedSums[step.note] = (current.sum + mean * Double(step.frameCount), current.frames + step.frameCount)
        }
        return weightedSums
            .map { NoteDeviation(note: $0.key, meanCents: $0.value.sum / Double($0.value.frames), frameCount: $0.value.frames, sessionCount: 1) }
            .sorted { abs($0.meanCents) != abs($1.meanCents) ? abs($0.meanCents) > abs($1.meanCents) : $0.note < $1.note }
            .prefix(3)
            .map { $0 }
    }
}
