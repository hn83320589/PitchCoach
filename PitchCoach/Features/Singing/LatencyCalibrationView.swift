import MusicTheory
import SingingEngine
import SwiftUI

/// 依路由的延遲校正（docs/SINGING_MODE.md §7.2）：播放 8 個提示音，由麥克風收音量出未補償的延遲。
/// 也用於 AC-19 的「回授自我測試」：顯示每個提示音的起音偏移。
struct LatencyCalibrationView: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    @State private var run: SongRun?
    @State private var result: SingingResult?
    @State private var message: String?
    @State private var subscription: UUID?

    var body: some View {
        List {
            Section {
                LabeledContent("目前輸出", value: pipeline.routeName.isEmpty ? "—" : pipeline.routeName)
                LabeledContent("iOS 回報的輸出延遲", value: String(format: "%.0f ms", pipeline.outputLatency * 1000))
                LabeledContent("已儲存的校正值", value: settings.latencyCalibration(for: pipeline.routeKey)
                    .map { String(format: "%+.0f ms", $0 * 1000) } ?? "未校正")
            } footer: {
                Text("用喇叭時直接校正；用耳機時請把耳機貼近手機底部的麥克風。校正期間請保持安靜。")
            }

            Section {
                Button(run == nil ? "開始校正" : "校正中…", action: start)
                    .disabled(run != nil || pipeline.state != .running)
                if let message { Text(message) }
            }

            if let result {
                Section("每個提示音的起音偏移（伴奏本身當範唱）") {
                    ForEach(Array(result.notes.enumerated()), id: \.offset) { index, note in
                        LabeledContent("第 \(index + 1) 個", value: note.onsetOffset.map { String(format: "%+.0f ms", $0.seconds * 1000) } ?? "未偵測到")
                    }
                }
            }
        }
        .navigationTitle("延遲校正")
        .onAppear {
            pipeline.prefersVoiceProcessing = false      // 校正必須讓麥克風收到伴奏
            subscription = pipeline.addInterruptionHandler { _ in
                guard let run else { return }
                run.stop()
                self.run = nil
                message = "校正被中斷（來電、耳機或音訊裝置變更），請再試一次。"
            }
        }
        .onDisappear {
            if let subscription { pipeline.removeInterruptionHandler(subscription) }
            run?.stop()
            pipeline.prefersVoiceProcessing = true
        }
    }

    private func start() {
        do {
            let timeline = try LatencyCalibration.timeline(reference: settings.reference)
            let run = SongRun(timeline: timeline, reference: settings.reference, options: SingingOptions(), pipeline: pipeline,
                              calibrationOffset: 0)
            run.onFinished = { result in
                self.result = result
                self.run = nil
                if let offset = LatencyCalibration.offset(from: result) {
                    settings.setLatencyCalibration(offset, for: pipeline.routeKey)
                    message = String(format: "已儲存校正值 %+.0f ms", offset * 1000)
                } else {
                    message = "偵測到的提示音不足 \(LatencyCalibration.minimumDetected) 個，請調高音量或在安靜處再試一次。"
                }
            }
            self.run = run
            message = nil
            run.start()
        } catch {
            message = "無法建立校正音：\(error)"
        }
    }
}
