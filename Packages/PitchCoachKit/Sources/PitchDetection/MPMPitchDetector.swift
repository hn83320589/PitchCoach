import Accelerate
import Foundation

/// McLeod Pitch Method（McLeod & Wyvill, 2005）基頻偵測。
///
/// 1. 以 FFT 計算自相關 r(τ)，以平方前綴和計算 m(τ) = Σ(x²ⱼ + x²ⱼ₊τ)
/// 2. 正規化平方差函數 n(τ) = 2r(τ) / m(τ)，純正弦在真實週期處恰為 1
/// 3. 每個正值區間取一個 key maximum，選「第一個」≥ k × 最高峰者（防八度錯誤）
/// 4. 拋物線插值求次樣本週期，得到八度正確的粗估
/// 5. 以 `HarmonicFrequencyRefiner` 的諧波最小平方擬合精修頻率（精度與抗噪）
///
/// 所有緩衝區在 init 時配置，`detect` 不配置記憶體，可在音訊 IO 執行緒呼叫。
/// 同一個實例不可同時被多個執行緒使用。
public final class MPMPitchDetector {
    public let configuration: PitchDetectorConfiguration
    public var windowSize: Int { configuration.windowSize }

    private let maxLag: Int
    private let fftSize: Int
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetupD
    private let refiner: HarmonicFrequencyRefiner?

    private let window: UnsafeMutablePointer<Double>
    private let padded: UnsafeMutablePointer<Double>
    private let splitReal: UnsafeMutablePointer<Double>
    private let splitImag: UnsafeMutablePointer<Double>
    private let autocorrelation: UnsafeMutablePointer<Double>
    private let squarePrefix: UnsafeMutablePointer<Double>
    private let nsdf: UnsafeMutablePointer<Double>
    private let keyMaxima: UnsafeMutablePointer<Int>

    public init(configuration: PitchDetectorConfiguration) {
        precondition(configuration.windowSize >= 64, "windowSize 太小")
        self.configuration = configuration
        let windowSize = configuration.windowSize
        maxLag = windowSize / 2

        // 線性（非循環）自相關需要 fftSize ≥ windowSize + maxLag
        var log2n = 0
        while (1 << log2n) < windowSize + maxLag { log2n += 1 }
        fftSize = 1 << log2n
        log2FFTSize = vDSP_Length(log2n)
        guard let setup = vDSP_create_fftsetupD(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            fatalError("無法建立 vDSP FFT setup（log2n = \(log2n)）")
        }
        fftSetup = setup
        refiner = configuration.maxRefinementHarmonics > 0
            ? HarmonicFrequencyRefiner(windowSize: windowSize, sampleRate: configuration.sampleRate,
                                       maxHarmonics: configuration.maxRefinementHarmonics)
            : nil

        window = .allocate(capacity: windowSize)
        padded = .allocate(capacity: fftSize)
        splitReal = .allocate(capacity: fftSize / 2)
        splitImag = .allocate(capacity: fftSize / 2)
        autocorrelation = .allocate(capacity: fftSize)
        squarePrefix = .allocate(capacity: windowSize + 1)
        nsdf = .allocate(capacity: maxLag + 1)
        keyMaxima = .allocate(capacity: maxLag)
    }

    deinit {
        vDSP_destroy_fftsetupD(fftSetup)
        window.deallocate()
        padded.deallocate()
        splitReal.deallocate()
        splitImag.deallocate()
        autocorrelation.deallocate()
        squarePrefix.deallocate()
        nsdf.deallocate()
        keyMaxima.deallocate()
    }

    public func detect(_ samples: [Float]) -> PitchEstimate? {
        samples.withUnsafeBufferPointer { detect($0) }
    }

    /// `samples.count` 必須等於 `windowSize`。沒有明確音高時回傳 nil。
    public func detect(_ samples: UnsafeBufferPointer<Float>) -> PitchEstimate? {
        precondition(samples.count == windowSize, "樣本數 \(samples.count) ≠ windowSize \(windowSize)")
        let n = vDSP_Length(windowSize)

        // 去直流
        vDSP_vspdp(samples.baseAddress!, 1, window, 1, n)
        var mean = 0.0
        vDSP_meanvD(window, 1, &mean, n)
        var negativeMean = -mean
        vDSP_vsaddD(window, 1, &negativeMean, window, 1, n)

        var energy = 0.0
        vDSP_svesqD(window, 1, &energy, n)
        guard energy > 0 else { return nil }
        let levelDB = 10 * log10(energy / Double(windowSize))
        guard levelDB >= configuration.levelGateDB else { return nil }

        computeNSDF(energy: energy)
        guard let (lag, clarity) = pickPeak(), clarity >= configuration.clarityThreshold else { return nil }

        let coarse = configuration.sampleRate / lag
        guard configuration.acceptedRange.contains(coarse) else { return nil }
        let frequency = refiner?.refine(window, coarseFrequency: coarse) ?? coarse
        guard configuration.acceptedRange.contains(frequency) else { return nil }
        return PitchEstimate(frequency: frequency, clarity: clarity, levelDB: levelDB)
    }

