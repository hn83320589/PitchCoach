import Foundation
import MusicTheory
import SingingEngine

public enum PracticeKind: String, CaseIterable, Sendable {
    case longTone
    case scale
    /// 開著調音器自由演奏（只計時間，不計成績）。
    case freePractice
    case singing
}

public enum PracticeStatus: String, CaseIterable, Sendable {
    case completed
    case interrupted
}

/// 一次練習中某個音的平均偏差（長音為目標音；音階為每個步驟）。
public struct NoteStat: Equatable, Sendable {
    public let note: Note
    public let meanCents: Double
    public let frameCount: Int

    public init(note: Note, meanCents: Double, frameCount: Int) {
        self.note = note
        self.meanCents = meanCents
        self.frameCount = frameCount
    }
}

/// 歌唱的一個音符是否唱準（沒唱算不準），用於「最常唱不準的音高區段」。
public struct NoteOutcome: Equatable, Sendable {
    public let note: Note
    public let accurate: Bool

    public init(note: Note, accurate: Bool) {
        self.note = note
        self.accurate = accurate
    }
}

/// 統計用的練習紀錄。App 把 SwiftData 的紀錄轉成此值型別，所有統計都在 Package 內計算。
public struct SessionSummary: Equatable, Sendable {
    public let startedAt: Date
    /// 實際練習時間（秒）。
    public let activeDuration: TimeInterval
    public let kind: PracticeKind
    public let status: PracticeStatus
    public let longToneAccuracy: Double?
    public let longToneMeanCents: Double?
    public let longToneStandardDeviationCents: Double?
    public let scaleReachedSteps: Int?
    public let scaleTotalSteps: Int?
    public let singingPitchAccuracy: Double?
    public let singingRhythmAccuracy: Double?
    /// 歌唱的曲名。
    public let title: String?
    public let noteStats: [NoteStat]
    public let noteOutcomes: [NoteOutcome]

    public init(startedAt: Date, activeDuration: TimeInterval, kind: PracticeKind, status: PracticeStatus,
                longToneAccuracy: Double? = nil, longToneMeanCents: Double? = nil,
                longToneStandardDeviationCents: Double? = nil,
                scaleReachedSteps: Int? = nil, scaleTotalSteps: Int? = nil,
                singingPitchAccuracy: Double? = nil, singingRhythmAccuracy: Double? = nil, title: String? = nil,
                noteStats: [NoteStat] = [], noteOutcomes: [NoteOutcome] = []) {
        self.startedAt = startedAt
        self.activeDuration = activeDuration
        self.kind = kind
        self.status = status
        self.longToneAccuracy = longToneAccuracy
        self.longToneMeanCents = longToneMeanCents
        self.longToneStandardDeviationCents = longToneStandardDeviationCents
        self.scaleReachedSteps = scaleReachedSteps
        self.scaleTotalSteps = scaleTotalSteps
        self.singingPitchAccuracy = singingPitchAccuracy
        self.singingRhythmAccuracy = singingRhythmAccuracy
        self.title = title
        self.noteStats = noteStats
        self.noteOutcomes = noteOutcomes
    }
}

public struct DailyValue: Equatable, Sendable {
    /// 當地日期的 00:00。
    public let day: Date
    public let value: Double
}

public struct LongToneSummary: Equatable, Sendable {
    public let sessionCount: Int
    public let meanAccuracy: Double
    public let meanCents: Double
    public let meanStandardDeviation: Double
}

public struct ScaleSummary: Equatable, Sendable {
    public let sessionCount: Int
    public let meanReachedRatio: Double
    /// 各音 |平均偏差| 的 frame 加權平均；沒有任何 frame 時為 nil。
    public let meanAbsoluteCents: Double?
}

public struct SingingSummary: Equatable, Sendable {
    public let sessionCount: Int
    public let meanPitchAccuracy: Double
    public let meanRhythmAccuracy: Double
    /// 區間內所有歌唱音符（含中斷練習已唱的部分）中最常唱不準的音高區段。
    public let weakestRange: WeakRange?
}

public struct DailySingingAccuracy: Equatable, Sendable {
    public let day: Date
    public let pitch: Double
    public let rhythm: Double
}

public struct WeeklyReport: Equatable, Sendable {
    public let interval: DateInterval
    public let practiceDays: Int
    /// 總練習時間（秒），含自由練習。
    public let totalDuration: TimeInterval
    /// 其中自由練習的時間（秒）。
    public let freePracticeDuration: TimeInterval
    public let sessionCount: Int
    public let interruptedCount: Int
    public let dailyMinutes: [DailyValue]
    /// 只統計完成的長音練習。
    public let longTone: LongToneSummary?
    /// 只統計完成的音階練習。
    public let scale: ScaleSummary?
    /// 只統計完成的歌唱練習（音高區段含中斷的部分）。
    public let singing: SingingSummary?
    public let sharpestNotes: [NoteDeviation]
    public let flattestNotes: [NoteDeviation]
}

