import Foundation
import MusicTheory
import PitchDetection

public struct TunerReading: Equatable, Sendable {
    public let note: Note
    /// 相對 `note` 的偏差，截在 ±50。
    public let cents: Double
    public let frequency: Double
}

public enum TunerDisplayState: Equatable, Sendable {
    /// 顯示「—」。
    case silent
    case reading(TunerReading)
}

/// 把逐 frame 的偵測結果轉成穩定的調音器讀數（docs/ARCHITECTURE.md §6）。
///
/// - 起音確認：連續 `onsetFrames` 個有效 frame 才顯示
/// - 保持與釋放：無效 frame 時保持讀數，連續 `releaseFrames` 個才回到「—」
/// - 中位數濾波：最近 `medianLength` 個 frame，去除單一 frame 的八度跳動
/// - 音名雙重遲滯：相對目前音 > 65 cents 立即換音；50–65 cents 持續 100 ms 才換
/// - 數值平滑：EMA（時間常數 50 ms），換音或起音時重設
public struct TunerTracker: Sendable {
    public struct Configuration: Sendable {
        public var onsetFrames = 2
        public var releaseFrames = 8
        public var medianLength = 3
        public var immediateSwitchCents = 65.0
        public var delayedSwitchDuration: Duration = .milliseconds(100)
        public var smoothingTimeConstant: Duration = .milliseconds(50)

        public init() {}
    }

    public let configuration: Configuration
    public var reference: TuningReference {
        didSet { reset() }
    }
    public private(set) var state: TunerDisplayState = .silent

    /// 最近有效 frame 的音高，以小數 MIDI 值表示（69.0 = A4）。
    private var recentPitches: [Double] = []
    private var validRun = 0
    private var invalidRun = 0
    private var currentNote: Note?
    private var smoothedPitch = 0.0
    private var lastTime: Duration?
    private var pendingSwitchSince: Duration?

    public init(reference: TuningReference, configuration: Configuration = Configuration()) {
        self.reference = reference
        self.configuration = configuration
    }

    public mutating func process(_ frame: PitchFrame) -> TunerDisplayState {
        guard let frequency = frame.frequency else {
            handleMissingPitch()
            return state
        }
        invalidRun = 0
        validRun += 1
        recentPitches.append(Double(Note.a4Midi) + 12 * log2(frequency / reference.a4))
        if recentPitches.count > configuration.medianLength {
            recentPitches.removeFirst()
        }
        let pitch = median(recentPitches)

        if let note = currentNote {
            let deviation = (pitch - Double(note.midi)) * 100
            if abs(deviation) > configuration.immediateSwitchCents {
                switchNote(to: pitch)
            } else if abs(deviation) > 50 {
                if let since = pendingSwitchSince, frame.time - since >= configuration.delayedSwitchDuration {
                    switchNote(to: pitch)
                } else {
                    if pendingSwitchSince == nil { pendingSwitchSince = frame.time }
                    smooth(toward: pitch, at: frame.time)
                }
            } else {
                pendingSwitchSince = nil
                smooth(toward: pitch, at: frame.time)
            }
        } else {
            guard validRun >= configuration.onsetFrames else { return state }
            switchNote(to: pitch)
        }
        lastTime = frame.time
        state = .reading(makeReading())
        return state
    }

    public mutating func reset() {
        recentPitches.removeAll()
        validRun = 0
        invalidRun = 0
        currentNote = nil
        lastTime = nil
        pendingSwitchSince = nil
        state = .silent
    }

    private mutating func handleMissingPitch() {
        validRun = 0
        invalidRun += 1
        if currentNote == nil {
            recentPitches.removeAll()
        } else if invalidRun >= configuration.releaseFrames {
            reset()
        }
    }

    private mutating func switchNote(to pitch: Double) {
        currentNote = Note(midi: Int((pitch + 0.5).rounded(.down)))
        smoothedPitch = pitch
        pendingSwitchSince = nil
    }

    private mutating func smooth(toward pitch: Double, at time: Duration) {
        let elapsed = lastTime.map { (time - $0).timeInterval } ?? 0
        let alpha = 1 - exp(-elapsed / configuration.smoothingTimeConstant.timeInterval)
        smoothedPitch += alpha * (pitch - smoothedPitch)
    }

    private func makeReading() -> TunerReading {
        let note = currentNote!
        let cents = min(50, max(-50, (smoothedPitch - Double(note.midi)) * 100))
        let frequency = reference.a4 * pow(2, (smoothedPitch - Double(Note.a4Midi)) / 12)
        return TunerReading(note: note, cents: cents, frequency: frequency)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
