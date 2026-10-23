import Foundation
import MusicTheory
import PDFKit
import PracticeEngine
import Testing
@testable import PitchCoach

@MainActor
struct WeeklyReportPDFTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func fixtureReport() -> WeeklyReport {
        let fSharp4 = Note(midi: 66), bFlat4 = Note(midi: 70)
        let sessions = [
            SessionSummary(startedAt: date(19), activeDuration: 600, kind: .longTone, status: .completed,
                           longToneAccuracy: 0.8, longToneMeanCents: 3, longToneStandardDeviationCents: 6,
                           noteStats: [NoteStat(note: Note(midi: 69), meanCents: 3, frameCount: 900)]),
            SessionSummary(startedAt: date(20), activeDuration: 1200, kind: .scale, status: .completed,
                           scaleReachedSteps: 8, scaleTotalSteps: 8,
                           noteStats: [NoteStat(note: fSharp4, meanCents: 11, frameCount: 100),
                                       NoteStat(note: bFlat4, meanCents: -9, frameCount: 100)]),
            SessionSummary(startedAt: date(22), activeDuration: 1500, kind: .scale, status: .completed,
                           scaleReachedSteps: 7, scaleTotalSteps: 8,
                           noteStats: [NoteStat(note: fSharp4, meanCents: 9, frameCount: 100),
                                       NoteStat(note: bFlat4, meanCents: -7, frameCount: 100)]),
        ]
        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        return PracticeAnalytics.weeklyReport(sessions, interval: interval, calendar: calendar)
    }

    /// PingFang 的部分字形（音、生、小、高…）同時對應康熙部首碼位，PDF 的 ToUnicode 反查會得到部首
    /// （例如「音」U+97F3 抽出為「⾳」U+2FB3）。畫面顯示正確，只是抽出的文字需以 NFKC 正規化還原。
    private func extractText(_ data: Data) throws -> String {
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        return try #require(document.string).precomposedStringWithCompatibilityMapping
    }

    @Test func pdfContainsSearchableChineseTextAndReportNumbers() throws {
        let data = try WeeklyReportPDF.render(fixtureReport(), studentName: "王小明", reference: .default,
                                              generatedAt: date(23, 20), calendar: calendar)
        let text = try extractText(data)
        for expected in ["練習週報", "王小明", "練習天數", "3 天", "總時數", "55 分", "長音", "80%", "音階",
                         "最常偏高", "F#4", "+10.0", "最常偏低", "A#4", "-8.0", "A4 = 442 Hz",
                         // 總時數扣掉自由練習後也包含歌唱，說明文字不能只寫長音、音階
                         "長音、音階、歌唱練習"] {
            #expect(text.contains(expected), "PDF 文字中找不到「\(expected)」")
        }
    }

    @Test func pdfPageIsA4() throws {
        let data = try WeeklyReportPDF.render(fixtureReport(), studentName: "", reference: .default,
                                              generatedAt: date(23, 20), calendar: calendar)
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(abs(bounds.width - 595.2) < 1)
        #expect(abs(bounds.height - 841.8) < 1)
    }

    @Test func fileNameIncludesInclusiveDateRange() {
        let interval = DateInterval(start: calendar.startOfDay(for: date(17)), end: calendar.startOfDay(for: date(24)))
        #expect(WeeklyReportPDF.fileName(for: interval, calendar: calendar) == "PitchCoach_週報_2026-10-17_2026-10-23.pdf")
    }

    @Test func practiceDurationIsFormattedInChinese() {
        #expect(formatPracticeDuration(45) == "45 秒")
        #expect(formatPracticeDuration(750) == "12 分 30 秒")
        #expect(formatPracticeDuration(3300) == "55 分")
        #expect(formatPracticeDuration(3900) == "1 小時 5 分")
    }
}
