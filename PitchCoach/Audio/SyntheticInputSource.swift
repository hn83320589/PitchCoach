#if DEBUG
import Accompaniment
import Foundation
import MusicTheory
import os
import QuartzCore

/// UI 測試用的合成輸入情境，以啟動參數 `-syntheticScenario <名稱>` 選擇。
enum SyntheticScenario: String {
    /// A4 +3 cents，穩定。
    case tuner
    /// A4 +4 cents，±8 cents、週期 3 秒的緩慢擺動。
    case longTone
    /// C 大調上行（C4–C5）循環，每音 0.6 秒，各音帶不同偏差。
    case scale
    /// 跟著 SongPlayer 的時間軸演唱（見 SyntheticSongScript）。
    case singing

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> SyntheticScenario? {
        guard let index = arguments.firstIndex(of: "-syntheticScenario"), index + 1 < arguments.count else { return nil }
        return SyntheticScenario(rawValue: arguments[index + 1])
    }

    /// 音階情境各音的偏差（cents）：E4 +12、B4 −9、A4 +6 為偏差最大的 3 個音。
    static let scaleDetune: [Double] = [0, -3, 12, 4, -2, 6, -9, 1]

    func frequency(at time: Double, reference: TuningReference) -> Double {
        func pitch(_ note: Note, cents: Double) -> Double {
            NoteConverter.frequency(of: note, reference: reference) * pow(2, cents / 1200)
        }
        switch self {
        case .tuner:
            return pitch(Note(midi: 69), cents: 3)
        case .longTone:
            return pitch(Note(midi: 69), cents: 4 + 8 * sin(2 * .pi * time / 3))
        case .scale:
            let steps = [0, 2, 4, 5, 7, 9, 11, 12]
            let index = Int(time / 0.6) % steps.count
            return pitch(Note(midi: 60 + steps[index]), cents: Self.scaleDetune[index])
        case .singing:
            return 0   // 由 SyntheticSongScript 依 host time 決定
        }
    }
}

/// 合成歌聲要演唱的樂譜與歌曲起點（host time）。主執行緒設定，合成訊號的佇列讀取。
final class SyntheticSongScript: @unchecked Sendable {
    /// 各音的偏差（cents）循環：第 4 個音偏高 32、第 7 個音偏低 30，其餘在 ±25 以內。
    static let detune: [Double] = [0, 4, -6, 32, 0, -3, -30, 8]

    private let lock = OSAllocatedUnfairLock<(score: SongPlayerScore, start: Double)?>(initialState: nil)

    func set(_ value: (score: SongPlayerScore, start: Double)?) {
        lock.withLockUnchecked { $0 = value }
    }

    /// 每個音符的最後 8% 停頓（換氣），讓每個音都有清楚的起音。
    func frequency(atHostTime hostTime: Double) -> Double? {
        guard let (score, start) = lock.withLockUnchecked({ $0 }) else { return nil }
        let time = hostTime - start
        guard let index = score.notes.firstIndex(where: { time >= $0.start && time < $0.end }) else { return nil }
        let note = score.notes[index]
        guard time < note.end - 0.08 * (note.end - note.start) else { return nil }
        return note.frequency * pow(2, Self.detune[index % Self.detune.count] / 1200)
    }
}

/// 以計時器產生合成訊號，取代麥克風送進同一條偵測管線（RealtimeCaptureContext 之後完全相同）。
final class SyntheticInputSource: @unchecked Sendable {
    private let scenario: SyntheticScenario
    private let reference: TuningReference
    private let context: RealtimeCaptureContext
    private let song: SyntheticSongScript?
    private let queue = DispatchQueue(label: "PitchCoach.SyntheticInput", qos: .userInitiated)
    private let chunkSize: Int
    private let buffer: UnsafeMutablePointer<Float>
    private var timer: DispatchSourceTimer?
    private var position: Int64 = 0
    private var phase = 0.0

    init(scenario: SyntheticScenario, reference: TuningReference, context: RealtimeCaptureContext, song: SyntheticSongScript? = nil) {
        self.scenario = scenario
        self.reference = reference
        self.context = context
        self.song = song
        chunkSize = Int(context.sampleRate / 100)   // 每 10 ms 一段
        buffer = .allocate(capacity: chunkSize)
    }

    deinit {
        timer?.cancel()
        buffer.deallocate()
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.renderChunk() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func renderChunk() {
        let sampleRate = context.sampleRate
        let hostTime = CACurrentMediaTime()
        for i in 0..<chunkSize {
            let time = Double(position + Int64(i)) / sampleRate
            let frequency: Double
            if let song {
                guard let sung = song.frequency(atHostTime: hostTime + Double(i) / sampleRate) else {
                    buffer[i] = 0
                    continue
                }
                frequency = sung
            } else {
                frequency = scenario.frequency(at: time, reference: reference)
            }
            let increment = frequency / sampleRate
            // 基音＋遞減泛音，近似樂器音色
            buffer[i] = Float(0.25 * sin(2 * .pi * phase) + 0.12 * sin(4 * .pi * phase) + 0.06 * sin(6 * .pi * phase))
            phase += increment
            if phase >= 1 { phase -= 1 }
        }
        context.process(UnsafeBufferPointer(start: buffer, count: chunkSize), startingAt: position, hostTime: hostTime)
        position += Int64(chunkSize)
    }
}
#endif
