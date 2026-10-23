/// 音階練習可選的 12 個大調（升降記號皆不超過 6 個）。
public enum MajorKey: String, CaseIterable, Sendable {
    case c, g, d, a, e, b, fSharp, dFlat, aFlat, eFlat, bFlat, f

    public var tonic: PitchClass {
        PitchClass(rawValue: (Self.letterPitchClasses[tonicLetter] + tonicAccidental).floorMod(12))!
    }

    /// 例如 "B♭ 大調"。
    public var displayName: String {
        Self.letterNames[tonicLetter] + Self.accidentalSymbol(tonicAccidental) + " 大調"
    }

    /// 主音的音名字母（0 = C … 6 = B）。
    var tonicLetter: Int {
        switch self {
        case .c: 0
        case .d, .dFlat: 1
        case .e, .eFlat: 2
        case .f, .fSharp: 3
        case .g: 4
        case .a, .aFlat: 5
        case .b, .bFlat: 6
        }
    }

    /// 主音的升降（+1 升、-1 降）。
    var tonicAccidental: Int {
        switch self {
        case .fSharp: 1
        case .dFlat, .aFlat, .eFlat, .bFlat: -1
        default: 0
        }
    }

    static let letterNames = ["C", "D", "E", "F", "G", "A", "B"]
    static let letterPitchClasses = [0, 2, 4, 5, 7, 9, 11]

    static func accidentalSymbol(_ accidental: Int) -> String {
        switch accidental {
        case 1: "#"
        case 2: "𝄪"
        case -1: "♭"
        case -2: "𝄫"
        default: ""
        }
    }
}

public enum ScaleDirection: String, CaseIterable, Sendable {
    case ascending
    case ascendingDescending
}

public enum ScaleError: Error, Equatable {
    case outOfDetectionRange
}

public struct MajorScale: Hashable, Sendable {
    public let key: MajorKey
    public let startOctave: Int
    public let direction: ScaleDirection
    /// 上行 8 音；上下行 15 音（頂端主音不重複）。
    public let steps: [Note]

    public init(key: MajorKey, startOctave: Int, direction: ScaleDirection, reference: TuningReference) throws(ScaleError) {
        let ascending = Self.ascendingNotes(key: key, startOctave: startOctave)
        guard Self.fitsDetectionRange(ascending, reference: reference) else {
            throw .outOfDetectionRange
        }
        self.key = key
        self.startOctave = startOctave
        self.direction = direction
        switch direction {
        case .ascending:
            steps = ascending
        case .ascendingDescending:
            steps = ascending + ascending.dropLast().reversed()
        }
    }

    /// 在此基準下，所有音都落在偵測範圍內的起始八度。
    public static func availableStartOctaves(key: MajorKey, reference: TuningReference) -> [Int] {
        (0...8).filter { fitsDetectionRange(ascendingNotes(key: key, startOctave: $0), reference: reference) }
    }

    /// 依調號拼寫的音名，例如 F 大調的第 4 音為 "B♭4"、F# 大調的第 7 音為 "E#5"。
    public func displayName(of note: Note) -> String {
        let degree = Self.majorSteps.firstIndex(of: (note.midi - steps[0].midi).floorMod(12)) ?? 0
        let letter = (key.tonicLetter + degree) % 7
        let natural = Self.naturalMidi(letter: letter, nearMidi: note.midi)
        let accidental = note.midi - natural
        let octave = Note(midi: natural).octave
        return MajorKey.letterNames[letter] + MajorKey.accidentalSymbol(accidental) + String(octave)
    }

    private static let majorSteps = [0, 2, 4, 5, 7, 9, 11]

    private static func ascendingNotes(key: MajorKey, startOctave: Int) -> [Note] {
        let tonicMidi = (startOctave + 1) * 12 + key.tonic.rawValue
        return (majorSteps + [12]).map { Note(midi: tonicMidi + $0) }
    }

    private static func fitsDetectionRange(_ notes: [Note], reference: TuningReference) -> Bool {
        notes.allSatisfy { PitchRange.detectable.contains(NoteConverter.frequency(of: $0, reference: reference)) }
    }

    /// 與 `midi` 最接近（相差不超過 ±2 半音）的指定字母自然音。
    private static func naturalMidi(letter: Int, nearMidi midi: Int) -> Int {
        let base = midi.floorDiv(12) * 12 + MajorKey.letterPitchClasses[letter]
        return [base - 12, base, base + 12].min { abs($0 - midi) < abs($1 - midi) }!
    }
}
