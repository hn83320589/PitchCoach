import MusicTheory
import PracticeEngine
import SwiftUI

struct TunerView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    @State private var model = TunerViewModel(reference: .default)
    @State private var handlerID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                switch pipeline.state {
                case .permissionDenied:
                    MicrophonePermissionView()
                case .failed(let message):
                    AudioErrorView(message: message) { pipeline.resume() }
                case .suspended:
                    AudioSuspendedView { pipeline.resume() }
                case .idle, .running:
                    tuner
                }
            }
            .navigationTitle("調音器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("A4 = \(settings.referenceA4) Hz")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            model.updateReference(settings.reference)
            handlerID = pipeline.addFrameHandler { [model] frame in model.process(frame) }
        }
        .onDisappear {
            if let handlerID { pipeline.removeFrameHandler(handlerID) }
        }
        .onChange(of: settings.referenceA4) {
            model.updateReference(settings.reference)
        }
    }

    private var tuner: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            NoteDisplay(state: model.display)
            TunerGauge(cents: reading?.cents)
                .padding(.horizontal, 16)
            ReadoutRow(reading: reading)
            Spacer()
            AccompanimentPanel(defaultDroneNote: .a)
            if settings.showsLatencyOverlay {
                LatencyOverlay()
            }
        }
        .padding()
    }

    private var reading: TunerReading? {
        if case .reading(let reading) = model.display { return reading }
        return nil
    }
}

/// 大字音名與八度，無讀數時顯示「—」。
private struct NoteDisplay: View {
    let state: TunerDisplayState

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            switch state {
            case .silent:
                Text("—")
                    .font(.system(size: 112, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            case .reading(let reading):
                let parts = Self.split(reading.note)
                Text(parts.name)
                    .font(.system(size: 112, weight: .semibold, design: .rounded))
                Text(parts.octave)
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 140)
        .contentTransition(.numericText())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tuner.note")
    }

    /// "C#5" → ("C#", "5")
    static func split(_ note: Note) -> (name: String, octave: String) {
        let octave = String(note.octave)
        let full = note.name()
        return (String(full.dropLast(octave.count)), octave)
    }
}

struct ReadoutRow: View {
    let reading: TunerReading?

    var body: some View {
        HStack(spacing: 32) {
            readout(title: "偏差", value: reading.map { Self.formatCents($0.cents) } ?? "—",
                    color: TunerPalette.color(forCents: reading?.cents))
                .accessibilityIdentifier("tuner.cents")
            readout(title: "頻率", value: reading.map { String(format: "%.1f Hz", $0.frequency) } ?? "—",
                    color: .primary)
                .accessibilityIdentifier("tuner.frequency")
        }
    }

    /// 四捨五入後為 0 時顯示「0 ¢」，避免出現「−0 ¢」讓學生誤以為偏低。
    nonisolated static func formatCents(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        return rounded == 0 ? "0 ¢" : String(format: "%+d ¢", rounded)
    }

    private func readout(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// 開發用：顯示分析窗結束到畫面顯示的延遲。
private struct LatencyOverlay: View {
    @Environment(AudioPipeline.self) private var pipeline

    var body: some View {
        let stats = pipeline.latency
        VStack(alignment: .leading, spacing: 2) {
            Text("延遲（分析窗結束 → 畫面）")
            Text(String(format: "P50 %.0f ms　P95 %.0f ms　n = %d",
                        (stats.percentile(50) ?? 0) * 1000, (stats.percentile(95) ?? 0) * 1000, stats.count))
            Text(String(format: "硬體輸入 %.1f ms　取樣率 %.0f Hz",
                        pipeline.hardwareInputLatency * 1000, pipeline.sampleRate ?? 0))
            Text(String(format: "輸入電平 %.1f dBFS　已接收 %d frames",
                        pipeline.inputLevelDB, pipeline.receivedFrameCount))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TunerView()
        .environment(AudioPipeline())
        .environment(AppSettings())
}
