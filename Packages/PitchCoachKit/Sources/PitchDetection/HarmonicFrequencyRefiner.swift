import Accelerate
import Foundation

/// 以諧波加權最小平方擬合精修基頻（MPM 只負責選對八度）。
///
/// 模型：x_j ≈ c + Σₕ aₕ·cos(hωj′) + bₕ·sin(hωj′)，j′ = j − (W−1)/2（以窗中心為原點），h = 1…H。
/// 固定 ω 時係數可用加權線性最小平方求得；投影能量 J(ω) = pᵀG⁻¹p 的最大值即為頻率估計。
/// 對 H 以內的週期訊號，真實頻率處殘差為 0，因此沒有拋物線插值的偏差；
/// 在白噪音下接近最大概似估計，抗噪能力遠優於只看單一 lag 的 NSDF。
///
/// 權重用 sine 窗 w(j′) = cos(πj′/W)：
/// - 矩形權重時，H 以外的泛音（例如弓弦的鋸齒波）在低頻會洩漏進模型，65 Hz 偏差可達 9 cents
/// - Hann 權重洩漏最小，但有效窗長較短，20 dB SNR 的誤差逼近 3 cents
/// - sine 窗旁瓣以 1/k² 衰減、雜訊等效頻寬 1.23，兩者兼顧（實驗數據見 README）
///
/// 以窗中心為原點且權重對稱時，cos 欄與 sin 欄正交，Gram 矩陣分成兩塊，元素都可由
/// Dirichlet kernel 的封閉解查表得到，每次評估只需 O(W·H) 的向量內積。
/// 所有緩衝區在 init 配置，`refine` 不配置記憶體。
final class HarmonicFrequencyRefiner {
    private let windowSize: Int
    private let sampleRate: Double
    private let maxHarmonics: Int

    private let centeredIndex: UnsafeMutablePointer<Double>    // j′
    private let weights: UnsafeMutablePointer<Double>          // cos(πj′/W)
    private let weightedSamples: UnsafeMutablePointer<Double>
    private let kernelTable: UnsafeMutablePointer<Double>      // Kw(kω)，k = 0…2H
    private let phase: UnsafeMutablePointer<Double>
    private let baseReal: UnsafeMutablePointer<Double>         // cos(ωj′)
    private let baseImag: UnsafeMutablePointer<Double>         // sin(ωj′)
    private let phasorReal: (UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>)
    private let phasorImag: (UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>)

    private let cosProjection: UnsafeMutablePointer<Double>    // [c, C₁…C_H]
    private let sinProjection: UnsafeMutablePointer<Double>    // [S₁…S_H]
    private let gram: UnsafeMutablePointer<Double>
    private let solution: UnsafeMutablePointer<Double>
    private var sampleSum = 0.0

    init(windowSize: Int, sampleRate: Double, maxHarmonics: Int) {
        self.windowSize = windowSize
        self.sampleRate = sampleRate
        self.maxHarmonics = maxHarmonics

        centeredIndex = .allocate(capacity: windowSize)
        var start = -Double(windowSize - 1) / 2
        var one = 1.0
        vDSP_vrampD(&start, &one, centeredIndex, 1, vDSP_Length(windowSize))
        weights = .allocate(capacity: windowSize)
        for j in 0..<windowSize {
            weights[j] = cos(.pi * centeredIndex[j] / Double(windowSize))
        }

        weightedSamples = .allocate(capacity: windowSize)
        kernelTable = .allocate(capacity: 2 * maxHarmonics + 1)
        phase = .allocate(capacity: windowSize)
        baseReal = .allocate(capacity: windowSize)
        baseImag = .allocate(capacity: windowSize)
        phasorReal = (.allocate(capacity: windowSize), .allocate(capacity: windowSize))
        phasorImag = (.allocate(capacity: windowSize), .allocate(capacity: windowSize))

        cosProjection = .allocate(capacity: maxHarmonics + 1)
        sinProjection = .allocate(capacity: maxHarmonics)
        gram = .allocate(capacity: (maxHarmonics + 1) * (maxHarmonics + 1))
        solution = .allocate(capacity: maxHarmonics + 1)
    }

    deinit {
        for buffer in [centeredIndex, weights, weightedSamples, kernelTable, phase, baseReal, baseImag,
                       phasorReal.0, phasorReal.1, phasorImag.0, phasorImag.1,
                       cosProjection, sinProjection, gram, solution] {
            buffer.deallocate()
        }
    }

