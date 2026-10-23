import MusicTheory
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.referenceA4,
                            in: Int(TuningReference.allowedRange.lowerBound)...Int(TuningReference.allowedRange.upperBound)) {
                        LabeledContent("A4 基準音", value: "\(settings.referenceA4) Hz")
                    }
                    if settings.referenceA4 != Int(TuningReference.default.a4) {
                        Button("恢復預設（\(Int(TuningReference.default.a4)) Hz）") {
                            settings.referenceA4 = Int(TuningReference.default.a4)
                        }
                    }
                } header: {
                    Text("基準音")
                } footer: {
                    Text("所有音名與偏差都以此為準。可設定 415–466 Hz，請依老師指定的基準音設定。")
                }

                Section("開發") {
                    Toggle("顯示延遲資訊", isOn: $settings.showsLatencyOverlay)
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView().environment(AppSettings())
}
