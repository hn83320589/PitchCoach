import Testing
@testable import MusicTheory

struct TuningReferenceTests {
    @Test func defaultReferenceIs442Hz() {
        #expect(TuningReference.default.a4 == 442)
    }

    @Test func acceptsRangeBounds() throws {
        #expect(try TuningReference(a4: 415).a4 == 415)
        #expect(try TuningReference(a4: 466).a4 == 466)
    }

    @Test func rejectsValuesOutsideRange() {
        for value in [414.9, 466.1, 0, .nan, .infinity] {
            #expect(throws: TuningReferenceError.self) {
                try TuningReference(a4: value)
            }
        }
    }
}
