import SwiftUI

/// ±50 cents 的半圓指針表，±10 cents 為綠色區。
struct TunerGauge: View {
    /// nil 表示沒有讀數，指針隱藏。
    let cents: Double?

    private let sweep: Double = 70   // ±50 cents 對應 ±70°

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.92)
            let radius = min(size.width / 2, size.height * 0.92) * 0.92

            ZStack {
                Canvas { context, _ in
                    drawZones(in: &context, center: center, radius: radius)
                    drawTicks(in: &context, center: center, radius: radius)
                }
                Needle(angle: .degrees(angle), center: center, length: radius * 0.92)
                    .stroke(needleColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .opacity(cents == nil ? 0 : 1)
                    .animation(.interpolatingSpring(stiffness: 220, damping: 26), value: angle)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 14, height: 14)
                    .position(center)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var angle: Double {
        guard let cents else { return 0 }
        return max(-50, min(50, cents)) / 50 * sweep
    }

    private var needleColor: Color {
        TunerPalette.color(forCents: cents)
    }

    private var accessibilityText: String {
        guard let cents else { return "沒有偵測到音高" }
        return String(format: "偏差 %+.0f 音分", cents)
    }

    private func point(_ center: CGPoint, _ radius: Double, _ degrees: Double) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private func drawZones(in context: inout GraphicsContext, center: CGPoint, radius: Double) {
        func arc(from: Double, to: Double, color: Color, width: Double) {
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
        }
        arc(from: -sweep, to: sweep, color: Color.secondary.opacity(0.18), width: 14)
        let inTune = 10 / 50 * sweep
        arc(from: -inTune, to: inTune, color: TunerPalette.inTune.opacity(0.85), width: 14)
    }

    private func drawTicks(in context: inout GraphicsContext, center: CGPoint, radius: Double) {
        for cents in stride(from: -50, through: 50, by: 5) {
            let degrees = Double(cents) / 50 * sweep
            let major = cents % 10 == 0
            var tick = Path()
            tick.move(to: point(center, radius - 12, degrees))
            tick.addLine(to: point(center, radius - (major ? 30 : 20), degrees))
            context.stroke(tick, with: .color(.secondary.opacity(major ? 0.9 : 0.5)), lineWidth: major ? 2 : 1)

            if cents % 25 == 0 {
                let label = cents == 0 ? "0" : String(format: "%+d", cents)
                context.draw(Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                             at: point(center, radius - 46, degrees))
            }
        }
    }
}

private struct Needle: Shape {
    var angle: Angle
    let center: CGPoint
    let length: Double

    var animatableData: Double {
        get { angle.degrees }
        set { angle = .degrees(newValue) }
    }

    func path(in rect: CGRect) -> Path {
        let radians = (angle.degrees - 90) * .pi / 180
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + length * cos(radians), y: center.y + length * sin(radians)))
        return path
    }
}

enum TunerPalette {
    static let inTune = Color.green
    static let close = Color.orange
    static let off = Color.red

    static func color(forCents cents: Double?) -> Color {
        guard let cents else { return .secondary }
        switch abs(cents) {
        case ...10: return inTune
        case ...25: return close
        default: return off
        }
    }
}
