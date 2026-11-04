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

    func testDigitalFullscreenTemporarilyUsesStandardWindowWithoutSavingModeChange() {
        let suite = "CubeTimerDigitalFullscreenModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "borderlessWindow")
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        model.displayStyle = .digital
        model.start()
        let activeSession = model.sessionSnapshot

        XCTAssertTrue(model.prepareForDigitalFullscreen())
        XCTAssertTrue(model.isPreparingDigitalFullscreen)
        XCTAssertFalse(model.borderlessWindow)
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))

        let relaunchedModel = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertTrue(relaunchedModel.borderlessWindow)
        relaunchedModel.reset()

        model.didEnterDigitalFullscreen()
        XCTAssertTrue(model.isDigitalFullscreen)
        model.finishDigitalFullscreen()
        XCTAssertFalse(model.isDigitalFullscreen)
        XCTAssertFalse(model.isPreparingDigitalFullscreen)
        XCTAssertTrue(model.borderlessWindow)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))
        model.reset()
    }

    func testDigitalFullscreenPromotionIsRejectedForCubeAndLeavesWindowModeUntouched() {
        let suite = "CubeTimerCubeFullscreenModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "borderlessWindow")
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)

        XCTAssertFalse(model.prepareForDigitalFullscreen())
        XCTAssertTrue(model.borderlessWindow)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))
        model.reset()
    }
}
