import Foundation
import XCTest
@testable import CubeTimer

final class TimerSessionPersistenceTests: XCTestCase {
    func testValidVersionedSessionRoundTripsThroughAdapter() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimerSessionPersistence(defaults: defaults)
        let session = SavedTimerSession(version: 5, state: .paused,
                                        selectedPreset: 2, phase: .focus,
                                        total: 1_500, deadline: nil,
                                        pausedRemaining: 735,
                                        focusesInCycle: 2,
                                        completedFocusTotal: 6,
                                        cycleTarget: 4)

        persistence.save(session)

        XCTAssertEqual(persistence.load(defaultFlowEnabled: false,
                                        defaultPomodoroModeEnabled: false)?.pausedRemaining,
                       735)
    }

    func testInvalidVersionedSessionIsRemovedByAdapter() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimerSessionPersistence(defaults: defaults)
        let session = SavedTimerSession(version: 5, state: .paused,
                                        selectedPreset: 99, phase: .focus,
                                        total: 300, deadline: nil,
                                        pausedRemaining: 30,
                                        cycleTarget: 4)
        let encoded = try! JSONEncoder().encode(session)
        defaults.set(encoded, forKey: SavedTimerSession.key)

        XCTAssertNil(persistence.load(defaultFlowEnabled: false,
                                      defaultPomodoroModeEnabled: false))
        XCTAssertNil(defaults.data(forKey: SavedTimerSession.key))
    }

    func testVersionSixRequiresAnExplicitSessionKind() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimerSessionPersistence(defaults: defaults)
        let session = SavedTimerSession(version: 6, state: .paused,
                                        selectedPreset: 0, phase: .focus,
                                        total: 300, deadline: nil,
                                        pausedRemaining: 120, cycleTarget: 4)
        persistence.save(session)
        XCTAssertNil(persistence.load(defaultFlowEnabled: false,
                                      defaultPomodoroModeEnabled: false))
    }

    func testVersionSevenAcceptsTheSixthPresetSlot() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimerSessionPersistence(defaults: defaults)
        let session = SavedTimerSession(version: 7, state: .paused,
                                        selectedPreset: 5, phase: .focus,
                                        total: 3_600, deadline: nil,
                                        pausedRemaining: 2_400, cycleTarget: 4,
                                        sessionKind: .presetCountdown)

        persistence.save(session)

        XCTAssertEqual(persistence.load(defaultFlowEnabled: false,
                                        defaultPomodoroModeEnabled: false)?.selectedPreset, 5)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "CubeTimerSessionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
