import Foundation

public struct PitchDetectorConfiguration: Sendable, Equatable {
    /// 偵測範圍 65–2,100 Hz 往外各放寬半個半音，讓邊界音偏低／偏高時仍有讀數。
    public static let defaultAcceptedRange: ClosedRange<Double> = (65 * pow(2, -1.0 / 24))...(2100 * pow(2, 1.0 / 24))

    public var sampleRate: Double
    /// 分析窗長（樣本數）。最大可偵測週期為窗長的一半。
    public var windowSize: Int
    /// 超出此範圍的估計值視為無音高。
    public var acceptedRange: ClosedRange<Double>
    /// MPM 的 k：選第一個 ≥ k × 最高峰的 key maximum。
    public var peakThreshold: Double
    /// NSDF 峰值低於此值視為沒有明顯音高。
    public var clarityThreshold: Double
    /// 輸入 RMS 低於此值（dBFS）視為靜音。
    public var levelGateDB: Double
    /// 諧波擬合精修使用的最多諧波數；0 表示只用 MPM 的拋物線插值結果。
    public var maxRefinementHarmonics: Int

    public init(
        sampleRate: Double,
        windowSize: Int = 2048,
        acceptedRange: ClosedRange<Double> = Self.defaultAcceptedRange,
        peakThreshold: Double = 0.9,
        clarityThreshold: Double = 0.85,
        levelGateDB: Double = -50,
        maxRefinementHarmonics: Int = 16
    ) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.acceptedRange = acceptedRange
        self.peakThreshold = peakThreshold
        self.clarityThreshold = clarityThreshold
        self.levelGateDB = levelGateDB
        self.maxRefinementHarmonics = maxRefinementHarmonics
    }
}

public struct PitchEstimate: Sendable, Equatable {
    public let frequency: Double
    /// 所選峰值的 NSDF 值（0–1），越接近 1 表示週期性越明確。
    public let clarity: Double
    /// 去除直流後的 RMS 電平（dBFS）。
    public let levelDB: Double

    public init(frequency: Double, clarity: Double, levelDB: Double) {
        self.frequency = frequency
        self.clarity = clarity
        self.levelDB = levelDB
    }
}
