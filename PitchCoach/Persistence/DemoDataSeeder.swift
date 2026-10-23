#if DEBUG
import Foundation
import MusicTheory
import PitchDetection
import PracticeEngine
import SingingEngine
import SwiftData

/// UI 測試與截圖用的示範資料（啟動參數 -seedDemoData）。
///
/// 把合成的 frame 餵給真正的 LongToneEvaluator／ScaleEvaluator，紀錄的數字與正式邏輯完全一致。
/// 學生設定：每天開著調音器自由練習 8–30 分鐘；長音逐週進步；F#、C# 習慣偏高，B♭、E 習慣偏低；
/// 唱歌時 A4 以上容易偏低，起音偶爾延遲。
@MainActor
enum DemoDataSeeder {
    private static let frameInterval = 512.0 / 48000   // 與實際 hop 相同
    private static let reference = TuningReference.default

    /// 各音級的偏差傾向（cents）。
    private static let pitchClassBias: [PitchClass: Double] = [
        .fSharp: 9, .cSharp: 7, .aSharp: -7, .e: -5, .b: 3, .a: 2, .d: -1,
    ]

    static func seed(into context: ModelContext, now: Date = Date(), calendar: Calendar = .current) throws {
        var rng = DemoRandom(seed: 20261023)
        let today = calendar.startOfDay(for: now)
        let longToneTargets = [Note(midi: 55), Note(midi: 62), Note(midi: 69), Note(midi: 76)]
        let scaleKeys: [MajorKey] = [.c, .g, .d, .bFlat]

        for daysAgo in (0..<28).reversed() {
            // 最近一週天天練，之前約 3/4 的日子有練
            guard daysAgo < 7 || rng.uniform() > 0.25 else { continue }
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let progress = 1 - Double(daysAgo) / 28          // 0 → 1，越近越穩
            var start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
            let freeMinutes = 8 + rng.uniform() * 22
            context.insert(PracticeSessionRecord(freePractice: freeMinutes * 60, startedAt: start, reference: reference))
            start = start.addingTimeInterval((freeMinutes + 2) * 60)

            for index in 0..<(1 + Int(rng.uniform() * 3)) {
                let interrupted = rng.uniform() < 0.08
                let record: PracticeSessionRecord
                if index.isMultiple(of: 2) {
                    let target = longToneTargets[Int(rng.uniform() * Double(longToneTargets.count))]
                    record = longTone(target: target, noise: 9 - 5 * progress, interrupted: interrupted, start: start, rng: &rng)
                } else {
                    let key = scaleKeys[Int(rng.uniform() * Double(scaleKeys.count))]
                    record = try scale(key: key, noise: 5 - 2 * progress, interrupted: interrupted, start: start, rng: &rng)
                }
                context.insert(record)
                start = start.addingTimeInterval(25 * 60)
            }
            if daysAgo.isMultiple(of: 2) {
                let song = Songbook.songs[Int(rng.uniform() * Double(Songbook.songs.count))]
                context.insert(try singing(song, progress: progress, start: start, rng: &rng))
            }
        }
        try context.save()
    }

    private static func cents(for note: Note) -> Double {
        pitchClassBias[note.pitchClass] ?? 0
    }

    private static func frame(_ index: Int, note: Note, cents: Double?) -> PitchFrame {
        PitchFrame(time: .nanoseconds(Int64(Double(index) * frameInterval * 1e9)), estimate: cents.map {
            PitchEstimate(frequency: NoteConverter.frequency(of: note, reference: reference) * pow(2, $0 / 1200),
                          clarity: 0.98, levelDB: -24)
        })
    }

    private static func longTone(target: Note, noise: Double, interrupted: Bool, start: Date,
                                 rng: inout DemoRandom) -> PracticeSessionRecord {
        var evaluator = LongToneEvaluator(target: target, reference: reference)
        let drift = rng.gaussian() * 2
        let frames = interrupted ? 450 : 1000
        for index in 0..<frames {
            let t = Double(index) * frameInterval
            let value: Double? = rng.uniform() < 0.04 ? nil
                : cents(for: target) + drift + noise * (0.6 * sin(t * 1.7) + 0.4 * rng.gaussian())
            if evaluator.process(frame(index, note: target, cents: value)) == .finished { break }
        }
        return PracticeSessionRecord(longTone: evaluator.result(), startedAt: start, reference: reference,
                                     interruption: interrupted ? .audioInterruption : nil)
    }

    private static func scale(key: MajorKey, noise: Double, interrupted: Bool, start: Date,
                              rng: inout DemoRandom) throws -> PracticeSessionRecord {
        let majorScale = try MajorScale(key: key, startOctave: 4, direction: .ascending, reference: reference)
        var evaluator = ScaleEvaluator(scale: majorScale, reference: reference)
        var index = 0
        let stepsToPlay = interrupted ? 4 : majorScale.steps.count
        for note in majorScale.steps.prefix(stepsToPlay) {
            let bias = cents(for: note) + rng.gaussian() * 1.5
            // 每個音最多拉 2 秒；到位後換下一個音
            for _ in 0..<Int(2 / frameInterval) {
                let value = max(-14, min(14, bias + noise * rng.gaussian()))
                let event = evaluator.process(frame(index, note: note, cents: value))
                index += 1
                if case .advanced = event { break }
                if event == .finished { break }
            }
        }
        return PracticeSessionRecord(scale: evaluator.result(), startedAt: start, activeDuration: Double(index) * frameInterval,
                                     reference: reference, interruption: interrupted ? .audioInterruption : nil)
    }
}

extension DemoDataSeeder {
    fileprivate static func singing(_ song: Song, progress: Double, start: Date, rng: inout DemoRandom) throws -> PracticeSessionRecord {
        let timeline = try SongTimeline(melody: song.melody(), beatsPerMinute: song.beatsPerMinute, reference: reference)
        var evaluator = SingingEvaluator(timeline: timeline, reference: reference, options: SingingOptions())
        for note in timeline.notes {
            // 高音偏低（越來越少）、一般音 ±8 cents 的隨機偏差；約 15% 的音起音延遲 100–150 ms
            let bias = (note.pitch.midi >= 69 ? -30 * (1 - 0.5 * progress) : 0) + rng.gaussian() * 8
            let late = rng.uniform() < 0.15 ? 0.1 + rng.uniform() * 0.05 : rng.gaussian() * 0.02
            let begin = note.start.seconds + late, end = note.end.seconds - 0.05
            var t = note.start.seconds - 0.04
            while t < end {
                let voiced = t >= begin
                let frequency = NoteConverter.frequency(of: note.pitch, reference: reference) * pow(2, (bias + rng.gaussian() * 3) / 1200)
                let time = Duration.nanoseconds(Int64(t * 1e9))
                evaluator.process(SungFrame(time: time, frequency: voiced ? frequency : nil, levelDB: voiced ? -22 : -70, levelTime: time))
                t += frameInterval
            }
        }
        let result = evaluator.result()
        return PracticeSessionRecord(singing: result, title: song.title, transposition: 0, startedAt: start,
                                     activeDuration: timeline.duration.seconds + timeline.countIn.seconds,
                                     reference: reference, interruption: nil)
    }
}

/// 固定種子的亂數（SplitMix64），示範資料可重現。
private struct DemoRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func gaussian() -> Double {
        let u1 = max(uniform(), .leastNonzeroMagnitude), u2 = uniform()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
#endif
