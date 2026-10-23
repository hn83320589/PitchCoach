import SwiftUI

/// 橫向偏差表：±50 cents，中間綠色區為容許範圍（長音 ±10、音階 ±15）。
struct CentsMeter: View {
    let cents: Double?
    let tolerance: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let toleranceWidth = width * tolerance / 100
            ZStack {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(TunerPalette.inTune.opacity(0.35))
                    .frame(width: toleranceWidth)
                Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 1)
                if let cents {
                    Circle()
                        .fill(color(for: cents))
                        .frame(width: 22, height: 22)
                        .offset(x: width / 2 * max(-1, min(1, cents / 50)))
                        .animation(.interpolatingSpring(stiffness: 220, damping: 26), value: cents)
                }
            }
        }
        .frame(height: 22)
        .overlay(alignment: .bottom) {
            HStack {
                Text("-50")
                Spacer()
                Text("0")
                Spacer()
                Text("+50")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .offset(y: 20)
        }
        .padding(.bottom, 20)
        .accessibilityElement()
        .accessibilityLabel(cents.map { String(format: "偏差 %+.0f 音分", $0) } ?? "沒有偵測到音高")
    }

    private func color(for cents: Double) -> Color {
        abs(cents) <= tolerance ? TunerPalette.inTune : TunerPalette.color(forCents: cents)
    }
}

/// 帶正負號、一位小數的 cents 文字；四捨五入為 0 時不帶負號。
func formattedCents(_ cents: Double?) -> String {
    guard let cents else { return "—" }
    let rounded = (cents * 10).rounded() / 10
    return rounded == 0 ? "0.0 ¢" : String(format: "%+.1f ¢", rounded)
}

/// 練習被中斷的標籤。
struct InterruptedBadge: View {
    let reason: String

    var body: some View {
        Label("中斷：\(reason)", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }
}
