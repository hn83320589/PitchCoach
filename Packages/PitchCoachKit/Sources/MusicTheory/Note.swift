/// 十二平均律中的一個音級（不含八度）。
public enum PitchClass: Int, CaseIterable, Sendable {
    case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b
}

/// 黑鍵要用升記號還是降記號拼寫。
public enum Spelling: Sendable {
    case sharps
    case flats
}

/// 以 MIDI 編號表示的音，A4 = 69，C4（中央 C）= 60。
public struct Note: Hashable, Sendable, Comparable {
    public static let a4Midi = 69

    public let midi: Int

    public init(midi: Int) {
        self.midi = midi
    }

    public var pitchClass: PitchClass {
        PitchClass(rawValue: midi.floorMod(12))!
    }

    /// 科學音高記號的八度（C4 = 中央 C）。
    public var octave: Int {
        midi.floorDiv(12) - 1
    }

    /// 例如 "C#5"；`.flats` 時為 "D♭5"。
    public func name(spelling: Spelling = .sharps) -> String {
        let names = spelling == .sharps ? Self.sharpNames : Self.flatNames
        return names[pitchClass.rawValue] + String(octave)
    }

    public static func < (lhs: Note, rhs: Note) -> Bool {
        lhs.midi < rhs.midi
    }

    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
}

extension Int {
    /// 向負無限大取整的除法（Swift 的 `/` 向零取整，對負數的八度計算不正確）。
    func floorDiv(_ divisor: Int) -> Int {
        let quotient = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    func floorMod(_ divisor: Int) -> Int {
        self - floorDiv(divisor) * divisor
    }
}
