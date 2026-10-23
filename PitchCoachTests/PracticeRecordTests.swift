import Foundation
import MusicTheory
import PitchDetection
import PracticeEngine
import SingingEngine
import SwiftData
import Testing
@testable import PitchCoach

@MainActor
struct PracticeRecordTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRepository() throws -> PracticeRepository {
        let container = try ModelContainer(for: PracticeSessionRecord.self, NoteStatRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return PracticeRepository(container: container)
    }

    private func frame(_ ms: Int, cents: Double?, note: Note) -> PitchFrame {
        PitchFrame(time: .milliseconds(ms), estimate: cents.map {
            PitchEstimate(frequency: NoteConverter.frequency(of: note, reference: .default) * pow(2, $0 / 1200), clarity: 1, levelDB: -20)
        })
    }

    @Test func longToneRecordRoundTripsToSameSummaryAndCurve() throws {
        let repository = try makeRepository()
        let target = Note(midi: 69)
        var evaluator = LongToneEvaluator(target: target, reference: .default, duration: .milliseconds(200))
        for (index, cents) in [3.0, 5, nil, 12, -4, 8, 60, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].enumerated() {
            _ = evaluator.process(frame(index * 10, cents: cents, note: target))
        }
        let result = evaluator.result()
        try repository.save(PracticeSessionRecord(longTone: result, startedAt: start, reference: .default, interruption: nil))

        let stored = try #require(try repository.records().first)
        #expect(stored.summary == SessionSummary(longTone: result, startedAt: start))
        #expect(stored.targetMidi == 69)
        #expect(stored.curve.count == result.curve.count)
        for (saved, original) in zip(stored.curve, result.curve) {
            #expect((saved == nil) == (original == nil))
            if let saved, let original { #expect(abs(saved - original) < 1e-4) }
        }
    }

    @Test func scaleRecordKeepsKeyStepsAndInterruptionReason() throws {
        let repository = try makeRepository()
        let scale = try MajorScale(key: .bFlat, startOctave: 4, direction: .ascendingDescending, reference: .default)
        var evaluator = ScaleEvaluator(scale: scale, reference: .default)
        for ms in stride(from: 0, through: 300, by: 10) { _ = evaluator.process(frame(ms, cents: 7, note: scale.steps[0])) }
        let result = evaluator.result()
        let record = PracticeSessionRecord(scale: result, startedAt: start, activeDuration: 0.3,
                                           reference: .default, interruption: .routeChange)
        try repository.save(record)

        let stored = try #require(try repository.records().first)
        #expect(stored.scaleKey == .bFlat)
        #expect(stored.startOctave == 4)
        #expect(stored.direction == .ascendingDescending)
        #expect(stored.status == .interrupted)
        #expect(stored.interruptionReason == .routeChange)
        #expect(stored.reachedSteps == 1)
        #expect(stored.totalSteps == 15)
        #expect(stored.summary.noteStats.count == 1)
        #expect(stored.sortedNoteStats.first?.reached == true)
    }

    @Test func recordsAreFilteredByStartDateAndSortedNewestFirst() throws {
        let repository = try makeRepository()
        let result = LongToneEvaluator(target: Note(midi: 69), reference: .default).result()
        for offset: TimeInterval in [0, 86_400, 2 * 86_400] {
            try repository.save(PracticeSessionRecord(longTone: result, startedAt: start + offset, reference: .default, interruption: nil))
        }
        let recent = try repository.records(since: start + 3600)
        #expect(recent.map(\.startedAt) == [start + 2 * 86_400, start + 86_400])
        #expect(try repository.summaries(since: start).count == 3)
    }

    @Test func freePracticeRecordStoresDurationOnly() throws {
        let repository = try makeRepository()
        try repository.save(PracticeSessionRecord(freePractice: 754, startedAt: start, reference: .default))
        let stored = try #require(try repository.records().first)
        #expect(stored.summary == SessionSummary(startedAt: start, activeDuration: 754, kind: .freePractice, status: .completed))
        #expect(stored.noteStats.isEmpty)
    }

    @Test func singingRecordKeepsEveryNoteButSummaryFiltersImplausibleDeviations() throws {
        let repository = try makeRepository()
        let timeline = try SongTimeline(melody: MelodyParser.parse("C4:1 D4:1 E4:1"), beatsPerMinute: 60, reference: .default)
        var evaluator = SingingEvaluator(timeline: timeline, reference: .default, options: SingingOptions())
        for (index, cents) in [(0, 6.0), (1, -1200.0)] {
            for ms in stride(from: index * 1000, to: (index + 1) * 1000, by: 10) {
                evaluator.process(SungFrame(time: .milliseconds(ms), frequency: NoteConverter.frequency(of: timeline.notes[index].pitch,
                                            reference: .default) * pow(2, cents / 1200), levelDB: -20, levelTime: .milliseconds(ms)))
            }
        }
        try repository.save(PracticeSessionRecord(singing: evaluator.result(), title: "測試", transposition: 2, startedAt: start,
                                                  activeDuration: 3, reference: .default, interruption: nil))
        let stored = try #require(try repository.records().first)
        #expect(stored.songTitle == "測試")
        #expect(stored.transposition == 2)
        #expect(stored.sortedNoteStats.count == 3)                       // 沒唱的 E4 也保留
        #expect(abs(stored.sortedNoteStats[1].meanCents + 1200) < 1)     // 實際偏差保留供細節顯示
        #expect(stored.summary.noteStats.map(\.note.midi) == [60])       // 統計只收合理偏差
        #expect(stored.summary.noteOutcomes.map(\.accurate) == [true, false, false])
        #expect(stored.summary == SessionSummary(singing: evaluator.result(), title: "測試", startedAt: start, activeDuration: 3))
    }
}
