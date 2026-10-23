import Foundation

/// 邊界比較的容許誤差：讓剛好落在 ±10、±15 cents 上的值不會因浮點往返誤差被判為範圍外。
let boundaryEpsilon = 1e-9

extension Duration {
    var timeInterval: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}

/// 以 Welford 演算法累計平均與母體變異數。
struct RunningStatistics: Equatable, Sendable {
    private(set) var count = 0
    private(set) var mean = 0.0
    private var sumOfSquaredDeviations = 0.0

    mutating func add(_ value: Double) {
        count += 1
        let delta = value - mean
        mean += delta / Double(count)
        sumOfSquaredDeviations += delta * (value - mean)
    }

    var meanIfAny: Double? { count > 0 ? mean : nil }

    /// 母體標準差（÷N）。
    var populationStandardDeviation: Double? {
        count > 0 ? (sumOfSquaredDeviations / Double(count)).squareRoot() : nil
    }
}
