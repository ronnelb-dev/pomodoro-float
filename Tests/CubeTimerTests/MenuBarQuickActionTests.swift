import XCTest
@testable import CubeTimer

@MainActor
final class MenuBarQuickActionTests: XCTestCase {
    func testCountdownRequestsEntryWithoutChangingCurrentSession() {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.startCustomCountdown(seconds: 180)
        let sessionBeforeRequest = model.sessionSnapshot
        var countdownEntryRequested = false

        MenuBarQuickAction.countdown.perform(using: model) {
            countdownEntryRequested = true
        }

        XCTAssertTrue(countdownEntryRequested)
        XCTAssertEqual(model.sessionSnapshot, sessionBeforeRequest)
    }

    func testStopwatchQuickActionStartsImmediatelyAndKeepsUndo() {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.start()

        MenuBarQuickAction.stopwatch.perform(using: model) {}

        XCTAssertEqual(model.sessionKind, .stopwatch)
        XCTAssertTrue(model.isRunning)
        XCTAssertNotNil(model.undoPresetLabel)
    }

    private func makeModel() -> (TimerModel, UserDefaults, String) {
        let suite = "MenuBarQuickActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (TimerModel(defaults: defaults, notificationsEnabled: false), defaults, suite)
    }
}
