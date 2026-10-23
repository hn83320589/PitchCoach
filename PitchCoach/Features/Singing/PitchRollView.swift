import MusicTheory
import SingingEngine
import SwiftUI

/// KTV 音高條：橫軸為歌曲時間（「現在」固定在 30% 處），目標旋律為色塊，學生的音高為即時曲線。
struct PitchRollView: View {
    let run: SongRun
    let tolerance: Double

    private let visibleSeconds = 6.0
    private let nowFraction = 0.3

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // 必須讓 Canvas 的輸入隨 timeline.date 改變，否則 SwiftUI 視為內容未變而不重繪
                draw(in: &context, size: size, frameDate: timeline.date,
                     now: run.currentSongTime ?? -run.timeline.countIn.seconds)
            }
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("singing.pitchRoll")
        .accessibilityLabel("音高條")
    }

    private var pitchRange: ClosedRange<Double> {
        let pitches = run.timeline.notes.map { Double($0.pitch.midi) }
        return (pitches.min()! - 3)...(pitches.max()! + 3)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, frameDate: Date, now: Double) {
        let range = pitchRange
        let start = now - visibleSeconds * nowFraction
        func x(_ time: Double) -> Double { (time - start) / visibleSeconds * size.width }
        func y(_ midi: Double) -> Double { size.height * (1 - (midi - range.lowerBound) / (range.upperBound - range.lowerBound)) }
        let rowHeight = size.height / (range.upperBound - range.lowerBound)

        // 每個半音一條淡格線，C 加深
        for midi in stride(from: range.lowerBound.rounded(.up), through: range.upperBound, by: 1) {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(midi)))
            line.addLine(to: CGPoint(x: size.width, y: y(midi)))
            let isC = Int(midi) % 12 == 0
            context.stroke(line, with: .color(.secondary.opacity(isC ? 0.25 : 0.08)), lineWidth: 1)
        }

        // 目標音符色塊與音名
        for note in run.timeline.notes where note.end.seconds >= start && note.start.seconds <= start + visibleSeconds {
            let rect = CGRect(x: x(note.start.seconds), y: y(Double(note.pitch.midi)) - rowHeight * 0.45,
                              width: max(4, x(note.end.seconds) - x(note.start.seconds) - 2), height: rowHeight * 0.9)
            let active = note.start.seconds <= now && now < note.end.seconds
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.accentColor.opacity(active ? 0.55 : 0.28)))
            context.draw(Text(note.pitch.name()).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
                         at: CGPoint(x: rect.minX + 14, y: rect.midY), anchor: .center)
        }

        // 學生的音高曲線，依偏差著色
        let points = run.livePoints.filter { $0.time >= start - 0.1 && $0.time <= now + 0.1 }
        for (a, b) in zip(points, points.dropFirst()) where b.time - a.time < 0.06 {
            var segment = Path()
            segment.move(to: CGPoint(x: x(a.time), y: y(a.midi)))
            segment.addLine(to: CGPoint(x: x(b.time), y: y(b.midi)))
            context.stroke(segment, with: .color(color(for: b.cents)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // 「現在」
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: x(now), y: 0))
        nowLine.addLine(to: CGPoint(x: x(now), y: size.height))
        context.stroke(nowLine, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
    }

    private func color(for cents: Double?) -> Color {
        guard let cents else { return .secondary }
        if abs(cents) <= tolerance { return TunerPalette.inTune }
        return cents > 0 ? .orange : .blue
    }
}