    /// 從 `coarseFrequency` 附近找 J(ω) 的最大值。`samples` 長度為 `windowSize`。
    ///
    /// 分兩階段，每階段的搜尋半寬都限制在該階段最高諧波主瓣半寬的 40% 以內，確保不會跳到旁瓣：
    /// 1. 粗估誤差可達約 10 cents，只用主瓣半寬仍 ≥ 25 cents 的諧波。低頻時主瓣很寬，
    ///    可直接擬合全部諧波（強泛音被正確建模，不會把峰值拉偏）；高頻時只剩前幾個諧波，
    ///    但此時窗內週期數多、各諧波近乎正交，未建模的諧波幾乎不洩漏。
    /// 2. 擬合全部諧波，在階段 1 結果附近小範圍精修。
    func refine(_ samples: UnsafePointer<Double>, coarseFrequency: Double) -> Double {
        vDSP_vmulD(samples, 1, weights, 1, weightedSamples, 1, vDSP_Length(windowSize))
        vDSP_sveD(weightedSamples, 1, &sampleSum, vDSP_Length(windowSize))
        let weighted = UnsafePointer(weightedSamples)

        let harmonics = max(1, min(maxHarmonics, Int(0.45 * sampleRate / coarseFrequency)))
        var firstStageHarmonics = 1
        while firstStageHarmonics < harmonics,
              lobeHalfWidthCents(coarseFrequency, harmonic: firstStageHarmonics + 1) >= 25 {
            firstStageHarmonics += 1
        }

        var estimate = maximize(weighted, around: coarseFrequency, harmonics: firstStageHarmonics,
                                halfWidthCents: min(12, 0.4 * lobeHalfWidthCents(coarseFrequency, harmonic: firstStageHarmonics)))
        if harmonics > firstStageHarmonics {
            estimate = maximize(weighted, around: estimate, harmonics: harmonics,
                                halfWidthCents: min(4, 0.4 * lobeHalfWidthCents(estimate, harmonic: harmonics)))
        }
        return estimate
    }

    /// 第 h 諧波主瓣（到第一個零點）的半寬換算成基頻的 cents。sine 窗主瓣半寬為 1.5 個 bin。
    private func lobeHalfWidthCents(_ frequency: Double, harmonic: Int) -> Double {
        let lobeWidth = 1.5 * sampleRate / Double(windowSize)
        return 1200 * log2(1 + lobeWidth / (Double(harmonic) * frequency))
    }

    private func maximize(_ samples: UnsafePointer<Double>, around center: Double, harmonics: Int, halfWidthCents: Double) -> Double {
        let best = brentMinimize(lower: -halfWidthCents, upper: halfWidthCents, tolerance: 0.002) { cents in
            -energy(samples, frequency: center * pow(2, cents / 1200), harmonics: harmonics)
        }
        return center * pow(2, best / 1200)
    }

    /// 投影能量 J(ω) = p_cᵀ G_c⁻¹ p_c + p_sᵀ G_s⁻¹ p_s（加權內積）。
    private func energy(_ samples: UnsafePointer<Double>, frequency: Double, harmonics: Int) -> Double {
        let omega = 2 * .pi * frequency / sampleRate
        project(samples, omega: omega, harmonics: harmonics)
        for k in 0...(2 * harmonics) {
            kernelTable[k] = weightedKernel(Double(k) * omega)
        }

        // cos 區塊：[1, C₁…C_H]；C_a·C_b = ½[Kw((a−b)ω) + Kw((a+b)ω)]，1·C_a = Kw(aω)
        let nc = harmonics + 1
        for row in 0..<nc {
            for col in 0...row {
                gram[row * nc + col] = col == 0
                    ? kernelTable[row]
                    : 0.5 * (kernelTable[row - col] + kernelTable[row + col])
            }
        }
        var total = quadraticForm(size: nc, rhs: cosProjection)

        // sin 區塊：[S₁…S_H]；S_a·S_b = ½[Kw((a−b)ω) − Kw((a+b)ω)]
        let ns = harmonics
        for row in 0..<ns {
            for col in 0...row {
                let a = row + 1, b = col + 1
                gram[row * ns + col] = 0.5 * (kernelTable[a - b] - kernelTable[a + b])
            }
        }
        total += quadraticForm(size: ns, rhs: sinProjection)
        return total
    }

    /// Kw(θ) = Σⱼ′ cos(πj′/W)·cos(θj′) = ½[K(θ + π/W) + K(θ − π/W)]。
    private func weightedKernel(_ theta: Double) -> Double {
        let phi = Double.pi / Double(windowSize)
        return 0.5 * (kernel(theta + phi) + kernel(theta - phi))
    }

