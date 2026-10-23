import Foundation
import MusicTheory
import SingingEngine
import Testing
@testable import PitchCoach

@MainActor
struct SingingSupportTests {
    @Test func playerScoreFollowsTransposedTimeline() throws {
        let timeline = try SongTimeline(melody: MelodyParser.parse("C4:1 R:1 E4:2"), beatsPerMinute: 120, transposition: 2,
                                        reference: .default)
        let score = timeline.playerScore(reference: .default)
        #expect(score.countInBeats == 4)
        #expect(score.beatDuration == 0.5)
        #expect(score.duration == 2)
        #expect(score.notes.map(\.start) == [0, 1])
        #expect(score.notes.map(\.end) == [0.5, 2])
        // 移調 +2：D4、F#4（A4 = 442）
        #expect(abs(score.notes[0].frequency - NoteConverter.frequency(of: Note(midi: 62), reference: .default)) < 1e-9)
        #expect(abs(score.notes[1].frequency - NoteConverter.frequency(of: Note(midi: 66), reference: .default)) < 1e-9)
    }

    @Test func latencyCalibrationIsStoredPerRoute() {
        let suite = "SingingSupportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.setLatencyCalibration(0.042, for: "BluetoothA2DPOutput:AA-BB")
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.latencyCalibration(for: "BluetoothA2DPOutput:AA-BB") == 0.042)
        #expect(reloaded.latencyCalibration(for: "Speaker:built-in") == nil)
    }
}
