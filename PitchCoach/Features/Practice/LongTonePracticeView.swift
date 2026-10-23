import MusicTheory
import PracticeEngine
import SwiftData
import SwiftUI

struct LongTonePracticeView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var model = LongTonePracticeModel()
    @State private var subscriptions: [UUID] = []

    var body: some View {
        content(model)
        .navigationTitle("長音練習")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: subscribe)
        .onDisappear(perform: unsubscribe)
    }

    @ViewBuilder
    private func content(_ model: LongTonePracticeModel) -> some View {
        switch model.phase {
        case .setup:
            LongToneSetupView(model: model, reference: settings.reference,
                              canStart: pipeline.state == .running) {
                model.start(reference: settings.reference)
            }
        case .running:
            LongToneRunningView(model: model)
        case .finished:
            if let result = model.result {
                ScrollView {
                    LongToneResultView(result: result, interruption: model.interruptionReason, saveError: model.saveError)
                    Button("再練一次") { model.reset() }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private func subscribe() {
        model.save = { [modelContext] record in
            try PracticeRepository(container: modelContext.container).save(record)
        }
        let model = self.model
        subscriptions = [
            pipeline.addFrameHandler { frame in model.process(frame) },
            pipeline.addInterruptionHandler { reason in model.interrupt(reason) },
        ]
    }

    private func unsubscribe() {
        subscriptions.forEach {
            pipeline.removeFrameHandler($0)
            pipeline.removeInterruptionHandler($0)
        }
        subscriptions = []
        // 離開畫面視為放棄（不存檔）
        if model.phase == .running { model.cancel() }
    }
}

private struct LongToneSetupView: View {
    @Bindable var model: LongTonePracticeModel
    let reference: TuningReference
    let canStart: Bool
    let start: () -> Void

    private var noteName: Binding<PitchClass> {
        Binding { model.target.pitchClass } set: { model.target = Note(midi: (model.target.octave + 1) * 12 + $0.rawValue) }
    }

    private var octave: Binding<Int> {
        Binding { model.target.octave } set: { model.target = Note(midi: ($0 + 1) * 12 + model.target.pitchClass.rawValue) }
    }

    private var isInRange: Bool {
        PitchRange.detectable.contains(NoteConverter.frequency(of: model.target, reference: reference))
    }

    var body: some View {
        Form {
            Section {
                Picker("音名", selection: noteName) {
                    ForEach(PitchClass.allCases, id: \.self) { pitchClass in
                        Text(Note(midi: 60 + pitchClass.rawValue).name().dropLast()).tag(pitchClass)
                    }
                }
                Picker("八度", selection: octave) {
                    ForEach(2...7, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("目標", value: String(format: "%@（%.1f Hz）", model.target.name(),
                                                      NoteConverter.frequency(of: model.target, reference: reference)))
            } header: {
                Text("目標音")
            } footer: {
                if !isInRange {
                    Text("這個音超出偵測範圍（65–2,100 Hz）。").foregroundStyle(.red)
                } else {
                    Text("按「開始」後，第一個聲音出現時開始計時 10 秒。")
                }
            }

            Section("伴奏") {
                AccompanimentPanel(defaultDroneNote: model.target.pitchClass, allowsNoteSelection: false)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Button(action: start) {
                    Text("開始").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("practice.start")
                .buttonStyle(.borderedProminent)
                .disabled(!isInRange || !canStart)
                .listRowBackground(Color.clear)
            } footer: {
                if !canStart { Text("收音尚未啟動。") }
            }
        }
    }
}

private struct LongToneRunningView: View {
    let model: LongTonePracticeModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(model.target.name())
                .font(.system(size: 96, weight: .semibold, design: .rounded))
            switch model.progress {
            case .waitingForSound:
                Text("請開始演奏").font(.title3).foregroundStyle(.secondary)
                CentsMeter(cents: nil, tolerance: 10)
                ProgressView(value: 0).padding(.horizontal)
            case .running(let elapsed, let cents):
                Text(formattedCents(cents))
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(cents.map { abs($0) <= 10 ? TunerPalette.inTune : TunerPalette.color(forCents: $0) } ?? .secondary)
                CentsMeter(cents: cents.map { max(-50, min(50, $0)) }, tolerance: 10)
                ProgressView(value: min(1, elapsed / model.duration)) {
                    Text(String(format: "剩 %.1f 秒", max(0, (model.duration - elapsed).seconds)))
                        .font(.footnote.monospacedDigit())
                }
                .padding(.horizontal)
            case .finished:
                ProgressView()
            }
            Spacer()
            Button("放棄", role: .destructive) { model.cancel() }
                .padding(.bottom)
        }
        .padding()
    }
}

struct LongToneResultView: View {
    let result: LongToneResult
    let interruption: PracticeInterruptionReason?
    var saveError: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(result.target.name())
                .font(.system(size: 56, weight: .semibold, design: .rounded))
            if let interruption {
                InterruptedBadge(reason: interruption.displayName)
                Text(String(format: "保留已完成的 %.1f 秒", result.analyzedDuration.seconds))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                StatTile(title: "±10¢ 以內", value: String(format: "%.0f%%", result.inToleranceRatio * 100), emphasized: true)
                    .accessibilityIdentifier("longTone.accuracy")
                StatTile(title: "平均偏差", value: formattedCents(result.meanCents))
                    .accessibilityIdentifier("longTone.mean")
                StatTile(title: "穩定度（標準差）", value: result.standardDeviationCents.map { String(format: "%.1f ¢", $0) } ?? "—")
                    .accessibilityIdentifier("longTone.standardDeviation")
            }
            DeviationCurveChart(curve: result.curve)
                .frame(height: 220)
            if let saveError {
                Text(saveError).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var emphasized = false

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font((emphasized ? Font.title : .title3).monospacedDigit().weight(.semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