/// 趨勢圖與週報的計算（docs/ARCHITECTURE.md §10）。
///
/// - 分鐘數依**開始時間**所在的當地日期分桶，含中斷的練習與自由練習
/// - 長音準確率只用完成的練習（中斷的練習時間短，比例會失真）
/// - 各音偏差以 frame 數加權，含中斷練習中已完成的部分
public enum PracticeAnalytics {
    /// 「最常偏高／偏低」的門檻：平均偏差需超過 ±5 cents，且出現在至少 2 次練習中。
    public static let tendencyThresholdCents = 5.0
    public static let tendencyMinimumSessions = 2
    public static let tendencyListLength = 3

    public static func dailyMinutes(_ sessions: [SessionSummary], days: Int, endingAt end: Date, calendar: Calendar) -> [DailyValue] {
        minutesPerDay(sessions, days: lastDays(days, endingAt: end, calendar: calendar), calendar: calendar)
    }

    /// 只回傳有完成長音練習的日子。
    public static func longToneAccuracyTrend(_ sessions: [SessionSummary], days: Int, endingAt end: Date, calendar: Calendar) -> [DailyValue] {
        let window = lastDays(days, endingAt: end, calendar: calendar)
        let byDay = Dictionary(grouping: completed(.longTone, in: sessions)) { calendar.startOfDay(for: $0.startedAt) }
        return window.compactMap { day in
            let accuracies = (byDay[day] ?? []).compactMap(\.longToneAccuracy)
            return accuracies.isEmpty ? nil : DailyValue(day: day, value: mean(accuracies))
        }
    }

    /// 只回傳有完成歌唱練習的日子：當天的平均音準與節奏正確率。
    public static func singingAccuracyTrend(_ sessions: [SessionSummary], days: Int, endingAt end: Date,
                                            calendar: Calendar) -> [DailySingingAccuracy] {
        let window = lastDays(days, endingAt: end, calendar: calendar)
        let byDay = Dictionary(grouping: completed(.singing, in: sessions)) { calendar.startOfDay(for: $0.startedAt) }
        return window.compactMap { day in
            guard let sessions = byDay[day], !sessions.isEmpty else { return nil }
            return DailySingingAccuracy(day: day, pitch: mean(sessions.compactMap(\.singingPitchAccuracy)),
                                        rhythm: mean(sessions.compactMap(\.singingRhythmAccuracy)))
        }
    }

    /// 依音高排序的各音平均偏差（frame 加權）。
    public static func noteDeviations(_ sessions: [SessionSummary], in interval: DateInterval) -> [NoteDeviation] {
        var totals: [Note: (sum: Double, frames: Int, sessions: Set<Int>)] = [:]
        for (index, session) in sessions.enumerated() where contains(interval, session.startedAt) {
            for stat in session.noteStats where stat.frameCount > 0 {
                var total = totals[stat.note] ?? (0, 0, [])
                total.sum += stat.meanCents * Double(stat.frameCount)
                total.frames += stat.frameCount
                total.sessions.insert(index)
                totals[stat.note] = total
            }
        }
        return totals
            .map { NoteDeviation(note: $0.key, meanCents: $0.value.sum / Double($0.value.frames),
                                 frameCount: $0.value.frames, sessionCount: $0.value.sessions.count) }
            .sorted { $0.note < $1.note }
    }

    public static func weeklyReport(_ sessions: [SessionSummary], interval: DateInterval, calendar: Calendar) -> WeeklyReport {
        let inRange = sessions.filter { contains(interval, $0.startedAt) }
        let days = daysCovering(interval, calendar: calendar)
        let deviations = noteDeviations(inRange, in: interval)
            .filter { $0.sessionCount >= tendencyMinimumSessions }

        return WeeklyReport(
            interval: interval,
            practiceDays: Set(inRange.map { calendar.startOfDay(for: $0.startedAt) }).count,
            totalDuration: inRange.reduce(0) { $0 + $1.activeDuration },
            freePracticeDuration: inRange.filter { $0.kind == .freePractice }.reduce(0) { $0 + $1.activeDuration },
            sessionCount: inRange.count,
            interruptedCount: inRange.filter { $0.status == .interrupted }.count,
            dailyMinutes: minutesPerDay(inRange, days: days, calendar: calendar),
            longTone: longToneSummary(inRange),
            scale: scaleSummary(inRange),
            singing: singingSummary(inRange),
            sharpestNotes: Array(deviations.filter { $0.meanCents > tendencyThresholdCents }
                .sorted { $0.meanCents > $1.meanCents }.prefix(tendencyListLength)),
            flattestNotes: Array(deviations.filter { $0.meanCents < -tendencyThresholdCents }
                .sorted { $0.meanCents < $1.meanCents }.prefix(tendencyListLength))
        )
    }

    // MARK: - 內部

    private static func longToneSummary(_ sessions: [SessionSummary]) -> LongToneSummary? {
        let done = completed(.longTone, in: sessions)
        guard !done.isEmpty else { return nil }
        return LongToneSummary(
            sessionCount: done.count,
            meanAccuracy: mean(done.compactMap(\.longToneAccuracy)),
            meanCents: mean(done.compactMap(\.longToneMeanCents)),
            meanStandardDeviation: mean(done.compactMap(\.longToneStandardDeviationCents))
        )
    }

