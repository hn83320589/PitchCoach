import Testing
@testable import PracticeEngine

struct PracticeLifecycleTests {
    @Test func interruptionWhileRunningMarksSessionInterruptedWithReason() {
        for reason in PracticeInterruptionReason.allCases {
            var lifecycle = PracticeLifecycle()
            lifecycle.handle(.start)
            let changed = lifecycle.handle(.interrupt(reason))
            #expect(changed)
            #expect(lifecycle.state == .interrupted(reason))
            #expect(lifecycle.state.isTerminal)
        }
    }

    @Test func eventsBeforeStartAreIgnored() {
        var lifecycle = PracticeLifecycle()
        let results = [lifecycle.handle(.interrupt(.audioInterruption)), lifecycle.handle(.complete), lifecycle.handle(.cancel)]
        #expect(results == [false, false, false])
        #expect(lifecycle.state == .ready)
    }

    @Test func terminalStatesIgnoreLateEvents() {
        var completed = PracticeLifecycle()
        completed.handle(.start)
        completed.handle(.complete)
        let lateInterrupt = completed.handle(.interrupt(.routeChange))
        #expect(!lateInterrupt)
        #expect(completed.state == .completed)

        var interrupted = PracticeLifecycle()
        interrupted.handle(.start)
        interrupted.handle(.interrupt(.appBackgrounded))
        let results = [interrupted.handle(.complete), interrupted.handle(.start)]
        #expect(results == [false, false])
        #expect(interrupted.state == .interrupted(.appBackgrounded))
    }

    @Test func cancelFromRunningEndsWithoutInterruption() {
        var lifecycle = PracticeLifecycle()
        lifecycle.handle(.start)
        let restarted = lifecycle.handle(.start)
        let cancelled = lifecycle.handle(.cancel)
        #expect(!restarted)
        #expect(cancelled)
        #expect(lifecycle.state == .cancelled)
    }
}
