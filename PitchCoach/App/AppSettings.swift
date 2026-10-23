import Foundation
import MusicTheory
import Observation

/// 使用者設定，存在 UserDefaults。
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let referenceA4 = "referenceA4"
        static let showsLatencyOverlay = "showsLatencyOverlay"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// A4 基準頻率（整數 Hz），寫入時夾在 415–466。
    var referenceA4: Int {
        didSet {
            let clamped = Int(TuningReference(clamping: Double(referenceA4)).a4)
            if clamped != referenceA4 {
                referenceA4 = clamped
                return
            }
            defaults.set(referenceA4, forKey: Key.referenceA4)
        }
    }

    /// 開發用：在調音器上顯示延遲統計。
    var showsLatencyOverlay: Bool {
        didSet { defaults.set(showsLatencyOverlay, forKey: Key.showsLatencyOverlay) }
    }

    var reference: TuningReference {
        TuningReference(clamping: Double(referenceA4))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Key.referenceA4) as? Int
        referenceA4 = Int(TuningReference(clamping: Double(stored ?? Int(TuningReference.default.a4))).a4)
        showsLatencyOverlay = defaults.bool(forKey: Key.showsLatencyOverlay)
    }
}