    private static func scaleSummary(_ sessions: [SessionSummary]) -> ScaleSummary? {
        let done = completed(.scale, in: sessions)
        guard !done.isEmpty else { return nil }
        let ratios = done.compactMap { session -> Double? in
            guard let reached = session.scaleReachedSteps, let total = session.scaleTotalSteps, total > 0 else { return nil }
            return Double(reached) / Double(total)
        }
        let stats = done.flatMap(\.noteStats)
        let frames = stats.reduce(0) { $0 + $1.frameCount }
        let absoluteSum = stats.reduce(0.0) { $0 + abs($1.meanCents) * Double($1.frameCount) }
        return ScaleSummary(sessionCount: done.count, meanReachedRatio: mean(ratios),
                            meanAbsoluteCents: frames > 0 ? absoluteSum / Double(frames) : nil)
    }

    private static func singingSummary(_ sessions: [SessionSummary]) -> SingingSummary? {
        let done = completed(.singing, in: sessions)
        guard !done.isEmpty else { return nil }
        let outcomes = sessions.filter { $0.kind == .singing }.flatMap(\.noteOutcomes).map { ($0.note, $0.accurate) }
        return SingingSummary(sessionCount: done.count,
                              meanPitchAccuracy: mean(done.compactMap(\.singingPitchAccuracy)),
                              meanRhythmAccuracy: mean(done.compactMap(\.singingRhythmAccuracy)),
                              weakestRange: WeakRange.find(in: outcomes))
    }

    private static func minutesPerDay(_ sessions: [SessionSummary], days: [Date], calendar: Calendar) -> [DailyValue] {
        let seconds = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
            .mapValues { $0.reduce(0) { $0 + $1.activeDuration } }
        return days.map { DailyValue(day: $0, value: (seconds[$0] ?? 0) / 60) }
    }

    private static func lastDays(_ count: Int, endingAt end: Date, calendar: Calendar) -> [Date] {
        let last = calendar.startOfDay(for: end)
        return (0..<count).reversed().map { calendar.date(byAdding: .day, value: -$0, to: last)! }
    }

    private static func daysCovering(_ interval: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    private static func completed(_ kind: PracticeKind, in sessions: [SessionSummary]) -> [SessionSummary] {
        sessions.filter { $0.kind == kind && $0.status == .completed }
    }

    /// 半開區間 [start, end)：區間結束的那一刻屬於下一段。
    private static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - 從練習結果建立摘要

extension SessionSummary {
    /// 長音：目標音的統計成為唯一的 NoteStat。未指定狀態時依結果是否完整決定。
    public init(longTone result: LongToneResult, startedAt: Date, status: PracticeStatus? = nil) {
        let noteStats = result.meanCents.map { [NoteStat(note: result.target, meanCents: $0, frameCount: result.statFrameCount)] } ?? []
        self.init(startedAt: startedAt,
                  activeDuration: result.analyzedDuration.timeInterval,
                  kind: .longTone,
                  status: status ?? (result.isComplete ? .completed : .interrupted),
                  longToneAccuracy: result.inToleranceRatio,
                  longToneMeanCents: result.meanCents,
                  longToneStandardDeviationCents: result.standardDeviationCents,
                  noteStats: noteStats)
    }

    /// 音階：每個有資料的步驟成為一筆 NoteStat（同一音高在上下行各一筆，統計時以 frame 加權合併）。
    public init(scale result: ScaleResult, startedAt: Date, activeDuration: TimeInterval, status: PracticeStatus? = nil) {
        let noteStats = result.steps.compactMap { step in
            step.meanCents.map { NoteStat(note: step.note, meanCents: $0, frameCount: step.frameCount) }
        }
        self.init(startedAt: startedAt,
                  activeDuration: activeDuration,
                  kind: .scale,
                  status: status ?? (result.isComplete ? .completed : .interrupted),
                  scaleReachedSteps: result.reachedCount,
                  scaleTotalSteps: result.steps.count,
                  noteStats: noteStats)
    }
}

extension SessionSummary {
    /// 歌唱各音偏差只收 |偏差| ≤ 100 cents 的音（唱成別的音或沒容許八度時的低八度不代表音準傾向）。
    public static let singingDeviationLimit = 100.0

    public init(singing result: SingingResult, title: String, startedAt: Date, activeDuration: TimeInterval,
                status: PracticeStatus? = nil) {
        let noteStats = result.notes.compactMap { note -> NoteStat? in
            guard let cents = note.centsDeviation, abs(cents) <= Self.singingDeviationLimit, note.frameCount > 0 else { return nil }
            return NoteStat(note: note.note.pitch, meanCents: cents, frameCount: note.frameCount)
        }
        self.init(startedAt: startedAt, activeDuration: activeDuration, kind: .singing,
                  status: status ?? (result.isComplete ? .completed : .interrupted),
                  singingPitchAccuracy: result.pitchAccuracy, singingRhythmAccuracy: result.rhythmAccuracy, title: title,
                  noteStats: noteStats,
                  noteOutcomes: result.notes.map { NoteOutcome(note: $0.note.pitch, accurate: $0.pitchVerdict == .accurate) })
    }
}