    /// Σⱼ′ e^{iθj′}，j′ 對稱於 0 → 實數 sin(Wθ/2) / sin(θ/2)。
    private func kernel(_ theta: Double) -> Double {
        let half = sin(theta / 2)
        if abs(half) < 1e-12 { return Double(windowSize) }
        return sin(Double(windowSize) * theta / 2) / half
    }

    /// 計算 Σ x_j·cos(hωj′) 與 Σ x_j·sin(hωj′)，h = 1…H。
    /// 基底相量 e^{iωj′} 以 vvsincos 算一次，其餘諧波以逐元素複數乘法遞推。
    private func project(_ samples: UnsafePointer<Double>, omega: Double, harmonics: Int) {
        let n = vDSP_Length(windowSize)
        var count = Int32(windowSize)
        var w = omega
        vDSP_vsmulD(centeredIndex, 1, &w, phase, 1, n)
        vvsincos(baseImag, baseReal, phase, &count)

        cosProjection[0] = sampleSum
        var current = DSPDoubleSplitComplex(realp: baseReal, imagp: baseImag)
        var base = current
        var useFirst = true
        for h in 1...harmonics {
            if h > 1 {
                var next = useFirst
                    ? DSPDoubleSplitComplex(realp: phasorReal.0, imagp: phasorImag.0)
                    : DSPDoubleSplitComplex(realp: phasorReal.1, imagp: phasorImag.1)
                vDSP_zvmulD(&current, 1, &base, 1, &next, 1, n, 1)
                current = next
                useFirst.toggle()
            }
            vDSP_dotprD(samples, 1, current.realp, 1, &cosProjection[h], n)
            vDSP_dotprD(samples, 1, current.imagp, 1, &sinProjection[h - 1], n)
        }
    }

    /// 以 Cholesky 分解（下三角存在 `gram`）計算 rhsᵀ G⁻¹ rhs = ‖L⁻¹ rhs‖²。
    private func quadraticForm(size n: Int, rhs: UnsafeMutablePointer<Double>) -> Double {
        for i in 0..<n {
            for j in 0...i {
                var sum = gram[i * n + j]
                for k in 0..<j { sum -= gram[i * n + k] * gram[j * n + k] }
                if i == j {
                    guard sum > 1e-12 else { return 0 }
                    gram[i * n + i] = sqrt(sum)
                } else {
                    gram[i * n + j] = sum / gram[j * n + j]
                }
            }
        }
        var result = 0.0
        for i in 0..<n {
            var sum = rhs[i]
            for k in 0..<i { sum -= gram[i * n + k] * solution[k] }
            solution[i] = sum / gram[i * n + i]
            result += solution[i] * solution[i]
        }
        return result
    }
}

/// Brent 法（黃金分割＋拋物線插值）求區間內的最小值，不需導數。
/// 參考 R. P. Brent, *Algorithms for Minimization without Derivatives*, 1973, 第 5 章。
func brentMinimize(lower: Double, upper: Double, tolerance: Double, _ f: (Double) -> Double) -> Double {
    let goldenSection = 0.5 * (3 - sqrt(5.0))
    var a = lower, b = upper
    var x = a + goldenSection * (b - a)
    var w = x, v = x
    var fx = f(x)
    var fw = fx, fv = fx
    var d = 0.0, e = 0.0

    while true {
        let midpoint = 0.5 * (a + b)
        let tol1 = tolerance
        let tol2 = 2 * tol1
        if abs(x - midpoint) <= tol2 - 0.5 * (b - a) { return x }

        var useGolden = true
        if abs(e) > tol1 {
            var r = (x - w) * (fx - fv)
            var q = (x - v) * (fx - fw)
            var p = (x - v) * q - (x - w) * r
            q = 2 * (q - r)
            if q > 0 { p = -p } else { q = -q }
            r = e
            e = d
            if abs(p) < abs(0.5 * q * r), p > q * (a - x), p < q * (b - x) {
                d = p / q
                let u = x + d
                if u - a < tol2 || b - u < tol2 { d = x < midpoint ? tol1 : -tol1 }
                useGolden = false
            }
        }
        if useGolden {
            e = (x < midpoint ? b : a) - x
            d = goldenSection * e
        }

        let u = abs(d) >= tol1 ? x + d : x + (d > 0 ? tol1 : -tol1)
        let fu = f(u)
        if fu <= fx {
            if u < x { b = x } else { a = x }
            v = w; fv = fw
            w = x; fw = fx
            x = u; fx = fu
        } else {
            if u < x { a = u } else { b = u }
            if fu <= fw || w == x {
                v = w; fv = fw
                w = u; fw = fu
            } else if fu <= fv || v == x || v == w {
                v = u; fv = fu
            }
        }
    }
}
