import Accompaniment
import AVFAudio

/// 建立帶即時回呼的音訊節點。
///
/// 回呼必須在非隔離的環境中建立：若在 @MainActor 方法內寫 closure，Swift 6 會推斷它隸屬 MainActor，
/// 在 IO 執行緒執行時觸發隔離檢查而終止 App（M4 曾發生）。
enum AudioNodeFactory {
    static func sourceNode(format: AVAudioFormat, renderer: any RealtimeRenderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count > 0, let data = buffers[0].mData else { return noErr }
            renderer.render(into: data.assumingMemoryBound(to: Float.self), frameCount: Int(frameCount))
            return noErr
        }
    }
}
