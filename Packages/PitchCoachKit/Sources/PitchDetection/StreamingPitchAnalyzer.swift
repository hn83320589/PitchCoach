import Accelerate
import Foundation

/// 一次分析的結果。`time` 為分析窗結束（最新樣本之後）的時間點，以串流起點為 0。
public struct PitchFrame: Sendable, Equatable {
    public let time: Duration
    /// 沒有明確音高時為 nil。
    public let estimate: PitchEstimate?
    /// 最近一個 hop（分析窗最後 hopSize 個樣本）的 RMS 電平（dBFS），無論有沒有音高都有值；
    /// 歌唱模式以它偵測同音重複時的重新咬字。
    public let levelDB: Double

    public init(time: Duration, estimate: PitchEstimate?, levelDB: Double = -.infinity) {
        self.time = time
        self.estimate = estimate
        self.levelDB = levelDB
    }

    public var frequency: Double? { estimate?.frequency }
}

/// 把任意長度的連續樣本切成固定窗長與 hop 的分析 frame。
///
/// 預先配置緩衝區，`process` 不配置記憶體，可在音訊 IO 執行緒呼叫。
/// 同一個實例不可同時被多個執行緒使用。
public final class StreamingPitchAnalyzer {
    public let hopSize: Int
    public var windowSize: Int { detector.windowSize }
    public var sampleRate: Double { detector.configuration.sampleRate }

    private let detector: MPMPitchDetector
    /// 容量為兩個窗長的線性緩衝；寫滿時把最近一個窗長的樣本搬到開頭。
    private let buffer: UnsafeMutablePointer<Float>
    private var count = 0
    private var samplesUntilNextFrame: Int
    private var expectedPosition: Int64?

    public init(configuration: PitchDetectorConfiguration, hopSize: Int = 512) {
        precondition(hopSize > 0 && hopSize <= configuration.windowSize, "hopSize 必須介於 1 與 windowSize 之間")
        self.hopSize = hopSize
        detector = MPMPitchDetector(configuration: configuration)
        buffer = .allocate(capacity: 2 * configuration.windowSize)
        samplesUntilNextFrame = configuration.windowSize
    }

    deinit {
        buffer.deallocate()
    }

    /// `samplePosition` 為第一個樣本在串流中的絕對位置；與上次結尾不連續時自動重設。
    public func process(_ samples: UnsafeBufferPointer<Float>, startingAt samplePosition: Int64, emit: (PitchFrame) -> Void) {
        if let expected = expectedPosition, expected != samplePosition {
            reset()
        }
        var offset = 0
        while offset < samples.count {
            let take = min(samplesUntilNextFrame, samples.count - offset)
            append(samples.baseAddress! + offset, count: take)
            offset += take
            samplesUntilNextFrame -= take
            if samplesUntilNextFrame == 0 {
                let window = UnsafeBufferPointer(start: buffer + count - windowSize, count: windowSize)
                let windowEnd = samplePosition + Int64(offset)
                var rms: Float = 0
                vDSP_rmsqv(buffer + count - hopSize, 1, &rms, vDSP_Length(hopSize))
                emit(PitchFrame(time: duration(ofSamples: windowEnd), estimate: detector.detect(window),
                                levelDB: Double(20 * log10(max(rms, 1e-9)))))
                samplesUntilNextFrame = hopSize
            }
        }
        expectedPosition = samplePosition + Int64(samples.count)
    }

    public func reset() {
        count = 0
        samplesUntilNextFrame = windowSize
        expectedPosition = nil
    }

    private func append(_ source: UnsafePointer<Float>, count newCount: Int) {
        if count + newCount > 2 * windowSize {
            buffer.update(from: buffer + count - windowSize, count: windowSize)
            count = windowSize
        }
        (buffer + count).update(from: source, count: newCount)
        count += newCount
    }

    /// 取樣率為整數時以整數運算換算，時間戳精確（練習判定的 300 ms 邊界比較依賴這點）。
    private func duration(ofSamples samples: Int64) -> Duration {
        guard sampleRate == sampleRate.rounded() else {
            return .seconds(Double(samples) / sampleRate)
        }
        let rate = Int64(sampleRate)
        let remainder = samples % rate
        let (attoseconds, _) = rate.dividingFullWidth(remainder.multipliedFullWidth(by: 1_000_000_000_000_000_000))
        return Duration(secondsComponent: samples / rate, attosecondsComponent: attoseconds)
    }
}
