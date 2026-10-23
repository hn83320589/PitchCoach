import SwiftData
import SwiftUI

@main
struct PitchCoachApp: App {
    @State private var settings = AppSettings()
    @State private var pipeline = AudioPipeline()
    private let modelContainer = Self.makeModelContainer()

    /// UI 測試（啟動參數 -uiTesting）使用記憶體內儲存，不汙染真實紀錄。
    private static func makeModelContainer() -> ModelContainer {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        do {
            return try ModelContainer(for: PracticeSessionRecord.self, NoteStatRecord.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            // 沒有資料庫就無法保存練習紀錄，直接終止並附上原因，比靜默失去資料好
            fatalError("無法建立練習紀錄資料庫：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(pipeline)
        }
        .modelContainer(modelContainer)
    }
}
