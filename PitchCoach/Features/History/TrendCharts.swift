import Charts
import MusicTheory
import PracticeEngine
import SwiftUI

/// 近 30 天趨勢：每日分鐘數、長音準確率、各音平均偏差。數字全部來自 PracticeAnalytics。
struct TrendCharts: View {
    let summaries: [SessionSummary]
    var now = Date()
    var calendar = Calendar.current

    private var window: DateInterval {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: end)!, end: end)
    }

    var body: some View {
        let daily = PracticeAnalytics.dailyMinutes(summaries, days: 30, endingAt: now, calendar: calendar)
        let accuracy = PracticeAnalytics.longToneAccuracyTrend(summaries, days: 30, endingAt: now, calendar: calendar)
        let notes = PracticeAnalytics.noteDeviations(summaries, in: window)
        let singing = PracticeAnalytics.singingAccuracyTrend(summaries, days: 30, endingAt: now, calendar: calendar)

        VStack(alignment: .leading, spacing: 28) {
            chartSection("每日練習分鐘數") {
                Chart(daily, id: \.day) { day in
                    BarMark(x: .value("日期", day.day, unit: .day), y: .value("分鐘", day.value))
                        .foregroundStyle(Color.accentColor)
                }
                .chartXAxis { weekAxis }
                .frame(height: 160)
            }

            chartSection("長音準確率（±10¢ 以內）") {
                if accuracy.isEmpty {
                    emptyText("近 30 天沒有完成的長音練習")
                } else {
                    Chart(accuracy, id: \.day) { day in
                        LineMark(x: .value("日期", day.day, unit: .day), y: .value("準確率", day.value * 100))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("日期", day.day, unit: .day), y: .value("準確率", day.value * 100))
                    }
                    .chartXScale(domain: window.start...window.end)
                    .chartXAxis { weekAxis }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                        }
                    }
                    .frame(height: 160)
                }
            }

            if !singing.isEmpty {
                chartSection("歌唱正確率") {
                    Chart {
                        ForEach(singing, id: \.day) { day in
                            LineMark(x: .value("日期", day.day, unit: .day), y: .value("正確率", day.pitch * 100),
                                     series: .value("項目", "音準"))
                                .foregroundStyle(by: .value("項目", "音準"))
                            LineMark(x: .value("日期", day.day, unit: .day), y: .value("正確率", day.rhythm * 100),
                                     series: .value("項目", "節奏"))
                                .foregroundStyle(by: .value("項目", "節奏"))
                        }
                    }
                    .chartXScale(domain: window.start...window.end)
                    .chartXAxis { weekAxis }
                    .chartYScale(domain: 0...100)
                    .frame(height: 160)
                }
            }

            chartSection("各音平均偏差") {
                if notes.isEmpty {
                    emptyText("近 30 天沒有可統計的音")
                } else {
                    let limit = max(15, notes.map { abs($0.meanCents) }.max() ?? 0)
                    Chart(notes.reversed(), id: \.note) { note in
                        BarMark(x: .value("偏差", note.meanCents), y: .value("音", note.note.name()))
                            .foregroundStyle(note.meanCents >= 0 ? Color.orange : Color.blue)
                            .annotation(position: note.meanCents >= 0 ? .trailing : .leading) {
                                Text(formattedCents(note.meanCents)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                    }
                    .chartXScale(domain: -limit * 1.4...limit * 1.4)
                    .chartXAxisLabel("cents（橘色偏高、藍色偏低）")
                    .frame(height: CGFloat(notes.count) * 26 + 40)
                }
            }
        }
    }

    private var weekAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
        }
    }

    private func chartSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
    }
}