    private func computeNSDF(energy: Double) {
        let half = fftSize / 2

        // 自相關 = IFFT(|FFT(x)|²)
        padded.update(from: window, count: windowSize)
        (padded + windowSize).initialize(repeating: 0, count: fftSize - windowSize)
        var split = DSPDoubleSplitComplex(realp: splitReal, imagp: splitImag)
        padded.withMemoryRebound(to: DSPDoubleComplex.self, capacity: half) {
            vDSP_ctozD($0, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zripD(fftSetup, &split, 1, log2FFTSize, FFTDirection(kFFTDirection_Forward))
        // zrip 格式：realp[0] 為 DC、imagp[0] 為 Nyquist，需分開處理
        let dc = splitReal[0] * splitReal[0]
        let nyquist = splitImag[0] * splitImag[0]
        vDSP_zvmagsD(&split, 1, splitReal, 1, vDSP_Length(half))
        vDSP_vclrD(splitImag, 1, vDSP_Length(half))
        splitReal[0] = dc
        splitImag[0] = nyquist
        vDSP_fft_zripD(fftSetup, &split, 1, log2FFTSize, FFTDirection(kFFTDirection_Inverse))
        autocorrelation.withMemoryRebound(to: DSPDoubleComplex.self, capacity: half) {
            vDSP_ztocD(&split, 1, $0, 2, vDSP_Length(half))
        }
        // vDSP 的 FFT 縮放因子依格式而異；以 r(0) = Σx² 校正，不必記憶各種係數
        var scale = energy / autocorrelation[0]
        vDSP_vsmulD(autocorrelation, 1, &scale, autocorrelation, 1, vDSP_Length(maxLag + 1))

        squarePrefix[0] = 0
        for j in 0..<windowSize {
            squarePrefix[j + 1] = squarePrefix[j] + window[j] * window[j]
        }
        let total = squarePrefix[windowSize]
        for tau in 0...maxLag {
            let m = squarePrefix[windowSize - tau] + (total - squarePrefix[tau])
            nsdf[tau] = m > 0 ? 2 * autocorrelation[tau] / m : 0
        }
    }

    /// 回傳（次樣本週期, clarity）。
    private func pickPeak() -> (Double, Double)? {
        // 跳過 τ = 0 附近的主瓣
        var tau = 1
        while tau < maxLag, nsdf[tau] > 0 { tau += 1 }

        var count = 0
        var regionMax = -1
        while tau < maxLag {
            if nsdf[tau] > 0 {
                if regionMax < 0 || nsdf[tau] > nsdf[regionMax] { regionMax = tau }
            } else if regionMax >= 0 {
                keyMaxima[count] = regionMax
                count += 1
                regionMax = -1
            }
            tau += 1
        }
        // 最後一個未結束的正值區間：最大值不在邊界上才是真正的峰
        if regionMax >= 0, regionMax < maxLag - 1 {
            keyMaxima[count] = regionMax
            count += 1
        }
        guard count > 0 else { return nil }

        var highest = -Double.infinity
        for i in 0..<count {
            highest = max(highest, interpolate(at: keyMaxima[i]).value)
        }
        let threshold = configuration.peakThreshold * highest
        for i in 0..<count {
            let peak = interpolate(at: keyMaxima[i])
            if peak.value >= threshold {
                return (peak.lag, peak.value)
            }
        }
        return nil
    }

    private func interpolate(at index: Int) -> (lag: Double, value: Double) {
        let a = nsdf[index - 1], b = nsdf[index], c = nsdf[index + 1]
        let curvature = a - 2 * b + c
        guard curvature < 0 else { return (Double(index), b) }
        let offset = 0.5 * (a - c) / curvature
        return (Double(index) + offset, b - 0.25 * (a - c) * offset)
    }
}
