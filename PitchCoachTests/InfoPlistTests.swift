import Foundation
import Testing
@testable import PitchCoach

struct InfoPlistTests {
    /// 缺少麥克風用途說明時，iOS 會在第一次存取麥克風時直接終止 App。
    @Test func microphoneUsageDescriptionIsPresent() throws {
        let description = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        )
        #expect(!description.isEmpty)
    }
}
