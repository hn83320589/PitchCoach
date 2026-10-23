import Foundation
import Testing
@testable import Accompaniment
import PitchDetection

struct SongPlayerTests {
    /// 120 BPM：一拍 24000 樣本；預備拍 4 拍 = 96000 樣本。
    private let score = SongPlayerScore(
        notes: [SongPlayerScore.Note(start: 0, end: 0.5, frequency: 440), SongPlayerScore.Note(start: 1, end: 1.5, frequency: 523.25)],
        beatDuration: 0.5, countInBeats: 4, duration: 2)

    private func render(_ player: SongPlayer, count: Int, hostStart: Double = 0) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let n = min(256, count - offset)
            output.withUnsafeMutableBufferPointer {
                player.render(into: $0.baseAddress! + offset, frameCount: n, hostTime: hostStart + Double(offset) / 48000)
            }
            offset += n
        }
        return output
    }

    private func firstNonZero(_ samples: [Float], from start: Int) -> Int? {
        samples[start...].firstIndex { $0 != 0 }
    }

    @Test func countInClicksAndBeatsAreSampleAccurate() {
        let player = SongPlayer(sampleRate: 48000)
        player.settings.set(SongPlayerSettings(guideEnabled: false, clickEnabled: true))
        player.play(score)
        let samples = render(player, count: 48000 * 3)
        // 每拍的 click 在 0、24000、48000 …（預備拍 4 拍，之後歌曲的每一拍）
        for beat in 0..<6 {
            #expect(firstNonZero(samples, from: beat * 24000) == beat * 24000, "第 \(beat + 1) 拍")
        }
    }

    @Test func guideNotesStartAtScoreTimeWithRequestedPitch() throws {
        let player = SongPlayer(sampleRate: 48000)
        player.settings.set(SongPlayerSettings(guideEnabled: true, clickEnabled: false))
        player.play(score)
        let samples = render(player, count: 48000 * 4)
        // 歌曲起點在第 96000 個樣本（起音包絡從 0 開始，允許前 2 個樣本為 0）
        let firstNote = try #require(firstNonZero(samples, from: 0))
        #expect((96000...96002).contains(firstNote))
        #expect(samples[90000..<96000].allSatisfy { $0 == 0 })

        let detector = MPMPitchDetector(configuration: PitchDetectorConfiguration(sampleRate: 48000))
        let first = try #require(detector.detect(Array(samples[97000..<99048])))
        let second = try #require(detector.detect(Array(samples[(96000 + 48000 + 1000)..<(96000 + 48000 + 3048)])))
        #expect(abs(1200 * log2(first.frequency / 440)) < 0.5)
        #expect(abs(1200 * log2(second.frequency / 523.25)) < 0.5)
    }

    @Test func reportsHostTimeWhenSongStartIsRendered() throws {
        let player = SongPlayer(sampleRate: 48000)
        player.play(score)
        _ = render(player, count: 48000 * 3, hostStart: 1000)
        var reports: [SongPlayer.Report] = []
        player.reports.drain { reports.append($0) }
        // 預備拍 2 秒：歌曲起點被 render 的 host time = 1000 + 2
        let start = try #require(reports.first { $0.event == .songStarted })
        #expect(abs(start.hostTime - 1002) < 1e-9)
    }

    @Test func stopSilencesAndReportsFinishAfterSongEnds() {
        let player = SongPlayer(sampleRate: 48000)
        player.play(score)
        _ = render(player, count: 48000 * 5)           // 預備拍 2 秒 ＋ 歌曲 2 秒 ＋ 餘韻
        var events: [SongPlayer.Report.Event] = []
        player.reports.drain { events.append($0.event) }
        #expect(events == [.songStarted, .finished])

        player.play(score)
        player.stop()
        #expect(render(player, count: 4800).allSatisfy { $0 == 0 })
    }
}
