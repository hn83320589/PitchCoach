import MusicTheory
import Observation
import PitchDetection
import PracticeEngine

@MainActor
@Observable
final class TunerViewModel {
    private(set) var display: TunerDisplayState = .silent
    @ObservationIgnored private var tracker: TunerTracker

    init(reference: TuningReference) {
        tracker = TunerTracker(reference: reference)
    }

    func process(_ frame: PitchFrame) {
        let next = tracker.process(frame)
        if next != display { display = next }
    }

    func updateReference(_ reference: TuningReference) {
        guard reference != tracker.reference else { return }
        tracker.reference = reference
        display = .silent
    }
}
