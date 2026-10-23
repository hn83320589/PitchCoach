import Accompaniment
import MusicTheory
import SwiftUI

/// 持續音與節拍器的控制列，調音器與練習畫面共用。
struct AccompanimentPanel: View {
    @Environment(AudioPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var settings
    /// 練習畫面傳入目標調性的主音；調音器可自行選擇。
    let defaultDroneNote: PitchClass
    var allowsNoteSelection = true

    @State private var droneNote: PitchClass?

    /// drone 放在第 3 八度（C3–B3，約 131–247 Hz）
    private static let droneOctave = 3

    var body: some View {
        @Bindable var pipeline = pipeline
        VStack(spacing: 12) {
            HStack {
                Toggle(isOn: droneEnabled) {
                    Label("持續音", systemImage: "waveform")
                }
                .toggleStyle(.button)
                Spacer()
                if allowsNoteSelection {
                    Picker("持續音的音", selection: noteSelection) {
                        ForEach(PitchClass.allCases, id: \.self) { pitchClass in
                            Text(Note(midi: 60 + pitchClass.rawValue).name().dropLast()).tag(pitchClass)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(Note(midi: 60 + currentDroneNote.rawValue).name().dropLast())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Toggle(isOn: $pipeline.metronome.isEnabled) {
                    Label("節拍器", systemImage: "metronome")
                }
                .toggleStyle(.button)
                Spacer()
                Stepper(value: $pipeline.metronome.beatsPerMinute, in: MetronomeSettings.tempoRange) {
                    Text("\(pipeline.metronome.beatsPerMinute) BPM")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize()
            }
            if pipeline.drone.isEnabled && pipeline.isOutputBuiltInSpeaker {
                Label("用喇叭播放時麥克風也會收到持續音，建議戴耳機。", systemImage: "headphones")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { applyDroneFrequency() }
        .onChange(of: settings.referenceA4) { applyDroneFrequency() }
        .onChange(of: defaultDroneNote) {
            droneNote = nil
            applyDroneFrequency()
        }
    }

    private var currentDroneNote: PitchClass {
        droneNote ?? defaultDroneNote
    }

    private var droneEnabled: Binding<Bool> {
        Binding {
            pipeline.drone.isEnabled
        } set: { enabled in
            applyDroneFrequency()
            pipeline.drone.isEnabled = enabled
        }
    }

    private var noteSelection: Binding<PitchClass> {
        Binding {
            currentDroneNote
        } set: { pitchClass in
            droneNote = pitchClass
            applyDroneFrequency()
        }
    }

    private func applyDroneFrequency() {
        let note = Note(midi: (Self.droneOctave + 1) * 12 + currentDroneNote.rawValue)
        pipeline.drone.frequency = NoteConverter.frequency(of: note, reference: settings.reference)
    }
}
