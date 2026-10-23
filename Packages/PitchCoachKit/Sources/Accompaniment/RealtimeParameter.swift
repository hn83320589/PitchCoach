import os

/// 主執行緒寫入、音訊 IO 執行緒讀取的參數。
///
/// 讀取端只用 trylock：拿不到鎖時沿用上次讀到的值，永遠不會阻塞 IO 執行緒。
/// `readForRealtime` 只能由同一個（IO）執行緒呼叫。
public final class RealtimeParameter<Value: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Value>
    private var lastRead: Value

    public init(_ initialValue: Value) {
        lock = OSAllocatedUnfairLock(initialState: initialValue)
        lastRead = initialValue
    }

    public func set(_ value: Value) {
        lock.withLockUnchecked { $0 = value }
    }

    public var value: Value {
        lock.withLockUnchecked { $0 }
    }

    public func readForRealtime() -> Value {
        if let current = lock.withLockIfAvailableUnchecked({ $0 }) {
            lastRead = current
        }
        return lastRead
    }

    func withLockHeldForTesting<T>(_ body: () -> T) -> T {
        lock.withLockUnchecked { _ in body() }
    }
}
