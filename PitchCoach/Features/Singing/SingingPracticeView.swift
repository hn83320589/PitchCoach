import MusicTheory
import PracticeEngine
import SingingEngine
import SwiftData
import SwiftUI

struct SingingPracticeView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var model = SingingSessionModel()
    @State private var subscription: UUID?

    var body: some View {
        content
            .navigationTitle("歌唱練習")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                model.save = { [modelContext] record in
                    try PracticeRepository(container: modelContext.container).save(record)
                }
                pipeline.prefersVoiceProcessing = true
                subscription = pipeline.addInterruptionHandler { [model, settings] reason in
                    model.interrupt(reason, reference: settings.reference)
                }
            }
            .onDisappear {
                if let subscription { pipeline.removeInterruptionHandler(subscription) }
                if model.phase == .running { model.cancel() }
                pipeline.prefersVoiceProcessing = false
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .setup:
            SingingSetupView(model: model)
        case .running:
            if let run = model.run {
                SingingRunView(run: run) { model.cancel() }
            }
        case .finished:
            if let result = model.result {
                ScrollView {
                    SingingResultView(result: result, title: model.title, interruption: model.interruptionReason,
                                      saveError: model.saveError)
                    Button("再唱一次") { model.reset() }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct SingingSetupView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    @Bindable var model: SingingSessionModel

    var body: some View {
        let timeline = model.timeline(reference: settings.reference)
        @Bindable var pipeline = pipeline
        Form {
            Section("曲目") {
                Picker("歌曲", selection: $model.songID) {
                    ForEach(Songbook.songs) { Text($0.title).tag($0.id) }
                    Text("自訂旋律").tag(SingingSessionModel.customSongID)
                }
                .accessibilityIdentifier("singing.songPicker")
                if model.selectedSong == nil {
                    TextEditor(text: $model.customNotation)
                        .font(.body.monospaced())
                        .frame(minHeight: 90)
                        .accessibilityIdentifier("singing.customNotation")
                    Text("格式：音名＋八度:拍數，以空白分隔，例如 C4:1 D4:1 E4:2；休止符為 R:1")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if case .invalid(let message) = timeline {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("singing.error")
                }
            }

            Section {
                Stepper("速度 \(model.beatsPerMinute) BPM", value: $model.beatsPerMinute, in: 40...208)
                Stepper(value: $model.transposition, in: SongTimeline.transpositionRange) {
                    LabeledContent("移調", value: model.transposition == 0 ? "原調" : String(format: "%+d 個半音", model.transposition))
                }
                if let timeline = timeline.timeline, let low = timeline.notes.map(\.pitch).min(),
                   let high = timeline.notes.map(\.pitch).max() {
                    LabeledContent("音域", value: "\(low.name()) – \(high.name())")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("音域")
                        .accessibilityValue("\(low.name()) – \(high.name())")
                        .accessibilityIdentifier("singing.range")
                }
                Toggle("容許八度（唱高或低一個八度也算）", isOn: $model.allowsOctaveShift)
            } header: {
                Text("設定")
            }

            Section {
                Toggle("旋律提示音", isOn: $pipeline.songPlayerSettings.guideEnabled)
                Toggle("節拍", isOn: $pipeline.songPlayerSettings.clickEnabled)
                NavigationLink {
                    LatencyCalibrationView()
                } label: {
                    LabeledContent("延遲校正", value: calibrationText)
                }
            } header: {
                Text("伴奏")
            } footer: {
                if pipeline.isOutputBuiltInSpeaker {
                    Text(pipeline.isVoiceProcessingActive
                         ? "用喇叭播放伴奏時已開啟回音消除；戴耳機演唱效果最好。"
                         : "用喇叭播放時麥克風會收到伴奏，建議戴耳機演唱。")
                }
            }

            Section {
                Button {
                    model.start(reference: settings.reference, pipeline: pipeline,
                                calibrationOffset: settings.latencyCalibration(for: pipeline.routeKey) ?? 0)
                } label: {
                    Text("開始").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pipeline.state != .running || timeline.timeline == nil)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("practice.start")
            }
        }
    }

    private var calibrationText: String {
        guard let offset = settings.latencyCalibration(for: pipeline.routeKey) else { return "未校正" }
        return String(format: "%+.0f ms", offset * 1000)
    }
}

private struct SingingRunView: View {
    let run: SongRun
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(status).font(.headline).monospacedDigit()
            }
            PitchRollView(run: run, tolerance: run.options.pitchTolerance)
                .frame(maxHeight: .infinity)
            HStack(spacing: 16) {
                legend(color: TunerPalette.inTune, text: "準（±25¢）")
                legend(color: .orange, text: "偏高")
                legend(color: .blue, text: "偏低")
            }
            .font(.caption)
            Button("放棄", role: .destructive, action: cancel)
                .padding(.bottom)
        }
        .padding()
    }

    private var status: String {
        guard let now = run.currentSongTime else { return "預備…" }
        let total = run.timeline.duration.seconds
        return now < 0 ? String(format: "預備 %.0f", ceil(-now / run.timeline.beatDuration.seconds))
            : String(format: "演唱中 %.0f / %.0f 秒", min(now, total), total)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

struct SingingResultView: View {
    let result: SingingResult
    let title: String
    let interruption: PracticeInterruptionReason?
    var saveError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            if let interruption { InterruptedBadge(reason: interruption.displayName) }
            HStack(spacing: 12) {
                StatTile(title: "音準正確率", value: String(format: "%.0f%%", result.pitchAccuracy * 100), emphasized: true)
                    .accessibilityIdentifier("singing.pitchAccuracy")
                StatTile(title: "節奏正確率", value: String(format: "%.0f%%", result.rhythmAccuracy * 100), emphasized: true)
                    .accessibilityIdentifier("singing.rhythmAccuracy")
            }
            if let weak = result.weakestRange {
                Label("最常唱不準：\(weak.lowest.name()) – \(weak.highest.name())（\(weak.total) 個音中 \(weak.missed) 個）",
                      systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("singing.weakestRange")
            }
            VStack(spacing: 0) {
                ForEach(Array(result.notes.enumerated()), id: \.offset) { index, note in
                    SungNoteRow(note: note)
                    if index < result.notes.count - 1 { Divider() }
                }
            }
            .padding(.horizontal)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            if let saveError {
                Text(saveError).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
    }
}

private struct SungNoteRow: View {
    let note: SungNoteResult

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(note.note.pitch.name()).font(.body.weight(.medium)).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(pitchText).foregroundStyle(pitchColor)
                if let vibrato = note.vibrato {
                    Text(String(format: "顫音 %.1f Hz ±%.0f¢", vibrato.rate, vibrato.depthCents))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(rhythmText).font(.callout).foregroundStyle(note.rhythmVerdict == .onTime ? .secondary : Color.orange)
        }
        .monospacedDigit()
        .padding(.vertical, 8)
    }

    private var pitchText: String {
        switch note.pitchVerdict {
        case .accurate: "準 \(formattedCents(note.centsDeviation))"
        case .sharp: "偏高 \(formattedCents(note.centsDeviation))"
        case .flat: "偏低 \(formattedCents(note.centsDeviation))"
        case .notSung: "沒唱"
        }
    }

    private var pitchColor: Color {
        switch note.pitchVerdict {
        case .accurate: TunerPalette.inTune
        case .sharp: .orange
        case .flat: .blue
        case .notSung: .secondary
        }
    }

    private var rhythmText: String {
        let ms = note.onsetOffset.map { String(format: "%+.0f ms", $0.seconds * 1000) } ?? ""
        return switch note.rhythmVerdict {
        case .onTime: "準時 \(ms)"
        case .early: "提早 \(ms)"
        case .late: "延遲 \(ms)"
        case .notSung: "—"
        }
    }
}
