import os

/// 單一生產者（音訊 IO 執行緒）、單一消費者（主執行緒）的固定容量信箱。
///
/// - `push` 只用 trylock，拿不到鎖時把值暫存在生產者專屬的緩衝，下次 push 再一併送出，
///   因此 IO 執行緒永遠不會等待鎖，也不配置記憶體
/// - 消費者太久沒取用時覆蓋最舊的值，並累計 `droppedCount`
///
/// `push` 只能由同一個執行緒呼叫；`drain` 只能由另一個（同一個）執行緒呼叫。
public final class RealtimeMailbox<Element: Sendable>: @unchecked Sendable {
    private struct Ring {
        var head = 0
        var count = 0
        var dropped = 0
    }

    private let capacity: Int
    private let storage: UnsafeMutablePointer<Element>
    private let lock = OSAllocatedUnfairLock(initialState: Ring())

    // 只有生產者執行緒會存取
    private let pending: UnsafeMutablePointer<Element>
    private var pendingCount = 0

    public init(capacity: Int, placeholder: Element) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: placeholder, count: capacity)
        pending = .allocate(capacity: capacity)
        pending.initialize(repeating: placeholder, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
        pending.deinitialize(count: capacity)
        pending.deallocate()
    }

    /// 回傳 false 表示這次拿不到鎖，值已暫存，會在下次成功 push 時送出。
    @discardableResult
    public func push(_ value: Element) -> Bool {
        if pendingCount == capacity {
            // 暫存區也滿了：丟掉最舊的暫存值
            pending.update(from: pending + 1, count: capacity - 1)
            pendingCount -= 1
            lock.withLockIfAvailableUnchecked { $0.dropped += 1 }
        }
        pending[pendingCount] = value
        pendingCount += 1

        let delivered = lock.withLockIfAvailableUnchecked { ring -> Bool in
            for index in 0..<pendingCount {
                write(pending[index], into: &ring)
            }
            return true
        } ?? false
        if delivered { pendingCount = 0 }
        return delivered
    }

    /// 依序取出所有值。
    public func drain(_ body: (Element) -> Void) {
        let values = lock.withLockUnchecked { ring -> [Element] in
            let result = (0..<ring.count).map { storage[(ring.head + $0) % capacity] }
            ring.head = (ring.head + ring.count) % capacity
            ring.count = 0
            return result
        }
        values.forEach(body)
    }

    public var droppedCount: Int {
        lock.withLock { $0.dropped }
    }

    private func write(_ value: Element, into ring: inout Ring) {
        if ring.count == capacity {
            ring.head = (ring.head + 1) % capacity
            ring.count -= 1
            ring.dropped += 1
        }
        storage[(ring.head + ring.count) % capacity] = value
        ring.count += 1
    }

    func withLockHeldForTesting<T>(_ body: () -> T) -> T {
        lock.withLockUnchecked { _ in body() }
    }
}
