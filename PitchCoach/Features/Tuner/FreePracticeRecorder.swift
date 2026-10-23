import Foundation
import MusicTheory
import os
import PitchDetection
import PracticeEngine

private let logger = Logger(subsystem: "PitchCoach", category: "FreePractice")

/// 調音器畫面開著並演奏時，把演奏時間存成「自由練習」紀錄（判定規則見 FreePracticeTracker）。
@MainActor
final class FreePracticeRecorder {
    var reference = TuningReference.default
    /// 由畫面注入（需要 Environment 的 modelContext）。
    var save: (@MainActor (PracticeSessionRecord) throws -> Void)?

    private var tracker = FreePracticeTracker()
    private var startedAt: Date?

    func process(_ frame: PitchFrame) {
        let wasActive = tracker.isActive
        if let segment = tracker.process(frame) {
            store(segment)
        }
        if !wasActive, tracker.isActive {
            startedAt = Date()
        }
    }

    /// 離開調音器、進入背景或收音被中斷時呼叫。
    func finish() {
        if let segment = tracker.finish() {
            store(segment)
        }
        startedAt = nil
    }

    private func store(_ segment: FreePracticeSegment) {
        let record = PracticeSessionRecord(freePractice: segment.activeDuration.seconds, startedAt: startedAt ?? Date(),
                                           reference: reference)
        startedAt = nil
        guard let save else {
            logger.error("自由練習紀錄未儲存：尚未設定儲存位置")
            return
        }
        do {
            try save(record)
        } catch {
            logger.error("自由練習紀錄儲存失敗：\(error.localizedDescription)")
        }
    }
}
