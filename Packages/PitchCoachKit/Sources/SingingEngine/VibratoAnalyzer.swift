import Foundation

public struct VibratoEstimate: Equatable, Sendable {
    /// 顫音速度（Hz）。
    public let rate: Double
    /// 顫音幅度（單邊，cents），已補償分析窗的平均效應。
    public let depthCents: Double
    /// 中心音高（cents，與輸入同一基準）。
    public let centerCents: Double
}

/// 顫音偵測（docs/SINGING_MODE.md §5）。
///
/// 對 cents 序列擬合 c(τ) ≈ α + βτ + a·cos(2πfτ) + b·sin(2πfτ)（τ 以序列中點為原點），
/// 在 3–9 Hz 搜尋殘差最小的 f。中心音高取 α（趨勢線在中點的值），不用中位數：
/// 顫音只涵蓋非整數個週期時，中位數會偏向多出來的半個週期。
public enum VibratoAnalyzer {
    public static let rateRange = 3.0...9.0
    /// 擬合需解釋的最少變異比例（相對只擬合直線的殘差）。
    public static let minimumExplainedVariance = 0.5
    public static let minimumDepthCents = 15.0
    public static let minimumCycles = 1.5

    /// - Parameter compensation: 顫音速度 → 分析窗的振幅響應，用來還原被平均掉的幅度。
    public static func analyze(times: [Double], cents: [Double], compensation: (Double) -> Double) -> VibratoEstimate? {
        guard times.count >= 12, times.count == cents.count else { return nil }
        let middle = (times.first! + times.last!) / 2
        let tau = times.map { $0 - middle }
        let span = times.last! - times.first!

        guard let baseline = fit(tau: tau, values: cents, frequency: nil) else { return nil }
        guard baseline.residual > 1e-9 else { return nil }

        // 粗搜尋（0.05 Hz 間距）後以黃金分割精修
        var bestFrequency = rateRange.lowerBound
        var bestResidual = Double.infinity
        for frequency in stride(from: rateRange.lowerBound, through: rateRange.upperBound, by: 0.05) {
            if let result = fit(tau: tau, values: cents, frequency: frequency), result.residual < bestResidual {
                bestResidual = result.residual
                bestFrequency = frequency
            }
        }
        bestFrequency = goldenSectionMinimum(lower: bestFrequency - 0.05, upper: bestFrequency + 0.05) {
            fit(tau: tau, values: cents, frequency: $0)?.residual ?? .infinity
        }
        guard let model = fit(tau: tau, values: cents, frequency: bestFrequency) else { return nil }

        let explained = 1 - model.residual / baseline.residual
        let depth = hypot(model.coefficients[2], model.coefficients[3]) / compensation(bestFrequency)
        guard explained >= minimumExplainedVariance, depth >= minimumDepthCents,
              span * bestFrequency >= minimumCycles else { return nil }
        return VibratoEstimate(rate: bestFrequency, depthCents: depth, centerCents: model.coefficients[0])
    }

    /// 偵測器分析窗對 f Hz 顫音的振幅響應。
    ///
    /// 以最小平方估計頻率，近似於對瞬時頻率做加權平均；權重為
    /// k(t) = ∫_{|t|}^{W/2} u·w(u) du（相位對時間做線性迴歸的斜率核），w 為偵測器的 sine 窗。
    public static func windowGain(windowDuration: Double) -> @Sendable (Double) -> Double {
        let a = Double.pi / windowDuration
        func antiderivative(_ u: Double) -> Double { cos(a * u) / (a * a) + u * sin(a * u) / a }
        let half = windowDuration / 2
        let count = 400
        let times = (0..<count).map { -half + (Double($0) + 0.5) * windowDuration / Double(count) }
        let kernel = times.map { antiderivative(half) - antiderivative(abs($0)) }
        let total = kernel.reduce(0, +)
        return { frequency in
            abs(zip(times, kernel).reduce(0) { $0 + $1.1 * cos(2 * .pi * frequency * $1.0) }) / total
        }
    }

    // MARK: - 最小平方

    private struct Fit {
        let coefficients: [Double]
        let residual: Double
    }

    /// 以正規方程解 [1, τ, cos, sin]（frequency 為 nil 時只擬合直線）的最小平方。
    private static func fit(tau: [Double], values: [Double], frequency: Double?) -> Fit? {
        let columns: [(Double) -> Double] = frequency.map { f in
            [{ _ in 1 }, { $0 }, { cos(2 * .pi * f * $0) }, { sin(2 * .pi * f * $0) }]
        } ?? [{ _ in 1 }, { $0 }]
        let n = columns.count
        var normal = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        let rows = tau.map { t in columns.map { $0(t) } }
        for (row, value) in zip(rows, values) {
            for i in 0..<n {
                for j in 0..<n { normal[i][j] += row[i] * row[j] }
                normal[i][n] += row[i] * value
            }
        }
        guard let coefficients = solve(normal) else { return nil }
        let residual = zip(rows, values).reduce(0.0) { sum, pair in
            let predicted = zip(pair.0, coefficients).reduce(0) { $0 + $1.0 * $1.1 }
            return sum + (pair.1 - predicted) * (pair.1 - predicted)
        }
        return Fit(coefficients: coefficients, residual: residual)
    }

    /// 部分選主元的高斯消去法；矩陣奇異時回傳 nil。
    private static func solve(_ augmented: [[Double]]) -> [Double]? {
        var m = augmented
        let n = m.count
        for column in 0..<n {
            guard let pivot = (column..<n).max(by: { abs(m[$0][column]) < abs(m[$1][column]) }),
                  abs(m[pivot][column]) > 1e-12 else { return nil }
            m.swapAt(column, pivot)
            for row in (column + 1)..<n {
                let factor = m[row][column] / m[column][column]
                for k in column...n { m[row][k] -= factor * m[column][k] }
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            let sum = ((row + 1)..<n).reduce(m[row][n]) { $0 - m[row][$1] * x[$1] }
            x[row] = sum / m[row][row]
        }
        return x
    }

    private static func goldenSectionMinimum(lower: Double, upper: Double, _ f: (Double) -> Double) -> Double {
        let ratio = (sqrt(5.0) - 1) / 2
        var low = lower, high = upper
        var x1 = high - ratio * (high - low), x2 = low + ratio * (high - low)
        var f1 = f(x1), f2 = f(x2)
        while high - low > 1e-4 {
            if f1 < f2 {
                high = x2; x2 = x1; f2 = f1
                x1 = high - ratio * (high - low); f1 = f(x1)
            } else {
                low = x1; x1 = x2; f1 = f2
                x2 = low + ratio * (high - low); f2 = f(x2)
            }
        }
        return (low + high) / 2
    }
}
