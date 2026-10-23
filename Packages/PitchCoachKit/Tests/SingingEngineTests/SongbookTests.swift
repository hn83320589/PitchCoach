import Testing
import MusicTheory
@testable import SingingEngine

struct SongbookTests {
    @Test func everyBuiltInSongParsesAndHasPublicDomainSource() throws {
        #expect(Songbook.songs.count >= 5)
        for song in Songbook.songs {
            let melody = try song.melody()
            #expect(melody.notes.count >= 16, "\(song.title)")
            #expect(!song.origin.isEmpty && song.sourceURL.hasPrefix("https://"), "\(song.title)")
        }
    }

    @Test func builtInSongsStayInVoiceRangeAndSurviveFullTransposition() throws {
        for song in Songbook.songs {
            let pitches = try song.melody().notes.compactMap(\.pitch?.midi)
            #expect(pitches.allSatisfy { (48...84).contains($0) }, "\(song.title) 應在 C3–C6")
            for semitones in [-6, 6] {
                #expect(throws: Never.self) {
                    try SongTimeline(melody: song.melody(), beatsPerMinute: song.beatsPerMinute,
                                     transposition: semitones, reference: .default)
                }
            }
        }
    }
}
