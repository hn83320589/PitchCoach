import Foundation
import MusicTheory

public struct SingingOptions: Equatable, Sendable {
    /// 唱成高或低一個八度仍以 cents 偏差判定。
    public var allowsOctaveShift: Bool
    public var pitchTolerance: Double
    public var rhythmTolerance: Duration
    /// 每個音符頭尾各去掉的比例。
    public var trimFraction: Double
    public var minimumBreathGap: Duration
    public var onsetSearchLimit: Duration

    public init(allowsOctaveShift: Bool = false, pitchTolerance: Double = 25, rhythmTolerance: Duration = .milliseconds(80),
                trimFraction: Double = 0.15, minimumBreathGap: Duration = .milliseconds(40),
                onsetSearchLimit: Duration = .milliseconds(250)) {
        self.allowsOctaveShift = allowsOctaveShift
        self.pitchTolerance = pitchTolerance
        self.rhythmTolerance = rhythmTolerance
        self.trimFraction = trimFraction
        self.minimumBreathGap = minimumBreathGap
        self.onsetSearchLimit = onsetSearchLimit
    }
}

public enum PitchVerdict: String, Sendable {
    case accurate, sharp, flat, notSung
}

public enum RhythmVerdict: String, Sendable {
    case onTime, early, late, notSung
}

public struct SungNoteResult: Equatable, Sendable {
    public let note: ScoredNote
    /// 相對目標音的偏差（容許八度時為折算後）；沒唱時為 nil。
    public let centsDeviation: Double?
    public let pitchVerdict: PitchVerdict
    public let vibrato: VibratoEstimate?
    /// 實際起音 − 樂譜起音。
    public let onsetOffset: Duration?
    public let rhythmVerdict: RhythmVerdict
}

/// 最常唱不準的音高區段。
public struct WeakRange: Equatable, Sendable {
    public let lowest: Note
    public let highest: Note
    public let missed: Int
    public let total: Int
}

public struct SingingResult: Equatable, Sendable {
    public let notes: [SungNoteResult]
    /// 準的音符 ÷ 全部音符（沒唱算不準）。
    public let pitchAccuracy: Double
    /// 準時的音符 ÷ 全部音符（沒唱算不準時）。
    public let rhythmAccuracy: Double
    public let weakestRange: WeakRange?
    public let isComplete: Bool
}

/// 歌唱判定（docs/SINGING_MODE.md §4、§5、§7.3）。收集整首的 frame，結束時逐音判定。
public struct SingingEvaluator: Sendable {
    public static let weakRangeWidth = 5       // 半音
    public static let weakRangeMinimumNotes = 3

    public let timeline: SongTimeline
    public let reference: TuningReference
    public let options: SingingOptions
    private var frames: [SungFrame] = []
    private let windowGain: @Sendable (Double) -> Double

    public init(timeline: SongTimeline, reference: TuningReference, options: SingingOptions,
                analysisWindowDuration: Double = 2048.0 / 48000) {
        self.timeline = timeline
        self.reference = reference
        self.options = options
        windowGain = VibratoAnalyzer.windowGain(windowDuration: analysisWindowDuration)
    }

    public mutating func process(_ frame: SungFrame) {
        frames.append(frame)
    }

    /// 即時顯示用：相對目標音的偏差（容許八度時折算）。
    public func cents(for frequency: Double, target: Note) -> Double {
        let raw = NoteConverter.cents(frequency: frequency, relativeTo: target, reference: reference)
        guard options.allowsOctaveShift else { return raw }
        let shift = max(-1, min(1, (raw / 1200).rounded()))
        return raw - 1200 * shift
    }

    /// - Parameter time: 中斷時傳入目前的歌曲時間，只判定已結束的音符。
    public func result(through time: Duration? = nil) -> SingingResult {
        let included = timeline.notes.filter { time == nil || $0.end <= time! }
        let detector = OnsetDetector(frames: frames.sorted { $0.time < $1.time }, reference: reference,
                                     allowsOctaveShift: options.allowsOctaveShift,
                                     minimumBreathGap: options.minimumBreathGap, searchLimit: options.onsetSearchLimit)
        let results = included.indices.map { evaluate(index: $0, notes: timeline.notes, detector: detector) }
        let total = Double(max(1, results.count))
        return SingingResult(
            notes: results,
            pitchAccuracy: results.isEmpty ? 0 : Double(results.filter { $0.pitchVerdict == .accurate }.count) / total,
            rhythmAccuracy: results.isEmpty ? 0 : Double(results.filter { $0.rhythmVerdict == .onTime }.count) / total,
            weakestRange: Self.weakestRange(results),
            isComplete: time == nil || time! >= timeline.duration
        )
    }

    private func evaluate(index: Int, notes: [ScoredNote], detector: OnsetDetector) -> SungNoteResult {
        let note = notes[index]
        let inNote = frames.filter { $0.frequency != nil && $0.time >= note.start && $0.time < note.end }
        guard !inNote.isEmpty else {
            return SungNoteResult(note: note, centsDeviation: nil, pitchVerdict: .notSung, vibrato: nil,
                                  onsetOffset: nil, rhythmVerdict: .notSung)
        }

        let trim = note.duration * options.trimFraction
        let middle = inNote.filter { $0.time >= note.start + trim && $0.time < note.end - trim }
        // 中段有效 frame 太少（短音符或只唱了頭尾）時改用整個音符期間
        let analyzed = middle.count >= 3 ? middle : inNote
        let cents = analyzed.map { self.cents(for: $0.frequency!, target: note.pitch) }

        let vibrato = middle.count >= 12
            ? VibratoAnalyzer.analyze(times: analyzed.map { $0.time.timeInterval }, cents: cents, compensation: windowGain)
            : nil
        let deviation = vibrato?.centerCents ?? Self.median(cents)
        let pitchVerdict: PitchVerdict = abs(deviation) <= options.pitchTolerance + 1e-9 ? .accurate : (deviation > 0 ? .sharp : .flat)

        let onset = detector.onset(for: index, in: notes)
        let offset = onset.map { $0 - note.start }
        let rhythmVerdict: RhythmVerdict = switch offset {
        case nil: .notSung
        case let value? where abs(value.timeInterval) <= options.rhythmTolerance.timeInterval + 1e-6: .onTime
        case let value?: value < .zero ? .early : .late
        }
        return SungNoteResult(note: note, centsDeviation: deviation, pitchVerdict: pitchVerdict, vibrato: vibrato,
                              onsetOffset: offset, rhythmVerdict: rhythmVerdict)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// 5 個半音寬的滑動區段中，不準（偏高、偏低、沒唱）比例最高、至少 3 個音者。
    static func weakestRange(_ results: [SungNoteResult]) -> WeakRange? {
        guard let low = results.map(\.note.pitch.midi).min(), let high = results.map(\.note.pitch.midi).max() else { return nil }
        var best: (rate: Double, range: WeakRange)?
        for start in low...max(low, high - weakRangeWidth + 1) {
            let inRange = results.filter { (start..<(start + weakRangeWidth)).contains($0.note.pitch.midi) }
            guard inRange.count >= weakRangeMinimumNotes else { continue }
            let missed = inRange.filter { $0.pitchVerdict != .accurate }.count
            let rate = Double(missed) / Double(inRange.count)
            guard missed > 0, rate > (best?.rate ?? 0) else { continue }
            let pitches = inRange.map(\.note.pitch.midi)
            best = (rate, WeakRange(lowest: Note(midi: pitches.min()!), highest: Note(midi: pitches.max()!),
                                    missed: missed, total: inRange.count))
        }
        return best?.range
    }
}
