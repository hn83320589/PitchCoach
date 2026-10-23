import Foundation
import Testing
@testable import PitchCoach

@MainActor
struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultReferenceIs442Hz() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.referenceA4 == 442)
        #expect(settings.reference.a4 == 442)
    }

    @Test func referenceIsPersistedAndClamped() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.referenceA4 = 440
        #expect(AppSettings(defaults: defaults).referenceA4 == 440)

        settings.referenceA4 = 500
        #expect(settings.referenceA4 == 466)
        #expect(AppSettings(defaults: defaults).referenceA4 == 466)
    }
}
