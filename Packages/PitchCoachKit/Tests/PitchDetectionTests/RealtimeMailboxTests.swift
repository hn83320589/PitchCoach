import Testing
@testable import PitchDetection

struct RealtimeMailboxTests {
    private func drain(_ mailbox: RealtimeMailbox<Int>) -> [Int] {
        var values: [Int] = []
        mailbox.drain { values.append($0) }
        return values
    }

    @Test func deliversValuesInOrder() {
        let mailbox = RealtimeMailbox<Int>(capacity: 8, placeholder: 0)
        for value in 1...5 { mailbox.push(value) }
        #expect(drain(mailbox) == [1, 2, 3, 4, 5])
        #expect(drain(mailbox).isEmpty)
    }

    @Test func overflowKeepsNewestValuesAndCountsDrops() {
        let mailbox = RealtimeMailbox<Int>(capacity: 4, placeholder: 0)
        for value in 1...10 { mailbox.push(value) }
        #expect(drain(mailbox) == [7, 8, 9, 10])
        #expect(mailbox.droppedCount == 6)
    }

    @Test func pushWhileConsumerHoldsLockIsDeferredNotLost() {
        let mailbox = RealtimeMailbox<Int>(capacity: 8, placeholder: 0)
        mailbox.push(1)
        // 模擬主執行緒正持有鎖：trylock 失敗，值暫存在生產者端
        let deferred = mailbox.withLockHeldForTesting { mailbox.push(2) }
        #expect(deferred == false)
        mailbox.push(3)
        #expect(drain(mailbox) == [1, 2, 3])
    }
}
