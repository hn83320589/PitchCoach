import Charts
import MusicTheory
import PracticeEngine
import SwiftUI

/// PDF 週報的一頁（A4，595 × 842 pt）。數字全部來自 PracticeAnalytics 產生的 WeeklyReport。
struct WeeklyReportPage: View {
    let report: WeeklyReport
    let studentName: String
    let reference: TuningReference
    let generatedAt: Date
    let calendar: Calendar

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summaryRow
            dailyChart
            HStack(alignment: .top, spacing: 14) {
                longToneSection
                scaleSection
            }
            HStack(alignment: .top, spacing: 14) {
                tendencySection(title: "最常偏高的音", notes: report.sharpestNotes, color: .orange)
                tendencySection(title: "最常偏低的音", notes: report.flattestNotes, color: .blue)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(40)
        .frame(width: 595.2, height: 841.8, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PitchCoach 練習週報").font(.system(size: 24, weight: .bold))
            HStack(spacing: 12) {
                if !studentName.isEmpty { Text("學生：\(studentName)") }
                Text("\(dateFormatter.string(from: report.interval.start)) – \(dateFormatter.string(from: report.interval.inclusiveLastDay(calendar: calendar)))")
                Text("A4 = \(Int(reference.a4)) Hz")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            tile("練習天數", "\(report.practiceDays) 天")
            tile("總時數", formatPracticeDuration(report.totalDuration))
            tile("練習次數", "\(report.sessionCount) 次")
            tile("中斷", "\(report.interruptedCount) 次")
        }
    }

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("每日練習分鐘數").font(.system(size: 12, weight: .semibold))
            Chart(report.dailyMinutes, id: \.day) { day in
                BarMark(x: .value("日期", day.day, unit: .day), y: .value("分鐘", day.value))
                    .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: report.dailyMinutes.map(\.day)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                }
            }
            .chartYAxisLabel("分鐘")
            .frame(height: 120)
        }
    }

    private var longToneSection: some View {
        section("長音") {
            if let longTone = report.longTone {
                row("完成次數", "\(longTone.sessionCount) 次")
                row("±10¢ 以內（平均）", String(format: "%.0f%%", longTone.meanAccuracy * 100))
                row("平均偏差", formattedCents(longTone.meanCents))
                row("平均穩定度（標準差）", String(format: "%.1f ¢", longTone.meanStandardDeviation))
            } else {
                Text("本期沒有完成的長音練習").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var scaleSection: some View {
        section("音階") {
            if let scale = report.scale {
                row("完成次數", "\(scale.sessionCount) 次")
                row("平均到位率", String(format: "%.0f%%", scale.meanReachedRatio * 100))
                row("平均 |偏差|", scale.meanAbsoluteCents.map { String(format: "%.1f ¢", $0) } ?? "—")
            } else {
                Text("本期沒有完成的音階練習").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func tendencySection(title: String, notes: [NoteDeviation], color: Color) -> some View {
        section(title) {
            if notes.isEmpty {
                Text("沒有明顯的傾向").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(notes, id: \.note) { note in
                    row("\(note.note.name())（\(note.sessionCount) 次練習）", formattedCents(note.meanCents), valueColor: color)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("「最常偏高／偏低」：平均偏差超過 ±\(Int(PracticeAnalytics.tendencyThresholdCents)) cents，且出現在至少 \(PracticeAnalytics.tendencyMinimumSessions) 次練習中的音。長音與音階成績只計入完成的練習；練習時數含中斷的練習。")
            Text("產生時間：\(dateFormatter.string(from: generatedAt))")
        }
        .font(.system(size: 8))
        .foregroundStyle(.secondary)
    }

    // MARK: - 元件

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ title: String, _ value: String, valueColor: Color = .black) -> some View {
        HStack {
            Text(title).font(.system(size: 10))
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(valueColor)
        }
    }
}
