import XCTest
import Combine
@testable import CubeTimer

final class OnboardingPreferenceTests: XCTestCase {
    func testFirstLaunchShowsGuideUntilSkippedOrCompleted() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(OnboardingPreference.shouldShowAutomatically(in: defaults))
        OnboardingPreference.markSeen(in: defaults)
        XCTAssertFalse(OnboardingPreference.shouldShowAutomatically(in: defaults))
    }

    @MainActor
    func testMarkingOnboardingSeenDoesNotChangeRestoredRunningSession() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        model.start()
        let sessionBeforeGuideDismissal = model.sessionSnapshot

        OnboardingPreference.markSeen(in: defaults)

        XCTAssertEqual(model.sessionSnapshot, sessionBeforeGuideDismissal)
        XCTAssertTrue(model.isRunning)
        model.reset()
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "OnboardingPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
