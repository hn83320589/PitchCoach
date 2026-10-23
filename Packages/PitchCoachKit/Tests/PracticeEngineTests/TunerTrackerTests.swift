import Foundation
import Testing
import MusicTheory
import PitchDetection
@testable import PracticeEngine

struct TunerTrackerTests {
    private func run(_ tracker: inout TunerTracker, _ input: [PitchFrame]) -> [TunerDisplayState] {
        input.map { tracker.process($0) }
    }

    private func noteName(_ state: TunerDisplayState) -> String? {
        if case .reading(let reading) = state { return reading.note.name() }
        return nil
    }

    @Test func framesWithoutPitchShowDash() {
        var tracker = TunerTracker(reference: .default)
        let states = run(&tracker, frames(from: 0, through: 100, step: 10, cents: nil))
        #expect(states.allSatisfy { $0 == .silent })
    }

    @Test func readingAppearsOnlyAfterTwoValidFrames() {
        var tracker = TunerTracker(reference: .default)
        #expect(tracker.process(frame(0, cents: 0)) == .silent)
        #expect(noteName(tracker.process(frame(10, cents: 0))) == "A4")
    }

    @Test func holdsReadingThroughShortDropoutThenReleases() {
        var tracker = TunerTracker(reference: .default)
        _ = run(&tracker, frames(from: 0, through: 50, step: 10, cents: 0))
        let dropout = run(&tracker, frames(from: 60, through: 130, step: 10, cents: nil))   // 8 個無音高 frame
        #expect(dropout.prefix(7).allSatisfy { noteName($0) == "A4" })
        #expect(dropout[7] == .silent)
    }

    @Test func singleFrameOctaveJumpIsFilteredOut() {
        var tracker = TunerTracker(reference: .default)
        var input = frames(from: 0, through: 40, step: 10, cents: 0)
        input.append(frame(50, cents: 1200))   // 單一 frame 跳到 A5
        input += frames(from: 60, through: 100, step: 10, cents: 0)
        let names = run(&tracker, input).compactMap(noteName)
        #expect(names.allSatisfy { $0 == "A4" })
    }

    @Test func jitterAcrossNoteBoundaryDoesNotFlipNote() {
        var tracker = TunerTracker(reference: .default)
        _ = run(&tracker, frames(from: 0, through: 30, step: 10, cents: 40))
        // A4 +49 / +51 交替（+50 是 A4 與 A#4 的分界）
        let jitter = (4..<60).map { frame($0 * 10, cents: $0.isMultiple(of: 2) ? 49 : 51) }
        let names = run(&tracker, jitter).compactMap(noteName)
        #expect(names.allSatisfy { $0 == "A4" })
    }

    @Test func largeDeviationSwitchesImmediatelyButModerateOneWaits100ms() {
        var tracker = TunerTracker(reference: .default)
        _ = run(&tracker, frames(from: 0, through: 30, step: 10, cents: 0))
        // 相對 A4 +80 cents（> 65）：中位數濾波需要 2 個 frame 才會反應，之後立即換音
        #expect(noteName(tracker.process(frame(40, cents: 80))) == "A4")
        #expect(noteName(tracker.process(frame(50, cents: 80))) == "A#4")

        var moderate = TunerTracker(reference: .default)
        _ = run(&moderate, frames(from: 0, through: 30, step: 10, cents: 0))
        // 相對 A4 +55 cents：中位數在 t = 50 ms 首次超過 50，持續滿 100 ms（t = 150）才換音
        let states = run(&moderate, frames(from: 40, through: 160, step: 10, cents: 55))
        let names = states.compactMap(noteName)
        #expect(names.prefix(11).allSatisfy { $0 == "A4" })   // t = 40…140
        #expect(names[11] == "A#4")                           // t = 150
    }

    @Test func displayedCentsAreSmoothedAndResetOnNoteChange() throws {
        var tracker = TunerTracker(reference: .default)
        _ = run(&tracker, frames(from: 0, through: 100, step: 10, cents: 0))
        let states = run(&tracker, frames(from: 110, through: 600, step: 10, cents: 20))
        guard case .reading(let early) = states[2], case .reading(let late) = states.last! else {
            Issue.record("應有讀數"); return
        }
        #expect(early.cents > 0 && early.cents < 20)
        #expect(abs(late.cents - 20) < 0.01)

        // 換音時直接跳到新值，不從舊音滑過去
        let switched = run(&tracker, frames(from: 610, through: 630, step: 10, cents: 300))
        guard case .reading(let reading) = switched.last! else { Issue.record("應有讀數"); return }
        #expect(reading.note.name() == "C5")
        #expect(abs(reading.cents) < 0.01)
    }

    @Test func readingFollowsTuningReference() throws {
        var tracker = TunerTracker(reference: try TuningReference(a4: 440))
        let input = [442.0, 442.0, 442.0].enumerated().map {
            PitchFrame(time: .milliseconds($0.offset * 10), estimate: PitchEstimate(frequency: $0.element, clarity: 1, levelDB: -20))
        }
        guard case .reading(let reading) = run(&tracker, input).last! else { Issue.record("應有讀數"); return }
        #expect(reading.note.name() == "A4")
        #expect(abs(reading.cents - 7.85) < 0.01)
        #expect(abs(reading.frequency - 442) < 0.01)
    }
}
