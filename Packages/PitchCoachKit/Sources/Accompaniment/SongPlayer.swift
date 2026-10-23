import Foundation
import PitchDetection

/// SongPlayer 要播放的樂譜，時間以秒表示、相對歌曲起點（預備拍之後的第一拍）。
public struct SongPlayerScore: Equatable, Sendable {
    public struct Note: Equatable, Sendable {
        public let start: Double
        public let end: Double
        public let frequency: Double

        public init(start: Double, end: Double, frequency: Double) {
            self.start = start
            self.end = end
            self.frequency = frequency
        }
    }

    public let notes: [Note]
    public let beatDuration: Double
    public let countInBeats: Int
    public let duration: Double

    public init(notes: [Note], beatDuration: Double, countInBeats: Int, duration: Double) {
        self.notes = notes
        self.beatDuration = beatDuration
        self.countInBeats = countInBeats
        self.duration = duration
    }
}

public struct SongPlayerSettings: Equatable, Sendable {
    public var guideEnabled: Bool
    public var clickEnabled: Bool
    public var guideVolume: Float
    public var clickVolume: Float

    public init(guideEnabled: Bool = true, clickEnabled: Bool = true, guideVolume: Float = 0.5, clickVolume: Float = 0.5) {
        self.guideEnabled = guideEnabled
        self.clickEnabled = clickEnabled
        self.guideVolume = guideVolume
        self.clickVolume = clickVolume
    }
}

/// 歌唱模式的伴奏：預備拍 click、每拍 click，以及類似鋼琴（快速起音、指數衰減）的旋律提示音。
///
/// - 全部以樣本計數，樣本精準
/// - 歌曲起點（預備拍結束）被 render 時，以 `reports` 回報該樣本的 host time，作為伴奏與收音
///   對齊的基準（docs/SINGING_MODE.md §7.1）
/// - 提示音快速衰減：喇叭外放時，音符中段被麥克風收到的提示音已大幅減弱
///
/// `render` 不配置記憶體，只能由音訊 IO 執行緒呼叫；`play`／`stop` 由主執行緒呼叫。
public final class SongPlayer: TimedRealtimeRenderer, @unchecked Sendable {
    public struct Report: Sendable {
        public enum Event: Sendable, Equatable {
            case songStarted
            case finished
        }

        public let event: Event
        public let hostTime: Double
    }

    private struct Command: Sendable {
        var generation = 0
        var score: SongPlayerScore?
    }

    public let settings = RealtimeParameter(SongPlayerSettings())
    public let reports = RealtimeMailbox(capacity: 16, placeholder: Report(event: .finished, hostTime: 0))

    private let sampleRate: Double
    private let command = RealtimeParameter(Command())
    private let click: ClickSound
    private let attackSamples: Double
    private let decayPerSample: Double
    private let releaseSamples: Double

    // 以下只有 IO 執行緒存取
    private var generation = 0
    private var score: SongPlayerScore?
    private var position: Int64 = 0          // 自預備拍開始的樣本數
    private var noteIndex = 0
    private var notePhase = 0.0
    private var clickPosition = Int.max
    private var finished = false

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        click = ClickSound(sampleRate: sampleRate)
        attackSamples = 0.005 * sampleRate
        decayPerSample = exp(-1 / (0.35 * sampleRate))     // 時間常數 0.35 秒
        releaseSamples = 0.03 * sampleRate
    }

    /// 從下一個 render 週期開始播放預備拍，接著播放歌曲。
    public func play(_ score: SongPlayerScore) {
        let current = command.value
        command.set(Command(generation: current.generation + 1, score: score))
    }

    public func stop() {
        let current = command.value
        command.set(Command(generation: current.generation + 1, score: nil))
    }

    public func render(into output: UnsafeMutablePointer<Float>, frameCount: Int, hostTime: Double) {
        let current = command.readForRealtime()
        if current.generation != generation {
            generation = current.generation
            score = current.score
            position = 0
            noteIndex = 0
            notePhase = 0
            clickPosition = .max
            finished = false
        }
        guard let score, !finished else {
            output.initialize(repeating: 0, count: frameCount)
            return
        }
        let settings = self.settings.readForRealtime()
        let beatSamples = score.beatDuration * sampleRate
        let countInSamples = Int64((Double(score.countInBeats) * beatSamples).rounded())
        let songEnd = countInSamples + Int64((score.duration * sampleRate).rounded())
        let tailEnd = songEnd + Int64(0.5 * sampleRate)

        for i in 0..<frameCount {
            let p = position + Int64(i)
            if p == countInSamples {
                reports.push(Report(event: .songStarted, hostTime: hostTime + Double(i) / sampleRate))
            }
            if p == tailEnd {
                reports.push(Report(event: .finished, hostTime: hostTime + Double(i) / sampleRate))
                finished = true
                output.advanced(by: i).initialize(repeating: 0, count: frameCount - i)
                break
            }

            var value: Float = 0
            // 每拍的 click（預備拍與歌曲期間）
            if p < songEnd, Double(p).truncatingRemainder(dividingBy: beatSamples) < 1 {
                clickPosition = 0
            }
            if clickPosition < click.length {
                if settings.clickEnabled { value += click.samples[clickPosition] * settings.clickVolume }
                clickPosition += 1
            }
            // 旋律提示音
            if settings.guideEnabled, let tone = guideSample(at: p - countInSamples, score: score) {
                value += tone * settings.guideVolume
            }
            output[i] = value
        }
        position += Int64(frameCount)
    }

    /// 歌曲時間 s（樣本）時的提示音；沒有音符時為 nil。
    private func guideSample(at s: Int64, score: SongPlayerScore) -> Float? {
        guard s >= 0 else { return nil }
        while noteIndex < score.notes.count, Double(s) >= score.notes[noteIndex].end * sampleRate + releaseSamples {
            noteIndex += 1
            notePhase = 0
        }
        guard noteIndex < score.notes.count else { return nil }
        let note = score.notes[noteIndex]
        let start = note.start * sampleRate, end = note.end * sampleRate
        let local = Double(s) - start
        guard local >= 0 else { return nil }

        var envelope = min(1, local / attackSamples) * pow(decayPerSample, local)
        if Double(s) >= end { envelope *= max(0, 1 - (Double(s) - end) / releaseSamples) }
        let value = sin(2 * .pi * notePhase) + 0.4 * sin(4 * .pi * notePhase) + 0.15 * sin(6 * .pi * notePhase)
        notePhase += note.frequency / sampleRate
        if notePhase >= 1 { notePhase -= 1 }
        return Float(value / 1.55 * envelope)
    }
}

/// 節拍器與 SongPlayer 共用的 click：指數衰減的固定種子噪音，沒有明確週期，漏進麥克風時不會被當成音高。
/// 樣本在 init 配置、deinit 釋放，建立後唯讀。
final class ClickSound: @unchecked Sendable {
    let samples: UnsafeMutablePointer<Float>
    let length: Int

    init(sampleRate: Double) {
        length = Int(sampleRate * 0.015)
        samples = .allocate(capacity: length)
        var state: UInt32 = 0x9E37_79B9
        for i in 0..<length {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            let noise = Float(state) / Float(UInt32.max) * 2 - 1
            let envelope = Float(exp(-Double(i) / (sampleRate * 0.003)))
            samples[i] = (noise == 0 ? 0.5 : noise) * envelope
        }
    }

    deinit {
        samples.deallocate()
    }
}
