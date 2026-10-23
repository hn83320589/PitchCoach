import Foundation
import MusicTheory
import PracticeEngine
import SwiftData

/// 一次練習的紀錄。列舉以 raw string 儲存（SwiftData 的 #Predicate 對自訂 enum 支援不穩定）。
@Model
final class PracticeSessionRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var statusRaw: String
    var interruptionReasonRaw: String?
    var startedAt: Date
    /// 實際練習時間（秒）。
    var activeDuration: Double
    var referenceA4: Double

    // 長音
    var targetMidi: Int?
    var inToleranceRatio: Double?
    var meanCents: Double?
    var standardDeviationCents: Double?
    /// 20 Hz 偏差曲線，Float32 陣列，NaN 表示該區間無音高。
    var curveData: Data?

    // 音階
    var scaleKeyRaw: String?
    var startOctave: Int?
    var directionRaw: String?
    var reachedSteps: Int?
    var totalSteps: Int?

    @Relationship(deleteRule: .cascade, inverse: \NoteStatRecord.session)
    var noteStats: [NoteStatRecord] = []

    private init(summary: SessionSummary, reference: TuningReference, interruption: PracticeInterruptionReason?) {
        id = UUID()
        kindRaw = summary.kind.rawValue
        statusRaw = summary.status.rawValue
        interruptionReasonRaw = interruption?.rawValue
        startedAt = summary.startedAt
        activeDuration = summary.activeDuration
        referenceA4 = reference.a4
        inToleranceRatio = summary.longToneAccuracy
        meanCents = summary.longToneMeanCents
        standardDeviationCents = summary.longToneStandardDeviationCents
        reachedSteps = summary.scaleReachedSteps
        totalSteps = summary.scaleTotalSteps
    }

    convenience init(longTone result: LongToneResult, startedAt: Date, reference: TuningReference,
                     interruption: PracticeInterruptionReason?) {
        let summary = SessionSummary(longTone: result, startedAt: startedAt, status: Self.status(interruption, complete: result.isComplete))
        self.init(summary: summary, reference: reference, interruption: interruption)
        targetMidi = result.target.midi
        curveData = Self.encode(curve: result.curve)
        noteStats = summary.noteStats.map { NoteStatRecord(stat: $0, stepIndex: nil, reached: true) }
    }

    convenience init(scale result: ScaleResult, startedAt: Date, activeDuration: TimeInterval,
                     reference: TuningReference, interruption: PracticeInterruptionReason?) {
        let summary = SessionSummary(scale: result, startedAt: startedAt, activeDuration: activeDuration,
                                     status: Self.status(interruption, complete: result.isComplete))
        self.init(summary: summary, reference: reference, interruption: interruption)
        scaleKeyRaw = result.scale.key.rawValue
        startOctave = result.scale.startOctave
        directionRaw = result.scale.direction.rawValue
        noteStats = result.steps.enumerated().compactMap { index, step in
            step.meanCents.map {
                NoteStatRecord(stat: NoteStat(note: step.note, meanCents: $0, frameCount: step.frameCount),
                               stepIndex: index, reached: step.reached)
            }
        }
    }

    // MARK: - 讀取

    var kind: PracticeKind { PracticeKind(rawValue: kindRaw) ?? .longTone }
    var status: PracticeStatus { PracticeStatus(rawValue: statusRaw) ?? .interrupted }
    var interruptionReason: PracticeInterruptionReason? { interruptionReasonRaw.flatMap(PracticeInterruptionReason.init) }
    var scaleKey: MajorKey? { scaleKeyRaw.flatMap(MajorKey.init) }
    var direction: ScaleDirection? { directionRaw.flatMap(ScaleDirection.init) }
    var targetNote: Note? { targetMidi.map(Note.init) }

    /// 依步驟順序（長音只有一筆）。SwiftData 的關聯不保證順序。
    var sortedNoteStats: [NoteStatRecord] {
        noteStats.sorted { ($0.stepIndex ?? 0) < ($1.stepIndex ?? 0) }
    }

    var curve: [Double?] {
        guard let curveData else { return [] }
        return curveData.withUnsafeBytes { raw in
            raw.bindMemory(to: Float32.self).map { $0.isNaN ? nil : Double($0) }
        }
    }

    var summary: SessionSummary {
        SessionSummary(startedAt: startedAt, activeDuration: activeDuration, kind: kind, status: status,
                       longToneAccuracy: inToleranceRatio, longToneMeanCents: meanCents,
                       longToneStandardDeviationCents: standardDeviationCents,
                       scaleReachedSteps: reachedSteps, scaleTotalSteps: totalSteps,
                       noteStats: sortedNoteStats.map(\.stat))
    }

    private static func status(_ interruption: PracticeInterruptionReason?, complete: Bool) -> PracticeStatus {
        interruption == nil && complete ? .completed : .interrupted
    }

    private static func encode(curve: [Double?]) -> Data {
        let values = curve.map { $0.map(Float32.init) ?? .nan }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

@Model
final class NoteStatRecord {
    var midi: Int
    /// 音階的步驟索引；長音為 nil。
    var stepIndex: Int?
    var meanCents: Double
    var frameCount: Int
    var reached: Bool
    var session: PracticeSessionRecord?

    init(stat: NoteStat, stepIndex: Int?, reached: Bool) {
        midi = stat.note.midi
        self.stepIndex = stepIndex
        meanCents = stat.meanCents
        frameCount = stat.frameCount
        self.reached = reached
    }

    var stat: NoteStat {
        NoteStat(note: Note(midi: midi), meanCents: meanCents, frameCount: frameCount)
    }
}
