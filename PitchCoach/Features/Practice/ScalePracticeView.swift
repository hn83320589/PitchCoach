import MusicTheory
import PracticeEngine
import SwiftData
import SwiftUI

struct ScalePracticeView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var model: ScalePracticeModel?
    @State private var subscriptions: [UUID] = []

    var body: some View {
        Group {
            if let model {
                content(model)
            }
        }
        .navigationTitle("音階練習")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: subscribe)
        .onDisappear(perform: unsubscribe)
    }

    @ViewBuilder
    private func content(_ model: ScalePracticeModel) -> some View {
        switch model.phase {
        case .setup:
            ScaleSetupView(model: model, reference: settings.reference, canStart: pipeline.state == .running) {
                model.start(reference: settings.reference)
            }
        case .running:
            ScaleRunningView(model: model)
        case .finished:
            if let result = model.result {
                ScrollView {
                    ScaleResultView(result: result, interruption: model.interruptionReason, saveError: model.saveError)
                    Button("再練一次") { model.reset() }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private func subscribe() {
        let model = self.model ?? ScalePracticeModel(save: { [modelContext] record in
            try PracticeRepository(container: modelContext.container).save(record)
        })
        self.model = model
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
        if model?.phase == .running { model?.cancel() }
    }
}

private struct ScaleSetupView: View {
    @Bindable var model: ScalePracticeModel
    let reference: TuningReference
    let canStart: Bool
    let start: () -> Void

    var body: some View {
        let octaves = model.availableOctaves(reference: reference)
        Form {
            Section {
                Picker("調", selection: $model.key) {
                    ForEach(MajorKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("起始八度", selection: $model.startOctave) {
                    ForEach(octaves, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("方向", selection: $model.direction) {
                    Text("上行").tag(ScaleDirection.ascending)
                    Text("上下行").tag(ScaleDirection.ascendingDescending)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("音階")
            } footer: {
                Text("每個音在 ±15 cents 以內持續 0.3 秒即「到位」，自動跳到下一個音。")
            }

            Section("伴奏") {
                AccompanimentPanel(defaultDroneNote: model.key.tonic, allowsNoteSelection: false)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Button(action: start) {
                    Text("開始").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart || !octaves.contains(model.startOctave))
                .listRowBackground(Color.clear)
            } footer: {
                if let setupError = model.setupError {
                    Text(setupError).foregroundStyle(.red)
                } else if !canStart {
                    Text("收音尚未啟動。")
                }
            }
        }
        .onChange(of: model.key) {
            // 換調後若原本的八度超出範圍，改用最接近的可選八度
            if !octaves.contains(model.startOctave), let nearest = octaves.min(by: { abs($0 - model.startOctave) < abs($1 - model.startOctave) }) {
                model.startOctave = nearest
            }
        }
    }
}

private struct ScaleRunningView: View {
    let model: ScalePracticeModel

    var body: some View {
        if let scale = model.scale {
            VStack(spacing: 24) {
                StepStrip(scale: scale, current: model.currentStep, reached: model.reachedSteps)
                Spacer()
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: model.holdProgress)
                        .stroke(TunerPalette.inTune, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: model.holdProgress)
                    Text(scale.displayName(of: scale.steps[min(model.currentStep, scale.steps.count - 1)]))
                        .font(.system(size: 72, weight: .semibold, design: .rounded))
                }
                .frame(width: 220, height: 220)
                Text(formattedCents(model.currentCents))
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(model.currentCents.map { abs($0) <= 15 ? TunerPalette.inTune : TunerPalette.color(forCents: $0) } ?? .secondary)
                CentsMeter(cents: model.currentCents.map { max(-50, min(50, $0)) }, tolerance: 15)
                    .padding(.horizontal)
                Spacer()
                HStack(spacing: 24) {
                    Button("放棄", role: .destructive) { model.cancel() }
                    Button("跳過這個音") { model.skipCurrentStep() }
                        .buttonStyle(.bordered)
                }
                .padding(.bottom)
            }
            .padding()
        }
    }
}

/// 音階各步驟的進度列：已到位打勾、目前的音高亮。
private struct StepStrip: View {
    let scale: MajorScale
    let current: Int
    let reached: Set<Int>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(scale.steps.enumerated()), id: \.offset) { index, note in
                        Text(scale.displayName(of: note))
                            .font(.callout.weight(index == current ? .bold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(background(for: index), in: Capsule())
                            .foregroundStyle(index == current ? Color.white : .primary)
                            .id(index)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: current) { withAnimation { proxy.scrollTo(current, anchor: .center) } }
        }
    }

    private func background(for index: Int) -> Color {
        if index == current { return .accentColor }
        if reached.contains(index) { return TunerPalette.inTune.opacity(0.25) }
        return Color.secondary.opacity(0.12)
    }
}

struct ScaleResultView: View {
    let result: ScaleResult
    let interruption: PracticeInterruptionReason?
    var saveError: String?

    var body: some View {
        let worst = Set(result.worstNotes.map(\.note))
        VStack(spacing: 16) {
            Text(result.scale.key.displayName)
                .font(.title.weight(.semibold))
            if let interruption {
                InterruptedBadge(reason: interruption.displayName)
            }
            HStack(spacing: 12) {
                StatTile(title: "到位", value: "\(result.reachedCount) / \(result.steps.count)", emphasized: true)
                StatTile(title: "偏差最大", value: result.worstNotes.map { result.scale.displayName(of: $0.note) }.joined(separator: "、"))
            }
            VStack(spacing: 0) {
                ForEach(Array(result.steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Image(systemName: step.reached ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.reached ? TunerPalette.inTune : .secondary)
                        Text(step.displayName).font(.body.weight(.medium))
                        if worst.contains(step.note) {
                            Text("偏差最大")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text(formattedCents(step.meanCents))
                            .monospacedDigit()
                            .foregroundStyle(worst.contains(step.note) ? .red : .primary)
                    }
                    .padding(.vertical, 10)
                    if index < result.steps.count - 1 { Divider() }
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
