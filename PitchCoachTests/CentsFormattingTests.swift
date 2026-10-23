import Testing
@testable import PitchCoach

struct CentsFormattingTests {
    @Test func valuesRoundingToZeroHaveNoSign() {
        #expect(ReadoutRow.formatCents(-0.3) == "0 ¢")
        #expect(ReadoutRow.formatCents(0.4) == "0 ¢")
        #expect(ReadoutRow.formatCents(-0.6) == "-1 ¢")
        #expect(ReadoutRow.formatCents(12.5) == "+13 ¢")
    }
}
