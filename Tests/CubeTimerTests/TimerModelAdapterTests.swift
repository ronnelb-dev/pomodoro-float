import Foundation
import XCTest
@testable import CubeTimer

@MainActor
final class TimerModelAdapterTests: XCTestCase {
    func testCommandsUpdatePublishedSnapshotAndPreferences() {
        let suite = "CubeTimerModelAdapterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)

        model.setPreset(0, seconds: 420)
        XCTAssertEqual(model.preferences.presetSeconds[0], 420)
        XCTAssertEqual(model.sessionSnapshot.presetSeconds[0], 420)
        XCTAssertEqual(model.remaining, 420)

        model.start()
        XCTAssertTrue(model.sessionSnapshot.isRunning)
        model.reset()
    }

    func testDisplayStyleDefaultsPersistsAndDoesNotChangeTimerSession() {
        let suite = "CubeTimerDisplayStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertEqual(model.displayStyle, .cube)

        model.start()
        let beforeStyleChange = model.sessionSnapshot
        model.displayStyle = .digital
        XCTAssertEqual(model.sessionSnapshot, beforeStyleChange)
        XCTAssertTrue(model.isRunning)

        model.reset()
        let reopenedModel = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertEqual(reopenedModel.displayStyle, .digital)
        reopenedModel.reset()
    }

    func testInvalidDisplayStyleDefaultsToCube() {
        let suite = "CubeTimerInvalidDisplayStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("unknown", forKey: TimerModel.displayStyleKey)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertEqual(model.displayStyle, .cube)
        model.reset()
    }
}
