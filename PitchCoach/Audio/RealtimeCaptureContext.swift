import Accelerate
import AVFAudio
import PitchDetection

/// 一個分析結果，附上分析窗結束時對應的 host time（秒，用來量測到畫面的延遲）
/// 與最近一個 IO buffer 的輸入電平（dBFS，用於電平表與除錯）。
struct CapturedFrame: Sendable {
    let frame: PitchFrame
    let hostTime: Double
    let inputLevelDB: Float
}

/// 音訊 IO 執行緒專用的擷取狀態。
///
/// 建立後只由 `AVAudioSinkNode` 的回呼呼叫 `receive`（單一執行緒），主執行緒只透過 `mailbox.drain` 取值。
/// `receive` 不配置記憶體、不等待鎖（StreamingPitchAnalyzer 與 RealtimeMailbox 皆預先配置）。
final class RealtimeCaptureContext: @unchecked Sendable {
    let mailbox = RealtimeMailbox(capacity: 256, placeholder: CapturedFrame(frame: PitchFrame(time: .zero, estimate: nil), hostTime: 0, inputLevelDB: -.infinity))
    let sampleRate: Double
    private let analyzer: StreamingPitchAnalyzer

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        analyzer = StreamingPitchAnalyzer(configuration: PitchDetectorConfiguration(sampleRate: sampleRate))
    }

    /// 回呼必須在非隔離的環境中建立：若在 @MainActor 方法內建立，Swift 6 會推斷 closure 隸屬 MainActor，
    /// 在 IO 執行緒執行時觸發隔離檢查而終止 App。
    func makeSinkNode() -> AVAudioSinkNode {
        AVAudioSinkNode { [self] timestamp, frameCount, bufferList in
            receive(timestamp: timestamp, frameCount: frameCount, bufferList: bufferList)
            return noErr
        }
    }

    func receive(timestamp: UnsafePointer<AudioTimeStamp>, frameCount: AVAudioFrameCount, bufferList: UnsafePointer<AudioBufferList>) {
        let time = timestamp.pointee
        guard time.mFlags.contains(.sampleTimeValid) else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard buffers.count > 0, let data = buffers[0].mData else { return }

        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
        let bufferHostTime = time.mFlags.contains(.hostTimeValid) ? AVAudioTime.seconds(forHostTime: time.mHostTime) : 0
        process(samples, startingAt: Int64(time.mSampleTime), hostTime: bufferHostTime)
    }

    /// `hostTime` 為第一個樣本的 host time（秒，CACurrentMediaTime 時基）。
    func process(_ samples: UnsafeBufferPointer<Float>, startingAt startPosition: Int64, hostTime bufferHostTime: Double) {
        guard let base = samples.baseAddress, !samples.isEmpty else { return }
        let bufferStartSeconds = Double(startPosition) / sampleRate
        var rms: Float = 0
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        let levelDB = 20 * log10(max(rms, 1e-9))

        analyzer.process(samples, startingAt: startPosition) { frame in
            let hostTime = bufferHostTime + (frame.time.seconds - bufferStartSeconds)
            mailbox.push(CapturedFrame(frame: frame, hostTime: hostTime, inputLevelDB: levelDB))
        }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
