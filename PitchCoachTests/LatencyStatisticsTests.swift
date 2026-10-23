import Testing
@testable import PitchCoach

struct LatencyStatisticsTests {
    @Test func percentilesUseNearestRank() {
        var statistics = LatencyStatistics(capacity: 100)
        for value in 1...100 { statistics.record(Double(value) / 1000) }
        #expect(statistics.count == 100)
        #expect(statistics.percentile(50) == 0.050)
        #expect(statistics.percentile(95) == 0.095)
    }

    @Test func keepsOnlyMostRecentSamples() {
        var statistics = LatencyStatistics(capacity: 3)
        [0.5, 0.01, 0.02, 0.03].forEach { statistics.record($0) }
        #expect(statistics.count == 3)
        #expect(statistics.percentile(100) == 0.03)
    }

    @Test func emptyStatisticsHaveNoPercentile() {
        #expect(LatencyStatistics(capacity: 10).percentile(50) == nil)
    }
}
