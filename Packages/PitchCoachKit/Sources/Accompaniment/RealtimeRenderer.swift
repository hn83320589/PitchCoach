/// 在音訊 IO 執行緒上產生單聲道樣本的合成器。
public protocol RealtimeRenderer: AnyObject, Sendable {
    func render(into output: UnsafeMutablePointer<Float>, frameCount: Int)
}

extension MetronomeSynthesizer: RealtimeRenderer {}
extension DroneSynthesizer: RealtimeRenderer {}

/// 需要知道每個 buffer 的 host time 的合成器（例如要回報歌曲起點被播放的時間）。
public protocol TimedRealtimeRenderer: AnyObject, Sendable {
    /// `hostTime` 為 buffer 第一個樣本的 host time（秒，CACurrentMediaTime 時基）。
    func render(into output: UnsafeMutablePointer<Float>, frameCount: Int, hostTime: Double)
}
