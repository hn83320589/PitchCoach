import Charts
import SwiftUI

/// 長音的偏差曲線：x 為秒、y 為 cents，±10 cents 綠色帶；無音高的區間斷開。
struct DeviationCurveChart: View {
    let curve: [Double?]
    var interval: Double = 0.05
    var duration: Double = 10

    private struct Point: Identifiable {
        let id: Int
        let time: Double
        let cents: Double
        let segment: Int
    }

    private var points: [Point] {
        var segment = 0
        var result: [Point] = []
        for (index, value) in curve.enumerated() {
            guard let value else {
                segment += 1
                continue
            }
            result.append(Point(id: index, time: Double(index) * interval, cents: max(-50, min(50, value)), segment: segment))
        }
        return result
    }

    var body: some View {
        Chart {
            RectangleMark(xStart: .value("開始", 0), xEnd: .value("結束", duration),
                          yStart: .value("下限", -10), yEnd: .value("上限", 10))
                .foregroundStyle(TunerPalette.inTune.opacity(0.15))
            RuleMark(y: .value("準", 0))
                .foregroundStyle(.secondary.opacity(0.5))
            ForEach(points) { point in
                LineMark(x: .value("秒", point.time), y: .value("cents", point.cents),
                         series: .value("段", point.segment))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: 0...duration)
        .chartYScale(domain: -50...50)
        .chartXAxisLabel("秒")
        .chartYAxisLabel("cents")
        .chartYAxis {
            AxisMarks(values: [-50, -25, -10, 0, 10, 25, 50])
        }
        .accessibilityLabel("偏差曲線")
    }
}
