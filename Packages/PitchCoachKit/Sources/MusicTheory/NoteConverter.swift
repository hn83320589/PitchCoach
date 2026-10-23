import Foundation

/// 頻率換算出的最近音與偏差。
public struct NoteReading: Hashable, Sendable {
    public let note: Note
    /// 相對 `note` 的偏差，範圍 [-50, 50)。
    public let cents: Double
}

public enum NoteConverter {
    /// 最近的音與偏差。恰好 +50 cents 歸屬上一個音（區間為 [-50, 50)）。
    public static func reading(frequency: Double, reference: TuningReference) -> NoteReading {
        let midiValue = fractionalMidi(frequency: frequency, reference: reference)
        let nearest = (midiValue + 0.5).rounded(.down)
        return NoteReading(note: Note(midi: Int(nearest)), cents: 100 * (midiValue - nearest))
    }

    public static func frequency(of note: Note, reference: TuningReference) -> Double {
        reference.a4 * pow(2, Double(note.midi - Note.a4Midi) / 12)
    }

    /// 相對指定音的偏差，不換算到最近的音（可超過 ±50）。
    public static func cents(frequency: Double, relativeTo note: Note, reference: TuningReference) -> Double {
        1200 * log2(frequency / Self.frequency(of: note, reference: reference))
    }

    private static func fractionalMidi(frequency: Double, reference: TuningReference) -> Double {
        Double(Note.a4Midi) + 12 * log2(frequency / reference.a4)
    }
}
