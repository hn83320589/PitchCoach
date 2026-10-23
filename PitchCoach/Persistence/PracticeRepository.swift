import Foundation
import PracticeEngine
import SwiftData

/// 練習紀錄的存取。統計一律轉成 `SessionSummary` 交給 PracticeEngine 計算。
@MainActor
struct PracticeRepository {
    /// ModelContext 對 container 只是弱參照；持有 container 確保它在 repository 使用期間存活。
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    func save(_ record: PracticeSessionRecord) throws {
        context.insert(record)
        try context.save()
    }

    /// 新到舊。
    func records(since start: Date? = nil) throws -> [PracticeSessionRecord] {
        var descriptor = FetchDescriptor<PracticeSessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        if let start {
            descriptor.predicate = #Predicate { $0.startedAt >= start }
        }
        return try context.fetch(descriptor)
    }

    func summaries(since start: Date? = nil) throws -> [SessionSummary] {
        try records(since: start).map(\.summary)
    }
}
