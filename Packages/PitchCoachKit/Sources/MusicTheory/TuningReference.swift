/// A4 的基準頻率。所有音名與 cents 的計算都以此為準。
public struct TuningReference: Sendable, Hashable {
    public static let allowedRange: ClosedRange<Double> = 415...466
    public static let `default` = TuningReference(uncheckedA4: 442)

    public let a4: Double

    public init(a4: Double) throws(TuningReferenceError) {
        guard Self.allowedRange.contains(a4) else {
            throw .outOfRange(a4)
        }
        self.a4 = a4
    }

    /// 超出範圍時夾到最近的邊界；NaN 時使用預設值。用於設定頁等一定要得到合法值的場合。
    public init(clamping a4: Double) {
        if a4.isNaN {
            self = .default
        } else {
            self.init(uncheckedA4: min(Self.allowedRange.upperBound, max(Self.allowedRange.lowerBound, a4)))
        }
    }

    private init(uncheckedA4 a4: Double) {
        self.a4 = a4
    }
}

public enum TuningReferenceError: Error, Equatable {
    case outOfRange(Double)
}
