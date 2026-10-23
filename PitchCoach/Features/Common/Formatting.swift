import Foundation

/// 練習時間的中文表示：「45 秒」「12 分 30 秒」「55 分」「1 小時 5 分」。
func formatPracticeDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600, minutes = total % 3600 / 60, remainder = total % 60
    if hours > 0 { return "\(hours) 小時 \(minutes) 分" }
    if minutes > 0 { return remainder > 0 ? "\(minutes) 分 \(remainder) 秒" : "\(minutes) 分" }
    return "\(remainder) 秒"
}

extension DateInterval {
    /// 區間為半開 [start, end)，顯示時的最後一天是 end 的前一天。
    func inclusiveLastDay(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: end) ?? end
    }
}
