import MusicTheory

/// 某個音在一段時間內的平均偏差。
public struct NoteDeviation: Equatable, Sendable {
    public let note: Note
    public let meanCents: Double
    public let frameCount: Int
    /// 出現在幾次練習中。
    public let sessionCount: Int

    public init(note: Note, meanCents: Double, frameCount: Int, sessionCount: Int) {
        self.note = note
        self.meanCents = meanCents
        self.frameCount = frameCount
        self.sessionCount = sessionCount
    }
}
