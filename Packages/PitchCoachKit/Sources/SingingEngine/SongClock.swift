import Foundation
import PitchDetection

/// 換算成「學生聽到的歌曲時間」的分析 frame。
public struct SungFrame: Equatable, Sendable {
    /// 分析窗中心對應的歌曲時間（歌曲起點為 0，預備拍為負值）。
    public let time: Duration
    public let frequency: Double?
    /// 最近一個 hop 的電平（dBFS）。
    public let levelDB: Double
    /// 電平所屬 hop 的中心對應的歌曲時間。
    public let levelTime: Duration

    public init(time: Duration, frequency: Double?, levelDB: Double, levelTime: Duration) {
        self.time = time
        self.frequency = frequency
        self.levelDB = levelDB
        self.levelTime = levelTime
    }
}

/// 伴奏與收音的時間對齊（docs/SINGING_MODE.md §7）。所有時間皆為 host time（秒）。
///
/// 歌曲時間 = 聲音到達麥克風的時間 − 學生聽到歌曲起點的時間 − 校正值
/// - 聲音到達麥克風 = 分析窗中心的 host time − 輸入延遲
/// - 學生聽到歌曲起點 = 歌曲起點被 render 的 host time ＋ 輸出延遲（由呼叫端加總後傳入）
public struct SongClock: Equatable, Sendable {
    public let heardSongStartHostTime: Double
    public let inputLatency: Double
    /// 依路由的回授校正值（秒），正值表示實際聽到的比估計的晚。
    public let calibrationOffset: Double
    public let windowDuration: Double
    public let hopDuration: Double

    public init(heardSongStartHostTime: Double, inputLatency: Double, calibrationOffset: Double,
                windowDuration: Double, hopDuration: Double) {
        self.heardSongStartHostTime = heardSongStartHostTime
        self.inputLatency = inputLatency
        self.calibrationOffset = calibrationOffset
        self.windowDuration = windowDuration
        self.hopDuration = hopDuration
    }

    /// `windowEndHostTime` 為分析窗最後一個樣本對應的 host time。
    public func sungFrame(_ frame: PitchFrame, windowEndHostTime: Double) -> SungFrame {
        // 用窗中心而非窗尾：分析窗反映的是過去一整個窗長的聲音，用窗尾會讓起音晚半個窗長（約 21 ms）
        let center = windowEndHostTime - windowDuration / 2
        let levelCenter = windowEndHostTime - hopDuration / 2
        return SungFrame(time: songTime(center), frequency: frame.frequency, levelDB: frame.levelDB, levelTime: songTime(levelCenter))
    }

    private func songTime(_ hostTime: Double) -> Duration {
        .nanoseconds(Int64(((hostTime - inputLatency - heardSongStartHostTime - calibrationOffset) * 1e9).rounded()))
    }
}

extension Duration {
    var timeInterval: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
