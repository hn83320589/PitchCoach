import Foundation
import Testing
@testable import PitchDetection
import SignalKit

struct StreamingPitchAnalyzerTests {
    private func collectFrames(
        _ analyzer: StreamingPitchAnalyzer, _ samples: [Float], chunkSizes: [Int], startingAt start: Int64 = 0
    ) -> [PitchFrame] {
        var frames: [PitchFrame] = []
        var offset = 0
        var chunkIndex = 0
        while offset < samples.count {
            let size = min(chunkSizes[chunkIndex % chunkSizes.count], samples.count - offset)
            samples[offset..<(offset + size)].withUnsafeBufferPointer { chunk in
                analyzer.process(chunk, startingAt: start + Int64(offset)) { frames.append($0) }
            }
            offset += size
            chunkIndex += 1
        }
        return frames
    }

    @Test func emitsFirstFrameWhenWindowFillsThenEveryHop() {
        // 取樣率 1000 Hz 讓時間戳是整數毫秒，方便精確比較
        let analyzer = StreamingPitchAnalyzer(configuration: PitchDetectorConfiguration(sampleRate: 1000), hopSize: 512)
        let silence = [Float](repeating: 0, count: 2048 + 512 * 3)
        let frames = collectFrames(analyzer, silence, chunkSizes: [silence.count])
        #expect(frames.map(\.time) == [.milliseconds(2048), .milliseconds(2560), .milliseconds(3072), .milliseconds(3584)])
        #expect(frames.allSatisfy { $0.estimate == nil })
    }

    @Test func arbitraryChunkSizesProduceIdenticalFrames() {
        let configuration = PitchDetectorConfiguration(sampleRate: 48000)
        let signal = SignalGenerator.sine(frequency: 440, sampleRate: 48000, count: 10_000)
        let whole = collectFrames(StreamingPitchAnalyzer(configuration: configuration), signal, chunkSizes: [signal.count])
        let chunked = collectFrames(StreamingPitchAnalyzer(configuration: configuration), signal, chunkSizes: [1, 37, 256, 1000, 4096])
        #expect(whole.count == (10_000 - 2048) / 512 + 1)
        #expect(chunked == whole)
    }

    @Test func frameEstimateUsesMostRecentWindow() throws {
        let configuration = PitchDetectorConfiguration(sampleRate: 48000)
        // 前 2048 個樣本是 220 Hz，之後換成 330 Hz：第 5 個 frame 的窗完全落在 330 Hz 段
        let signal = SignalGenerator.sine(frequency: 220, sampleRate: 48000, count: 2048)
            + SignalGenerator.sine(frequency: 330, sampleRate: 48000, count: 2048)
        let frames = collectFrames(StreamingPitchAnalyzer(configuration: configuration), signal, chunkSizes: [256])
        let detector = MPMPitchDetector(configuration: configuration)
        let expected = detector.detect(Array(signal[2048..<4096]))
        #expect(frames[4].estimate == expected)
        #expect(abs(try #require(frames[4].estimate).frequency - 330) < 0.01)
    }

    @Test func discontinuityInSamplePositionResetsHistory() {
        let analyzer = StreamingPitchAnalyzer(configuration: PitchDetectorConfiguration(sampleRate: 1000), hopSize: 512)
        let block = [Float](repeating: 0, count: 2048)
        var frames = collectFrames(analyzer, block, chunkSizes: [2048], startingAt: 0)
        #expect(frames.map(\.time) == [.milliseconds(2048)])

        // 跳過 100 個樣本（例如引擎重啟），必須重新累積完整的窗才輸出
        frames = collectFrames(analyzer, Array(block.prefix(1000)), chunkSizes: [1000], startingAt: 2148)
        #expect(frames.isEmpty)
        frames = collectFrames(analyzer, block, chunkSizes: [2048], startingAt: 3148)
        #expect(frames.map(\.time) == [.milliseconds(4196), .milliseconds(4708)])
    }
}
