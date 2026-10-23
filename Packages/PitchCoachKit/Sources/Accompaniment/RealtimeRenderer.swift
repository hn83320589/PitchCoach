/// 在音訊 IO 執行緒上產生單聲道樣本的合成器。
public protocol RealtimeRenderer: AnyObject, Sendable {
    func render(into output: UnsafeMutablePointer<Float>, frameCount: Int)
}

extension MetronomeSynthesizer: RealtimeRenderer {}
extension DroneSynthesizer: RealtimeRenderer {}
