import MusicTheory

public struct MelodyParseError: Error, Equatable, Sendable {
    public enum Reason: Error, Equatable, Sendable {
        case empty
        case invalidNoteName(String)
        case missingOctave
        case invalidOctave(String)
        case missingDuration
        case invalidDuration(String)
        case outOfRange
    }

    /// 第幾個音符（從 1 起算，休止符也算一個）；空白輸入為 0。
    public let noteIndex: Int
    public let token: String
    public let reason: Reason

    public var message: String {
        if reason == .empty { return "旋律是空的" }
        let detail: String = switch reason {
        case .empty: ""
        case .invalidNoteName(let name): "無法辨識的音名「\(name)」（請用 A–G，或 R 表示休止符）"
        case .missingOctave: "缺少八度數字（例如 C4）"
        case .invalidOctave(let text): "八度「\(text)」不是整數"
        case .missingDuration: "缺少拍數（格式為「音名:拍數」，例如 C4:1）"
        case .invalidDuration(let text): "拍數「\(text)」必須是大於 0、不超過 \(Int(MelodyParser.maximumBeats)) 的數字"
        case .outOfRange: "音高超出可練習的範圍（C2–C7）"
        }
        return "第 \(noteIndex) 個音符「\(token)」：\(detail)"
    }
}

/// 自訂旋律格式：以空白或換行分隔的 `音名[#|b|♯|♭]八度:拍數`，休止符為 `R:拍數`。
/// 例如 `C4:1 D4:1 E4:2 R:1 F#4:0.5`。
public enum MelodyParser {
    public static let maximumBeats = 16.0
    /// C2–C7：涵蓋歌唱音域（C3–C6）移調 ±6 半音後的範圍。
    public static let allowedMidiRange = 36...96

    private static let letterPitchClasses: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    public static func parse(_ text: String) throws(MelodyParseError) -> Melody {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            throw MelodyParseError(noteIndex: 0, token: "", reason: .empty)
        }
        var notes: [MelodyNote] = []
        for (offset, token) in tokens.enumerated() {
            do {
                notes.append(try parseToken(token))
            } catch {
                throw MelodyParseError(noteIndex: offset + 1, token: token, reason: error)
            }
        }
        return Melody(notes: notes)
    }

    private static func parseToken(_ token: String) throws(MelodyParseError.Reason) -> MelodyNote {
        guard let colon = token.firstIndex(of: ":") else { throw .missingDuration }
        let pitchText = token[..<colon]
        let beatsText = String(token[token.index(after: colon)...])
        guard let beats = Double(beatsText), beats.isFinite, beats > 0, beats <= maximumBeats else {
            throw .invalidDuration(beatsText)
        }
        guard let first = pitchText.first else { throw .invalidNoteName("") }
        let letter = Character(first.uppercased())
        if letter == "R", pitchText.count == 1 {
            return MelodyNote(pitch: nil, beats: beats)
        }
        guard let pitchClass = letterPitchClasses[letter] else { throw .invalidNoteName(String(first)) }

        var rest = pitchText.dropFirst()
        var accidental = 0
        if let symbol = rest.first, ["#", "♯", "b", "♭"].contains(symbol) {
            accidental = (symbol == "#" || symbol == "♯") ? 1 : -1
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty else { throw .missingOctave }
        guard let octave = Int(rest) else { throw .invalidOctave(String(rest)) }

        let midi = (octave + 1) * 12 + pitchClass + accidental
        guard allowedMidiRange.contains(midi) else { throw .outOfRange }
        return MelodyNote(pitch: Note(midi: midi), beats: beats)
    }
}
