import Foundation
import MusicTheory
import PracticeEngine
import SwiftUI

/// 把週報畫成 PDF（向量輸出，文字可搜尋、可複製）。
@MainActor
enum WeeklyReportPDF {
    /// A4（pt）。
    static let pageSize = CGSize(width: 595.2, height: 841.8)

    enum RenderError: LocalizedError {
        case contextCreationFailed

        var errorDescription: String? { "無法建立 PDF 繪圖環境。" }
    }

    static func render(_ report: WeeklyReport, studentName: String, reference: TuningReference,
                       generatedAt: Date = Date(), calendar: Calendar = .current) throws -> Data {
        let page = WeeklyReportPage(report: report, studentName: studentName, reference: reference,
                                    generatedAt: generatedAt, calendar: calendar)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(pageSize)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.contextCreationFailed
        }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// 例如「PitchCoach_週報_2026-10-17_2026-10-23.pdf」（結束日為區間內最後一天）。
    static func fileName(for interval: DateInterval, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "PitchCoach_週報_\(formatter.string(from: interval.start))_\(formatter.string(from: interval.inclusiveLastDay(calendar: calendar))).pdf"
    }

    /// 寫到暫存資料夾，供分享選單使用。
    static func write(_ data: Data, interval: DateInterval, calendar: Calendar = .current) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: interval, calendar: calendar))
        try data.write(to: url, options: .atomic)
        return url
    }
}
