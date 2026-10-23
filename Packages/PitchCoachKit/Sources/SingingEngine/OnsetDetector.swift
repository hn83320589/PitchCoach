import Foundation
import MusicTheory

/// 起音偵測（docs/SINGING_MODE.md §7.3）。在樂譜起點附近找三種線索，依可靠度取用：
/// 1. 發聲起點：無音高持續 ≥ 40 ms 後出現音高（換氣後起音）
/// 2. 音高轉換：連唱換音時，音高曲線穿過前後兩個目標音的中點（換音瞬間分析窗橫跨兩個音，
///    常有 1–3 個 frame 沒有音高，因此容許 ≤ 80 ms 的空檔並在兩端之間內插）
/// 3. 電平上升：同音重複時重新咬字，電平先下降再上升 ≥ 6 dB，取上升過中點的時間
/// 都找不到時：若與前一個同音高的音連成一個長音（跨過樂譜起點時發聲沒有中斷），回報「沒有分開唱」——
/// 此時搜尋範圍內的 frame 屬於前一個音，拿來當起音會得到假的提早或準時；
/// 否則取搜尋範圍內第一個接近目標音（±100 cents）的有音高 frame。
struct OnsetDetector {
    enum Result: Equatable {
        case found(Duration)
        case notSeparated
        case notFound
    }

    let frames: [SungFrame]
    let reference: TuningReference
    let allowsOctaveShift: Bool
    let minimumBreathGap: Duration
    let searchLimit: Duration
    let minimumLevelRise = 6.0
    let maximumCrossingGap: Duration = .milliseconds(80)

    func onset(for index: Int, in notes: [ScoredNote]) -> Result {
        let note = notes[index]
        var halfGap = searchLimit
        if index > 0 { halfGap = min(halfGap, (note.start - notes[index - 1].start) / 2) }
        if index + 1 < notes.count { halfGap = min(halfGap, (notes[index + 1].start - note.start) / 2) }
        let window = (note.start - halfGap)...(note.start + halfGap)

        if let time = nearest(voicingOnsets(in: window), to: note.start) { return .found(time) }
        if index > 0, notes[index - 1].pitch != note.pitch,
           let time = nearest(pitchCrossings(from: notes[index - 1].pitch, to: note.pitch, in: window), to: note.start) {
            return .found(time)
        }
        if let time = nearest(levelRises(in: window), to: note.start) { return .found(time) }
        if index > 0, notes[index - 1].pitch == note.pitch, isContinuouslyVoiced(across: note.start) { return .notSeparated }
        let voicedInRange = frames.filter { $0.frequency != nil && $0.time >= window.lowerBound && $0.time < note.end }
        let nearTarget = voicedInRange.first { abs(pitch($0.frequency!, near: note.pitch) - Double(note.pitch.midi)) <= 1 }
        return (nearTarget ?? voicedInRange.first { $0.time >= note.start }).map { .found($0.time) } ?? .notFound
    }

    /// time 前後最近的兩個有音高 frame 相距不超過換氣門檻，即發聲沒有中斷。
    private func isContinuouslyVoiced(across time: Duration) -> Bool {
        guard let before = frames.last(where: { $0.frequency != nil && $0.time <= time }),
              let after = frames.first(where: { $0.frequency != nil && $0.time > time }) else { return false }
        return after.time - before.time <= minimumBreathGap
    }

    private func nearest(_ candidates: [Duration], to target: Duration) -> Duration? {
        candidates.min { abs(($0 - target).timeInterval) < abs(($1 - target).timeInterval) }
    }

    private func voicingOnsets(in window: ClosedRange<Duration>) -> [Duration] {
        var result: [Duration] = []
        var lastVoiced: Duration?
        var sawFrameBefore = false
        for frame in frames where frame.time <= window.upperBound {
            if frame.frequency != nil {
                let gapIsBreath = lastVoiced.map { frame.time - $0 > minimumBreathGap } ?? true
                if gapIsBreath, window.contains(frame.time), sawFrameBefore || lastVoiced == nil {
                    result.append(frame.time)
                }
                lastVoiced = frame.time
            }
            sawFrameBefore = true
        }
        return result
    }

    private func pitchCrossings(from previous: Note, to target: Note, in window: ClosedRange<Duration>) -> [Duration] {
        let midpoint = Double(previous.midi + target.midi) / 2
        let rising = target.midi > previous.midi
        var result: [Duration] = []
        let voiced = frames.filter { $0.frequency != nil && window.contains($0.time) }
        for (a, b) in zip(voiced, voiced.dropFirst()) {
            let pa = pitch(a.frequency!, near: target), pb = pitch(b.frequency!, near: target)
            let crosses = rising ? (pa < midpoint && pb >= midpoint) : (pa > midpoint && pb <= midpoint)
            guard crosses, b.time - a.time <= maximumCrossingGap else { continue }
            let fraction = (midpoint - pa) / (pb - pa)
            result.append(a.time + (b.time - a.time) * fraction)
        }
        return result
    }

    private func levelRises(in window: ClosedRange<Duration>) -> [Duration] {
        let nearby = frames.filter { $0.levelTime >= window.lowerBound - .milliseconds(80) && $0.levelTime <= window.upperBound + .milliseconds(80) }
        guard nearby.count >= 3 else { return [] }
        var result: [Duration] = []
        for index in 1..<(nearby.count - 1) where nearby[index].levelDB <= nearby[index - 1].levelDB
            && nearby[index].levelDB < nearby[index + 1].levelDB {
            // 局部最低點之後 60 ms 內的最高電平
            let minimum = nearby[index].levelDB
            let after = nearby[(index + 1)...].prefix { $0.levelTime - nearby[index].levelTime <= .milliseconds(60) }
            guard let peak = after.map(\.levelDB).max(), peak - minimum >= minimumLevelRise else { continue }
            let threshold = (minimum + peak) / 2
            var previous = nearby[index]
            for frame in after {
                if frame.levelDB >= threshold {
                    let fraction = (threshold - previous.levelDB) / (frame.levelDB - previous.levelDB)
                    let time = previous.levelTime + (frame.levelTime - previous.levelTime) * fraction
                    if window.contains(time) { result.append(time) }
                    break
                }
                previous = frame
            }
        }
        return result
    }

    /// 以 MIDI 小數表示的音高；容許八度時折算到最接近目標的八度。
    func pitch(_ frequency: Double, near target: Note) -> Double {
        let value = Double(Note.a4Midi) + 12 * log2(frequency / reference.a4)
        guard allowsOctaveShift else { return value }
        let shift = ((value - Double(target.midi)) / 12).rounded()
        return value - 12 * max(-1, min(1, shift))
    }
}
