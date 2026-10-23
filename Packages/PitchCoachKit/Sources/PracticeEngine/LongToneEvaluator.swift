import Foundation
import MusicTheory
import PitchDetection

public enum LongToneProgress: Equatable, Sendable {
    case waitingForSound
    /// `cents` 為相對目標音的偏差，無音高時為 nil。
    case running(elapsed: Duration, cents: Double?)
    case finished
}

public struct LongToneResult: Equatable, Sendable {
    public static let curveInterval: Duration = .milliseconds(50)

    public let target: Note
    /// ±tolerance 以內的 frame 比例，分母為全部 frame（含無音高與錯音）。
    public let inToleranceRatio: Double
    /// 有音高的 frame 比例。
    public let voicedRatio: Double
    /// 只用有音高且 |c| ≤ 錯音門檻的 frame。
    public let meanCents: Double?
    /// 母體標準差（穩定度）。
    public let standardDeviationCents: Double?
    public let statFrameCount: Int
    public let analyzedDuration: Duration
    /// 每 50 ms 一點的平均偏差；該區間沒有可用 frame 時為 nil。
    public let curve: [Double?]
    public let isComplete: Bool
}

/// 長音練習判定（docs/ARCHITECTURE.md §7.1）。
///
/// 從第一個有音高的 frame 開始計時 `duration`；偏差一律相對目標音（不換算到最近的音）。
public struct LongToneEvaluator: Sendable {
    public let target: Note
    public let reference: TuningReference
    public let duration: Duration
    public let tolerance: Double
    /// 偏差超過此值視為吹／拉成別的音，不計入平均、標準差與曲線。
    public let wrongNoteThreshold: Double

    private var startTime: Duration?
    private var lastTime: Duration?
    private var isFinished = false
    private var frameCount = 0
    private var inToleranceCount = 0
    private var voicedCount = 0
    private var statistics = RunningStatistics()
    private var curveBins: [RunningStatistics] = []

    public init(target: Note, reference: TuningReference, duration: Duration = .seconds(10),
                tolerance: Double = 10, wrongNoteThreshold: Double = 50) {
        self.target = target
        self.reference = reference
        self.duration = duration
        self.tolerance = tolerance
        self.wrongNoteThreshold = wrongNoteThreshold
    }

    public mutating func process(_ frame: PitchFrame) -> LongToneProgress {
        if isFinished { return .finished }
        if startTime == nil {
            guard frame.frequency != nil else { return .waitingForSound }
            startTime = frame.time
        }
        let elapsed = frame.time - startTime!
        if elapsed >= duration {
            isFinished = true
            return .finished
        }

        frameCount += 1
        lastTime = frame.time
        let binIndex = Int(elapsed / LongToneResult.curveInterval)
        while curveBins.count <= binIndex { curveBins.append(RunningStatistics()) }

        let cents = frame.frequency.map { NoteConverter.cents(frequency: $0, relativeTo: target, reference: reference) }
        if let cents {
            voicedCount += 1
            if abs(cents) <= tolerance + boundaryEpsilon { inToleranceCount += 1 }
            if abs(cents) <= wrongNoteThreshold + boundaryEpsilon {
                statistics.add(cents)
                curveBins[binIndex].add(cents)
            }
        }
        return .running(elapsed: elapsed, cents: cents)
    }

    /// 完成或中斷時呼叫；中斷時以已收集的部分計算。
    public func result() -> LongToneResult {
        let analyzed: Duration = if isFinished {
            duration
        } else if let startTime, let lastTime {
            lastTime - startTime
        } else {
            .zero
        }
        return LongToneResult(
            target: target,
            inToleranceRatio: frameCount > 0 ? Double(inToleranceCount) / Double(frameCount) : 0,
            voicedRatio: frameCount > 0 ? Double(voicedCount) / Double(frameCount) : 0,
            meanCents: statistics.meanIfAny,
            standardDeviationCents: statistics.populationStandardDeviation,
            statFrameCount: statistics.count,
            analyzedDuration: analyzed,
            curve: curveBins.map(\.meanIfAny),
            isComplete: isFinished
        )
    }
}
