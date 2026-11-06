import Foundation
import Combine
import XCTest
@testable import CubeTimer

final class MenuBarTimerIndicatorTests: XCTestCase {
    func testStateAndPrimaryActionLabelsCoverTimerLifecycle() {
        let cases: [(Bool, Bool, Bool, String?, String, String, String)] = [
            (false, false, false, nil, "Ready", "timer", "Start"),
            (true, false, false, nil, "Running", "pause.fill", "Pause"),
            (false, true, false, nil, "Paused", "play.fill", "Resume"),
            (false, false, true, nil, "Complete", "checkmark.circle.fill", "Start"),
            (false, false, true, "Short Break", "Complete", "checkmark.circle.fill", "Start Short Break")
        ]

        for (isRunning, isPaused, isComplete, nextPhase, state, symbol, action) in cases {
            XCTAssertEqual(MenuBarTimerIndicator.stateLabel(
                isRunning: isRunning, isPaused: isPaused, isComplete: isComplete), state)
            XCTAssertEqual(MenuBarTimerIndicator.systemImage(
                isRunning: isRunning, isPaused: isPaused, isComplete: isComplete), symbol)
            XCTAssertEqual(MenuBarTimerIndicator.primaryActionTitle(
                isRunning: isRunning, isPaused: isPaused, nextPhaseName: nextPhase), action)
        }
    }
}

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

    func testResetPresetSettingsRestoresCycleTargetWithoutChangingRunningSession() {
        let suite = "CubeTimerResetPresetSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        model.setCycleTarget(8)
        model.setFlowEnabled(true)
        model.autoStartNextPhase = true
        model.setPreset(0, seconds: 420)
        model.setLongBreak(seconds: 1_200)
        model.start()
        let activeDuration = model.total

        model.resetPresetSettings()

        XCTAssertEqual(model.requestedCycleTarget, 4)
        XCTAssertEqual(model.preferences.requestedCycleTarget, 4)
        XCTAssertEqual(model.presetSeconds, TimerModel.defaultDurations)
        XCTAssertEqual(model.presetNames, TimerModel.defaultPresetNames)
        XCTAssertEqual(model.longBreakSeconds, 900)
        XCTAssertTrue(model.requestedFlowEnabled)
        XCTAssertTrue(model.autoStartNextPhase)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.total, activeDuration)
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
        model.displayStyle = .clock
        XCTAssertEqual(model.sessionSnapshot, beforeStyleChange)
        XCTAssertTrue(model.isRunning)

        model.reset()
        let reopenedModel = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertEqual(reopenedModel.displayStyle, .clock)
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

    func testMenuBarTimerPreferenceDefaultsOffPersistsAndDoesNotChangeSession() {
        let suite = "CubeTimerMenuBarPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertFalse(model.showMenuBarTimer)
        XCTAssertNil(defaults.object(forKey: TimerModel.showMenuBarTimerKey))

        model.start()
        let activeSession = model.sessionSnapshot
        var publishedValues: [Bool] = []
        let cancellable = model.$showMenuBarTimer.dropFirst().sink {
            publishedValues.append($0)
        }
        model.setShowMenuBarTimer(true)
        model.setShowMenuBarTimer(true)
        XCTAssertTrue(defaults.bool(forKey: TimerModel.showMenuBarTimerKey))
        XCTAssertEqual(publishedValues, [true])
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        model.reset()

        let reopenedModel = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertTrue(reopenedModel.showMenuBarTimer)
        reopenedModel.setShowMenuBarTimer(false)
        XCTAssertFalse(defaults.bool(forKey: TimerModel.showMenuBarTimerKey))
        reopenedModel.reset()
        withExtendedLifetime(cancellable) {}
    }

    func testDeskClockTwentyFourHourPreferenceDefaultsOffPersistsAndDoesNotChangeSession() {
        let suite = "CubeTimer24HourClockPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertFalse(model.use24HourTime)
        XCTAssertNil(defaults.object(forKey: TimerModel.use24HourTimeKey))

        model.start()
        let activeSession = model.sessionSnapshot
        model.setUse24HourTime(true)
        XCTAssertTrue(model.use24HourTime)
        XCTAssertTrue(defaults.bool(forKey: TimerModel.use24HourTimeKey))
        XCTAssertEqual(model.sessionSnapshot, activeSession)

        model.reset()
        let reopenedModel = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertTrue(reopenedModel.use24HourTime)
        reopenedModel.setUse24HourTime(false)
        XCTAssertFalse(defaults.bool(forKey: TimerModel.use24HourTimeKey))
        reopenedModel.reset()
    }

    func testDisplayFullscreenTemporarilyUsesStandardWindowWithoutSavingModeChange() {
        let suite = "CubeTimerDisplayFullscreenModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "borderlessWindow")
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        model.displayStyle = .clock
        model.start()
        let activeSession = model.sessionSnapshot

        XCTAssertTrue(model.prepareForDisplayFullscreen())
        XCTAssertTrue(model.isPreparingDisplayFullscreen)
        XCTAssertFalse(model.borderlessWindow)
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))

        let relaunchedModel = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertTrue(relaunchedModel.borderlessWindow)
        relaunchedModel.reset()

        model.didEnterDisplayFullscreen()
        XCTAssertTrue(model.isDisplayFullscreen)
        model.finishDisplayFullscreen()
        XCTAssertFalse(model.isDisplayFullscreen)
        XCTAssertFalse(model.isPreparingDisplayFullscreen)
        XCTAssertTrue(model.borderlessWindow)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))
        model.reset()
    }

    func testCubeFullscreenTemporarilyPromotesAndRestoresBorderlessWindow() {
        let suite = "CubeTimerCubeFullscreenModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "borderlessWindow")
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        model.displayStyle = .cube
        model.start()
        let activeSession = model.sessionSnapshot

        XCTAssertTrue(model.prepareForDisplayFullscreen())
        XCTAssertTrue(model.isPreparingDisplayFullscreen)
        XCTAssertFalse(model.borderlessWindow)
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))

        model.didEnterDisplayFullscreen()
        XCTAssertTrue(model.isDisplayFullscreen)
        model.finishDisplayFullscreen()
        XCTAssertFalse(model.isDisplayFullscreen)
        XCTAssertFalse(model.isPreparingDisplayFullscreen)
        XCTAssertTrue(model.borderlessWindow)
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        XCTAssertTrue(defaults.bool(forKey: "borderlessWindow"))
        model.reset()
    }
}
