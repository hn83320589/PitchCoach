import QuartzCore

/// 以螢幕更新頻率呼叫 `onFrame`，參數為這一幀預計顯示的時間（CACurrentMediaTime 時基）。
@MainActor
final class DisplayLinkDriver: NSObject {
    private var link: CADisplayLink?
    private let onFrame: @MainActor (_ targetTimestamp: CFTimeInterval) -> Void

    init(onFrame: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// CADisplayLink 會強參照 target，必須呼叫 stop 才會釋放。
    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onFrame(link.targetTimestamp)
    }
}
