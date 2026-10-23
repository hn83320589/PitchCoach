/// 最近 N 筆延遲樣本（秒）的百分位數。
struct LatencyStatistics {
    private let capacity: Int
    private var samples: [Double] = []
    private var nextIndex = 0

    init(capacity: Int = 600) {
        self.capacity = capacity
    }

    var count: Int { samples.count }

    mutating func record(_ seconds: Double) {
        if samples.count < capacity {
            samples.append(seconds)
        } else {
            samples[nextIndex] = seconds
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    /// 最近排名法（nearest-rank）的百分位數。
    func percentile(_ p: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
}
