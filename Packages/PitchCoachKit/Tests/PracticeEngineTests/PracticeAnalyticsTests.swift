import Foundation
import Testing
import MusicTheory
import SingingEngine
@testable import PracticeEngine

struct PracticeAnalyticsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 18, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func longTone(_ start: Date, minutes: Double = 1, accuracy: Double, mean: Double, std: Double,
                          status: PracticeStatus = .completed, note: Note = a4, frames: Int = 900) -> SessionSummary {
        SessionSummary(startedAt: start, activeDuration: minutes * 60, kind: .longTone, status: status,
                       longToneAccuracy: accuracy, longToneMeanCents: mean, longToneStandardDeviationCents: std,
                       noteStats: [NoteStat(note: note, meanCents: mean, frameCount: frames)])
    }

    private func scale(_ start: Date, minutes: Double = 2, reached: Int, total: Int = 8,
                       status: PracticeStatus = .completed, noteStats: [NoteStat]) -> SessionSummary {
        SessionSummary(startedAt: start, activeDuration: minutes * 60, kind: .scale, status: status,
                       scaleReachedSteps: reached, scaleTotalSteps: total, noteStats: noteStats)
    }

    @Test func dailyMinutesAreBucketedByLocalStartDay() {
        // 23:50 開始、練 20 分鐘，跨過午夜仍算在開始那天
        let sessions = [longTone(date(20, 23, 50), minutes: 20, accuracy: 1, mean: 0, std: 0),
                        longTone(date(21, 7, 0), minutes: 5, accuracy: 1, mean: 0, std: 0)]
        let daily = PracticeAnalytics.dailyMinutes(sessions, days: 30, endingAt: date(23), calendar: calendar)
        #expect(daily.count == 30)
        #expect(daily.first?.day == calendar.startOfDay(for: date(24, month: 9)))
        #expect(daily.last?.day == calendar.startOfDay(for: date(23)))
        #expect(daily.first { $0.day == calendar.startOfDay(for: date(20)) }?.value == 20)
        #expect(daily.first { $0.day == calendar.startOfDay(for: date(21)) }?.value == 5)
        #expect(daily.reduce(0) { $0 + $1.value } == 25)
    }

    @Test func dailyMinutesIgnoreSessionsOutsideWindow() {
        let sessions = [longTone(date(23, month: 9), minutes: 10, accuracy: 1, mean: 0, std: 0),   // 第 31 天前
                        longTone(date(24, 0, 0, month: 9), minutes: 3, accuracy: 1, mean: 0, std: 0),
                        longTone(date(24), minutes: 7, accuracy: 1, mean: 0, std: 0)]               // 未來
        let daily = PracticeAnalytics.dailyMinutes(sessions, days: 30, endingAt: date(23), calendar: calendar)
        #expect(daily.reduce(0) { $0 + $1.value } == 3)
    }

    @Test func longToneAccuracyTrendAveragesCompletedSessionsOnly() {
        let sessions = [longTone(date(20, 9), accuracy: 0.6, mean: 0, std: 0),
                        longTone(date(20, 19), accuracy: 0.8, mean: 0, std: 0),
                        longTone(date(20, 20), accuracy: 0.1, mean: 0, std: 0, status: .interrupted),
                        longTone(date(22), accuracy: 0.9, mean: 0, std: 0)]
        let trend = PracticeAnalytics.longToneAccuracyTrend(sessions, days: 30, endingAt: date(23), calendar: calendar)
        #expect(trend.count == 2)
        #expect(abs(trend[0].value - 0.7) < 1e-12)
        #expect(trend[0].day == calendar.startOfDay(for: date(20)))
        #expect(abs(trend[1].value - 0.9) < 1e-12)
    }

    @Test func noteDeviationsAreWeightedByFrameCount() throws {
        let b4 = Note(midi: 71)
        let sessions = [longTone(date(20), accuracy: 1, mean: 10, std: 0, frames: 100),
                        longTone(date(21), accuracy: 1, mean: -20, std: 0, status: .interrupted, frames: 50),
                        scale(date(22), reached: 8, noteStats: [NoteStat(note: a4, meanCents: 4, frameCount: 50),
                                                                 NoteStat(note: b4, meanCents: -6, frameCount: 30)])]
        let deviations = PracticeAnalytics.noteDeviations(sessions, in: DateInterval(start: date(1), end: date(31)))
        #expect(deviations.map(\.note) == [a4, b4])
        // A4：(10·100 − 20·50 + 4·50) / 200 = 1.0
        #expect(abs(deviations[0].meanCents - 1.0) < 1e-12)
        #expect(deviations[0].frameCount == 200)
        #expect(deviations[0].sessionCount == 3)
    }

    @Test func weeklyReportSummarizesPracticeAndScores() throws {
        let c5 = Note(midi: 72)
        let sessions = [
            longTone(date(19), minutes: 1, accuracy: 0.6, mean: 4, std: 8),
            longTone(date(19, 20), minutes: 1, accuracy: 0.8, mean: -2, std: 6),
            longTone(date(21), minutes: 0.5, accuracy: 0.2, mean: 9, std: 20, status: .interrupted),
            scale(date(22), minutes: 3, reached: 6, noteStats: [NoteStat(note: c5, meanCents: 10, frameCount: 100),
                                                                 NoteStat(note: a4, meanCents: -4, frameCount: 300)]),
            scale(date(30), minutes: 9, reached: 8, noteStats: []),   // 區間外
        ]
        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        let report = PracticeAnalytics.weeklyReport(sessions, interval: interval, calendar: calendar)

        #expect(report.practiceDays == 3)
        #expect(report.totalDuration == 330)          // 60 + 60 + 30 + 180 秒
        #expect(report.sessionCount == 4)
        #expect(report.interruptedCount == 1)
        #expect(report.dailyMinutes.count == 7)

        let longTone = try #require(report.longTone)
        #expect(longTone.sessionCount == 2)           // 中斷的不計入成績
        #expect(abs(longTone.meanAccuracy - 0.7) < 1e-12)
        #expect(abs(longTone.meanCents - 1) < 1e-12)
        #expect(abs(longTone.meanStandardDeviation - 7) < 1e-12)

        let scale = try #require(report.scale)
        #expect(scale.sessionCount == 1)
        #expect(abs(scale.meanReachedRatio - 0.75) < 1e-12)
        // |平均偏差| 以 frame 加權：(10·100 + 4·300) / 400 = 5.5
        #expect(abs(try #require(scale.meanAbsoluteCents) - 5.5) < 1e-12)
    }

    @Test func weeklyReportListsConsistentlySharpAndFlatNotes() {
        func note(_ midi: Int, _ cents: Double) -> NoteStat { NoteStat(note: Note(midi: midi), meanCents: cents, frameCount: 100) }
        // 兩次練習都出現的音才列入；平均需超過 ±5 cents；各取前 3 名
        let first = [note(60, 12), note(62, 8), note(64, 6), note(65, 30), note(67, -9), note(69, -4), note(71, -20)]
        let second = [note(60, 10), note(62, 8), note(64, 7), note(66, 50), note(67, -7), note(69, -5), note(71, -16), note(72, 5.5)]
        let sessions = [scale(date(18), reached: 8, noteStats: first),
                        scale(date(20), reached: 8, noteStats: second + [note(72, 5.5)])]
        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        let report = PracticeAnalytics.weeklyReport(sessions, interval: interval, calendar: calendar)

        // F4（65）與 F#4（66）只出現一次；C5（72）兩筆都在同一次練習 → 不列入
        #expect(report.sharpestNotes.map { $0.note.name() } == ["C4", "D4", "E4"])
        // A4 平均 −4.5 未超過 −5 → 不列入
        #expect(report.flattestNotes.map { $0.note.name() } == ["B4", "G4"])
    }

    @Test func emptyIntervalProducesEmptyReport() {
        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        let report = PracticeAnalytics.weeklyReport([], interval: interval, calendar: calendar)
        #expect(report.practiceDays == 0)
        #expect(report.totalDuration == 0)
        #expect(report.longTone == nil)
        #expect(report.scale == nil)
        #expect(report.sharpestNotes.isEmpty && report.flattestNotes.isEmpty)
        #expect(report.dailyMinutes.allSatisfy { $0.value == 0 })
    }

    @Test func freePracticeCountsTowardMinutesButNotScores() {
        let sessions = [longTone(date(20), minutes: 1, accuracy: 0.5, mean: 0, std: 0),
                        SessionSummary(startedAt: date(20, 19), activeDuration: 1200, kind: .freePractice, status: .completed)]
        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        let report = PracticeAnalytics.weeklyReport(sessions, interval: interval, calendar: calendar)
        #expect(report.totalDuration == 1260)
        #expect(report.freePracticeDuration == 1200)
        #expect(report.longTone?.sessionCount == 1)
        #expect(PracticeAnalytics.dailyMinutes(sessions, days: 30, endingAt: date(23), calendar: calendar)
            .first { $0.day == calendar.startOfDay(for: date(20)) }?.value == 21)
    }

    private func singing(_ start: Date, pitch: Double, rhythm: Double, status: PracticeStatus = .completed,
                         outcomes: [(Int, Bool)] = []) -> SessionSummary {
        SessionSummary(startedAt: start, activeDuration: 30, kind: .singing, status: status,
                       singingPitchAccuracy: pitch, singingRhythmAccuracy: rhythm, title: "小星星",
                       noteOutcomes: outcomes.map { NoteOutcome(note: Note(midi: $0.0), accurate: $0.1) })
    }

    @Test func singingTrendAndWeeklySummaryUseCompletedSessions() throws {
        let sessions = [
            singing(date(20, 9), pitch: 0.6, rhythm: 0.8, outcomes: [(60, true), (67, false), (69, false)]),
            singing(date(20, 19), pitch: 0.8, rhythm: 0.6, outcomes: [(62, true), (69, false), (71, true)]),
            singing(date(21), pitch: 0.1, rhythm: 0.1, status: .interrupted, outcomes: [(67, false)]),
        ]
        let trend = PracticeAnalytics.singingAccuracyTrend(sessions, days: 30, endingAt: date(23), calendar: calendar)
        #expect(trend.count == 1)
        #expect(abs(trend[0].pitch - 0.7) < 1e-12)
        #expect(abs(trend[0].rhythm - 0.7) < 1e-12)

        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        let report = PracticeAnalytics.weeklyReport(sessions, interval: interval, calendar: calendar)
        let singing = try #require(report.singing)
        #expect(singing.sessionCount == 2)
        #expect(abs(singing.meanPitchAccuracy - 0.7) < 1e-12)
        // 整週（含中斷的部分）：F4–A4 區段（實際出現 G4 ×2、A4 ×2）4 個全不準，
        // 比 G4–B4 區段（5 個中 4 個不準）更差
        let weak = try #require(singing.weakestRange)
        #expect(weak.lowest.name() == "G4")
        #expect(weak.highest.name() == "A4")
        #expect(weak.missed == 4 && weak.total == 4)
    }
}
