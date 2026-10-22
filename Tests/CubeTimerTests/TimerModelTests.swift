import AVFoundation
import Foundation
import XCTest
@testable import CubeTimer

@MainActor
final class TimerModelTests: XCTestCase {
    func testClockJumpsDoNotChangeRunningTimeAndRebaseWallDeadline() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, timeSource: source)
        defer { model.reset() }
        model.start()
        source.advance(30)
        source.jumpWall(3_600)
        model.refresh()
        XCTAssertEqual(model.remaining, 270, accuracy: 0.01)
        XCTAssertEqual(saved(in: defaults)!.deadline!.timeIntervalSince(source.wallNow),
                       270, accuracy: 0.01)
        source.advance(10)
        source.jumpWall(-7_200)
        model.refresh()
        XCTAssertEqual(model.remaining, 260, accuracy: 0.01)
        XCTAssertEqual(saved(in: defaults)!.deadline!.timeIntervalSince(source.wallNow),
                       260, accuracy: 0.01)
        XCTAssertEqual(notifications.scheduled.first!, 300, accuracy: 0.01)
    }

    func testSameBootRelaunchUsesMonotonicDeadlineDespiteClockChange() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        let first = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        first.start()
        source.advance(90)
        source.jumpWall(3_600)
        let notifications = RecordingNotifications()
        let restored = TimerModel(defaults: defaults, now: source.wallNow,
                                  notificationClient: notifications, timeSource: source)
        defer { restored.reset(); first.reset() }
        XCTAssertTrue(restored.isRunning)
        XCTAssertEqual(restored.remaining, 210, accuracy: 0.01)
        XCTAssertEqual(notifications.pending!.seconds, 210, accuracy: 0.01)
        XCTAssertEqual(saved(in: defaults)?.version, 5)
    }

    func testDifferentBootUsesWallDeadlineFallback() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstClock = ManualTimerTimeSource()
        let first = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: firstClock.wallNow, timeSource: firstClock)
        first.start()
        let secondClock = ManualTimerTimeSource(wallNow: firstClock.wallNow.addingTimeInterval(60),
                                                continuousNow: 10, bootSessionID: "boot-B")
        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: secondClock.wallNow, timeSource: secondClock)
        defer { restored.reset(); first.reset() }
        XCTAssertEqual(restored.remaining, 240, accuracy: 0.01)
    }

    func testVersionOneSessionMigratesWithoutLosingTime() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 0,
                               phase: .focus, total: 300,
                               deadline: source.wallNow.addingTimeInterval(180),
                               pausedRemaining: nil), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        XCTAssertEqual(model.remaining, 180, accuracy: 0.01)
        XCTAssertEqual(saved(in: defaults)?.version, 5)
        XCTAssertEqual(saved(in: defaults)?.bootSessionID, source.bootSessionID)
        XCTAssertNotNil(saved(in: defaults)?.continuousDeadline)
    }

    func testVersionTwoSessionMigratesWithItsPomodoroPhase() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 2, state: .paused, selectedPreset: 0,
                               phase: .breakTime, total: 300,
                               deadline: nil, pausedRemaining: 123), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        XCTAssertTrue(model.flowEnabled)
        XCTAssertTrue(model.pomodoroModeEnabled)
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.remaining, 123)
        XCTAssertEqual(saved(in: defaults)?.version, 5)
        model.reset()
    }

    func testMissedSleepBoundaryAndUndoUseMonotonicTimeThroughWallJump() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, timeSource: source)
        defer { model.reset() }
        model.start()
        model.prepareForSleep()
        source.advance(1_520)
        source.jumpWall(3_600)
        model.resumeAfterSleep()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertNil(notifications.pending)

        model.startNextPhase()
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.remaining, 300, accuracy: 0.01)
        XCTAssertEqual(notifications.pending!.seconds, 300, accuracy: 0.01)

        source.advance(10)
        model.selectAndStartPreset(1)
        source.jumpWall(-7_200)
        source.advance(2)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.remaining, 288, accuracy: 0.01)
        XCTAssertEqual(notifications.pending!.seconds, 288, accuracy: 0.01)
    }

    func testEditingPausedPresetPreservesSessionUntilReset() {
        let model = makeModel()
        model.start()
        model.refresh(at: Date().addingTimeInterval(20))
        model.pause()
        let remaining = model.remaining
        let total = model.total

        model.setPreset(0, seconds: 420)
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.total, total)
        XCTAssertEqual(model.remaining, remaining)
        model.reset()
        XCTAssertEqual(model.total, 420)
        XCTAssertEqual(model.remaining, 420)
    }

    func testEditingIdlePresetUpdatesDisplayedDuration() {
        let model = makeModel()
        model.setPreset(0, seconds: 420)
        XCTAssertEqual(model.total, 420)
        XCTAssertEqual(model.remaining, 420)
    }

    func testRunningSessionRestoresItsDeadlineAndNotification() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: now.addingTimeInterval(900), pausedRemaining: nil),
             in: defaults)
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: now, notificationClient: notifications)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.remaining, 900, accuracy: 0.01)
        XCTAssertEqual(notifications.cancelCount, 0)
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(notifications.scheduled[0], 900, accuracy: 0.01)
        model.reset()
    }

    func testStartPauseResumeAndResetKeepSavedSessionInSync() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertNil(defaults.data(forKey: SavedTimerSession.key))

        model.start()
        XCTAssertEqual(saved(in: defaults)?.state, .running)
        XCTAssertNotNil(saved(in: defaults)?.deadline)

        model.pause()
        XCTAssertEqual(saved(in: defaults)?.state, .paused)
        XCTAssertEqual(saved(in: defaults)?.pausedRemaining, model.remaining)

        let restored = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertTrue(restored.isPaused)
        XCTAssertEqual(restored.remaining, model.remaining)
        restored.start()
        XCTAssertEqual(saved(in: defaults)?.state, .running)
        restored.reset()
        XCTAssertNil(defaults.data(forKey: SavedTimerSession.key))
        model.reset()
    }

    func testPausedSessionRestoresWithoutSchedulingNotification() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        save(SavedTimerSession(version: 1, state: .paused, selectedPreset: 4,
                               phase: .focus, total: 3_600,
                               deadline: nil, pausedRemaining: 1_234), in: defaults)
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, notificationClient: notifications)
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.selectedPreset, 4)
        XCTAssertEqual(model.total, 3_600)
        XCTAssertEqual(model.remaining, 1_234)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testExpiredPomodoroWhileClosedWaitsForUserToStartBreak() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let now = Date()
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: now.addingTimeInterval(-20), pausedRemaining: nil),
             in: defaults)
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: now, notificationClient: notifications)
        XCTAssertTrue(model.isComplete)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(model.alertText, "Focus complete")
        XCTAssertTrue(notifications.scheduled.isEmpty)

        model.start()
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertEqual(model.total, 300)
        XCTAssertEqual(notifications.scheduled.count, 1)
        model.reset()
    }

    func testWakePastFocusBoundaryWaitsForBreak() {
        let (model, defaults, boundary, notifications, sound) = runningPomodoro()
        defer { model.reset() }

        model.refresh(at: boundary.addingTimeInterval(20), afterWake: true)

        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.nextPhaseName, "Short Break")
        XCTAssertEqual(model.alertText, "Focus elapsed while away · Start Short Break")
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testDelayedRefreshDoesNotSkipMultipleBoundaries() {
        let (model, defaults, boundary, notifications, sound) = runningPomodoro()
        defer { model.reset() }

        model.refresh(at: boundary.addingTimeInterval(300 + 1_500 + 30))

        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testLongSleepWaitsAtFirstBoundary() {
        let (model, defaults, boundary, notifications, sound) = runningPomodoro()
        defer { model.reset() }

        model.refresh(at: boundary.addingTimeInterval(4 * 1_800 + 20), afterWake: true)

        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testExactPomodoroBoundariesStartNextPhaseAtFullDuration() {
        let (model, defaults, boundary, _, sound) = runningPomodoro()
        defer { model.reset() }

        model.refresh(at: boundary)
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.remaining, 300, accuracy: 0.01)
        XCTAssertEqual(model.alertText, "Focus complete")
        XCTAssertEqual(sound.playCount, 1)

        model.refresh(at: boundary.addingTimeInterval(300), afterWake: true)
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
        model.startNextPhase()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remaining, 1_500, accuracy: 0.01)
        XCTAssertEqual(sound.playCount, 1)
    }

    func testManualHandoffPreferencePersistsAndWaitsAfterOnTimeCompletion() {
        let (model, defaults, boundary, notifications, sound) = runningPomodoro()
        defer { model.reset() }
        XCTAssertTrue(model.autoStartNextPhase)
        model.autoStartNextPhase = false
        model.refresh(at: boundary)

        XCTAssertEqual(model.phase, .focus)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.nextPhaseName, "Short Break")
        XCTAssertEqual(model.remaining, 0)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
        XCTAssertEqual(sound.playCount, 1)

        model.startNextPhase()
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.total, 300)
        XCTAssertEqual(notifications.pending?.title, "Short Break session complete")
        XCTAssertFalse(defaults.bool(forKey: "autoStartNextPhase"))
        let reopened = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertFalse(reopened.autoStartNextPhase)
        XCTAssertEqual(reopened.phase, .breakTime)
        XCTAssertTrue(reopened.isRunning)
    }

    func testSkipRunningBreakPreparesFocusAndCancelsNotification() {
        let (model, defaults, boundary, notifications, _) = runningPomodoro()
        defer { model.reset() }
        model.refresh(at: boundary)
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertTrue(model.canSkipBreak)
        XCTAssertNotNil(notifications.pending)

        model.skipBreak()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.remaining, TimeInterval(model.presetSeconds[2]))
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isPaused)
        XCTAssertFalse(model.canSkipBreak)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(defaults.integer(forKey: "selectedPreset"), 2)

        model.start()
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(notifications.pending?.title, "Focus session complete")
    }

    func testSkipPausedBreakLeavesFocusReady() {
        let (model, _, boundary, notifications, _) = runningPomodoro()
        defer { model.reset() }
        model.refresh(at: boundary)
        model.pause()
        XCTAssertTrue(model.isPaused)
        model.skipBreak()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.remaining, TimeInterval(model.presetSeconds[2]))
        XCTAssertFalse(model.isPaused)
        XCTAssertNil(notifications.pending)
    }

    func testFourCompletedFocusesLeadToSeparateLongBreak() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, timeSource: source)
        defer { model.reset() }
        model.setPreset(2, seconds: 1)
        model.setPreset(0, seconds: 1)
        model.setLongBreak(seconds: 7)
        model.start()

        for completed in 1...4 {
            source.advance(1)
            model.refresh()
            XCTAssertEqual(model.completedFocusTotal, completed)
            if completed < 4 {
                XCTAssertEqual(model.focusesInCycle, completed)
                XCTAssertEqual(model.phase, .breakTime)
                XCTAssertEqual(model.total, 1)
                source.advance(1)
                model.refresh()
                XCTAssertEqual(model.phase, .focus)
            } else {
                XCTAssertEqual(model.phase, .longBreak)
                XCTAssertEqual(model.focusesInCycle, 0)
                XCTAssertEqual(model.total, 7)
                XCTAssertEqual(model.selectedPreset, 0)
                XCTAssertEqual(notifications.pending?.title, "Long Break session complete")
            }
        }
        XCTAssertEqual(model.presetSeconds[0], 1)
        source.advance(7)
        model.refresh()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.completedFocusTotal, 4)
    }

    func testConfigurableTwoAndEightFocusCyclesWithManualHandoff() {
        for target in [2, 8] {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "flowEnabled")
            let source = ManualTimerTimeSource()
            let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                                   now: source.wallNow, timeSource: source)
            model.autoStartNextPhase = false
            model.setPreset(2, seconds: 1)
            model.setPreset(0, seconds: 1)
            model.setCycleTarget(target)
            XCTAssertEqual(model.cycleTarget, target)
            XCTAssertEqual(model.focusProgressLabel, "0/\(target)")
            model.start()

            for completed in 1...target {
                source.advance(1)
                model.refresh()
                XCTAssertEqual(model.focusesInCycle, completed)
                XCTAssertEqual(model.completedFocusTotal, completed)
                XCTAssertEqual(model.nextPhaseName,
                               completed == target ? "Long Break" : "Short Break")
                if completed < target {
                    model.startNextPhase()
                    source.advance(1)
                    model.refresh()
                    XCTAssertEqual(model.nextPhaseName, "Focus")
                    model.startNextPhase()
                }
            }
            XCTAssertTrue(model.longBreakDue)
            model.startNextPhase()
            XCTAssertEqual(model.phase, .longBreak)
            XCTAssertEqual(model.focusesInCycle, 0)
            model.reset()
        }
    }

    func testCycleTargetChangeWaitsUntilDueLongBreakIsSkipped() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.autoStartNextPhase = false
        model.setPreset(2, seconds: 1)
        model.setPreset(0, seconds: 1)
        model.start()
        source.advance(1)
        model.refresh()
        model.setCycleTarget(2)
        XCTAssertEqual(model.cycleTarget, 4)
        XCTAssertEqual(model.requestedCycleTarget, 2)
        XCTAssertTrue(model.cycleTargetChangePending)
        XCTAssertEqual(model.focusProgressLabel, "1/4")

        for _ in 2...4 {
            model.startNextPhase()
            source.advance(1)
            model.refresh()
            model.startNextPhase()
            source.advance(1)
            model.refresh()
        }
        XCTAssertEqual(model.nextPhaseName, "Long Break")
        XCTAssertEqual(model.focusProgressLabel, "4/4")
        model.skipBreak()
        XCTAssertEqual(model.cycleTarget, 2)
        XCTAssertEqual(model.focusProgressLabel, "0/2")
        XCTAssertFalse(model.cycleTargetChangePending)
        model.reset()
    }

    func testPendingCycleTargetPersistsThroughRelaunchAndLongBreakCompletion() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let first = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        first.setPreset(2, seconds: 1)
        first.setPreset(0, seconds: 1)
        first.setLongBreak(seconds: 2)
        first.start()
        source.advance(1)
        first.refresh()
        first.pause()
        first.setCycleTarget(8)

        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertEqual(restored.cycleTarget, 4)
        XCTAssertEqual(restored.requestedCycleTarget, 8)
        XCTAssertEqual(restored.focusProgressLabel, "1/4")
        XCTAssertEqual(saved(in: defaults)?.version, 5)
        XCTAssertEqual(saved(in: defaults)?.cycleTarget, 4)
        restored.start()
        for _ in 2...4 {
            source.advance(1)
            restored.refresh()
            source.advance(1)
            restored.refresh()
        }
        XCTAssertEqual(restored.phase, .longBreak)
        XCTAssertEqual(restored.cycleTarget, 4)
        source.advance(2)
        restored.refresh()
        XCTAssertEqual(restored.phase, .focus)
        XCTAssertEqual(restored.cycleTarget, 8)
        XCTAssertEqual(restored.focusProgressLabel, "0/8")
        restored.reset()
    }

    func testCycleTargetChangedDuringLongBreakWaitsForItsCompletion() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 5, state: .running, selectedPreset: 0,
                               phase: .longBreak, total: 3,
                               deadline: source.wallNow.addingTimeInterval(3),
                               pausedRemaining: nil, bootSessionID: source.bootSessionID,
                               continuousDeadline: source.continuousNow + 3,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 0, completedFocusTotal: 4,
                               cycleTarget: 4), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.setCycleTarget(2)
        XCTAssertEqual(model.phase, .longBreak)
        XCTAssertEqual(model.cycleTarget, 4)
        XCTAssertEqual(model.requestedCycleTarget, 2)
        source.advance(3)
        model.refresh()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.cycleTarget, 2)
        XCTAssertEqual(model.completedFocusTotal, 4)
        model.reset()
    }

    func testUndoOneOffRestoresCurrentCycleAndKeepsNextTarget() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 5, state: .running, selectedPreset: 2,
                               phase: .focus, total: 20,
                               deadline: source.wallNow.addingTimeInterval(20),
                               pausedRemaining: nil, bootSessionID: source.bootSessionID,
                               continuousDeadline: source.continuousNow + 20,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 1, completedFocusTotal: 1,
                               cycleTarget: 4), in: defaults)
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, timeSource: source)
        model.setCycleTarget(2)
        model.selectAndStartPreset(4)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.focusProgressLabel, "1/4")
        XCTAssertEqual(model.requestedCycleTarget, 2)
        XCTAssertTrue(model.cycleTargetChangePending)
        XCTAssertEqual(notifications.pending?.title, "Focus session complete")
        model.reset()
    }

    func testShortBreakLabelPreservesSavedPhaseValue() {
        XCTAssertEqual(SessionPhase.breakTime.rawValue, "BREAK")
        XCTAssertEqual(SessionPhase.breakTime.displayLabel, "SHORT BREAK")
    }

    func testManualFourthFocusWaitsForLongBreakAndCanSkipIt() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.autoStartNextPhase = false
        model.setPreset(2, seconds: 1)
        model.setPreset(0, seconds: 1)
        model.start()
        for completed in 1...4 {
            source.advance(1)
            model.refresh()
            XCTAssertTrue(model.isComplete)
            if completed < 4 {
                XCTAssertEqual(model.nextPhaseName, "Short Break")
                model.startNextPhase()
                source.advance(1)
                model.refresh()
                XCTAssertEqual(model.nextPhaseName, "Focus")
                model.startNextPhase()
            }
        }
        XCTAssertEqual(model.focusesInCycle, 4)
        XCTAssertEqual(model.nextPhaseName, "Long Break")
        XCTAssertEqual(model.skipBreakName, "Skip Long Break")
        XCTAssertTrue(model.canSkipBreak)
        model.skipBreak()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.focusesInCycle, 0)
        XCTAssertEqual(model.completedFocusTotal, 4)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.remaining, 1)
    }

    func testMissedFourthFocusWaitsForLongBreakWithoutSound() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, soundClient: sound, timeSource: source)
        defer { model.reset() }
        model.setPreset(2, seconds: 1)
        model.start()
        // Keep the current focus running while the preceding three completions
        // are restored from a saved v4 session below.
        model.reset()
        let savedSession = SavedTimerSession(version: 4, state: .running,
            selectedPreset: 2, phase: .focus, total: 1,
            deadline: source.wallNow.addingTimeInterval(1), pausedRemaining: nil,
            bootSessionID: source.bootSessionID,
            continuousDeadline: source.continuousNow + 1,
            activeFlowEnabled: true, pomodoroModeEnabled: true,
            focusesInCycle: 3, completedFocusTotal: 3)
        save(savedSession, in: defaults)
        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, soundClient: sound, timeSource: source)
        source.advance(10)
        restored.refresh(afterWake: true)
        XCTAssertTrue(restored.isComplete)
        XCTAssertEqual(restored.focusesInCycle, 4)
        XCTAssertEqual(restored.completedFocusTotal, 4)
        XCTAssertEqual(restored.nextPhaseName, "Long Break")
        XCTAssertEqual(sound.playCount, 0)
        restored.reset()
    }

    func testClosedFourthFocusIsCountedExactlyOnceAndMigrated() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 4, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1,
                               deadline: source.wallNow.addingTimeInterval(1),
                               pausedRemaining: nil, bootSessionID: source.bootSessionID,
                               continuousDeadline: source.continuousNow + 1,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 3, completedFocusTotal: 3), in: defaults)
        source.advance(10)
        let first = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        XCTAssertTrue(first.isComplete)
        XCTAssertEqual(first.focusesInCycle, 4)
        XCTAssertEqual(first.completedFocusTotal, 4)
        XCTAssertEqual(saved(in: defaults)?.version, 5)
        let reopened = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertEqual(reopened.completedFocusTotal, 4)
        XCTAssertEqual(reopened.nextPhaseName, "Long Break")

        save(SavedTimerSession(version: 3, state: .completed, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: nil, pausedRemaining: nil,
                               activeFlowEnabled: true, pomodoroModeEnabled: true), in: defaults)
        let migrated = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertEqual(migrated.completedFocusTotal, 0)
        XCTAssertEqual(migrated.focusesInCycle, 0)
        migrated.reset()
    }

    func testDueLongBreakSurvivesOneOffAndModeChanges() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 4, state: .completed, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: nil, pausedRemaining: nil,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 4, completedFocusTotal: 4), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.selectAndStartPreset(2)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertFalse(model.flowEnabled)
        XCTAssertEqual(model.focusesInCycle, 4)
        let reopened = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertTrue(reopened.hasSuspendedPomodoro)
        XCTAssertEqual(reopened.focusesInCycle, 4)
        XCTAssertTrue(reopened.resumePomodoro())
        XCTAssertEqual(reopened.nextPhaseName, "Long Break")
        reopened.setFlowEnabled(false)
        XCTAssertEqual(reopened.completedFocusTotal, 4)
        reopened.setFlowEnabled(true)
        XCTAssertEqual(reopened.phase, .longBreak)
        XCTAssertEqual(reopened.focusesInCycle, 4)
        XCTAssertTrue(reopened.canSkipBreak)
        reopened.reset()
        model.reset()
    }

    func testFiveMinutePresetDuringLongBreakIsAOneOff() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 4, state: .running, selectedPreset: 0,
                               phase: .longBreak, total: 900,
                               deadline: source.wallNow.addingTimeInterval(600),
                               pausedRemaining: nil, bootSessionID: source.bootSessionID,
                               continuousDeadline: source.continuousNow + 600,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 0, completedFocusTotal: 4), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        XCTAssertTrue(model.presetBecomesOneOff(0))
        model.selectPreset(0)
        XCTAssertFalse(model.flowEnabled)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertEqual(model.total, 300)
        XCTAssertTrue(model.resumePomodoro())
        XCTAssertEqual(model.phase, .longBreak)
        XCTAssertEqual(model.remaining, 600, accuracy: 0.01)
        XCTAssertEqual(model.completedFocusTotal, 4)
    }

    func testLongBreakEditPreservesRunningTimeAndChangesNextFreshStart() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 4, state: .completed, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: nil, pausedRemaining: nil,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 4, completedFocusTotal: 4), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        XCTAssertEqual(model.longBreakSeconds, 900)
        model.setLongBreak(seconds: 7)
        model.startNextPhase()
        XCTAssertEqual(model.phase, .longBreak)
        XCTAssertEqual(model.total, 7)
        source.advance(2)
        model.refresh()
        model.setLongBreak(seconds: 11)
        XCTAssertEqual(model.total, 7)
        XCTAssertEqual(model.remaining, 5, accuracy: 0.01)
        model.pause()
        model.setLongBreak(seconds: 12)
        XCTAssertEqual(model.remaining, 5, accuracy: 0.01)
        model.reset()
        XCTAssertEqual(model.total, 12)
        XCTAssertEqual(model.remaining, 12)
        model.setPreset(0, seconds: 4)
        XCTAssertEqual(model.total, 12)
        XCTAssertEqual(model.remaining, 12)
        let reopened = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertEqual(reopened.longBreakSeconds, 12)
        XCTAssertEqual(reopened.total, 12)
        XCTAssertEqual(reopened.completedFocusTotal, 4)
    }

    func testInterruptedFocusDoesNotCountAndUndoRestoresCycle() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 4, state: .running, selectedPreset: 2,
                               phase: .focus, total: 20,
                               deadline: source.wallNow.addingTimeInterval(20),
                               pausedRemaining: nil, bootSessionID: source.bootSessionID,
                               continuousDeadline: source.continuousNow + 20,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 3, completedFocusTotal: 9), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.selectAndStartPreset(1)
        XCTAssertEqual(model.completedFocusTotal, 9)
        XCTAssertEqual(model.focusesInCycle, 3)
        source.advance(2)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remaining, 18, accuracy: 0.01)
        XCTAssertEqual(model.focusesInCycle, 3)
        model.reset()
        XCTAssertEqual(model.completedFocusTotal, 9)
        XCTAssertEqual(model.focusesInCycle, 3)
    }

    func testUndoExpiredFocusCountsOnceAndLeavesLongBreakDue() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 4, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1,
                               deadline: source.wallNow.addingTimeInterval(1),
                               pausedRemaining: nil, bootSessionID: source.bootSessionID,
                               continuousDeadline: source.continuousNow + 1,
                               activeFlowEnabled: true, pomodoroModeEnabled: true,
                               focusesInCycle: 3, completedFocusTotal: 3), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.selectAndStartPreset(1)
        source.advance(2)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.completedFocusTotal, 4)
        XCTAssertEqual(model.focusesInCycle, 4)
        XCTAssertEqual(model.nextPhaseName, "Long Break")
        XCTAssertEqual(saved(in: defaults)?.completedFocusTotal, 4)
    }

    func testLegacyRunningFocusExpiredWhileClosedCountsOnce() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let now = Date()
        save(SavedTimerSession(version: 3, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: now.addingTimeInterval(-20),
                               pausedRemaining: nil, activeFlowEnabled: true,
                               pomodoroModeEnabled: true), in: defaults)
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: now)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.completedFocusTotal, 1)
        XCTAssertEqual(model.focusesInCycle, 1)
        XCTAssertEqual(saved(in: defaults)?.version, 5)
        let reopened = TimerModel(defaults: defaults, notificationsEnabled: false, now: now)
        XCTAssertEqual(reopened.completedFocusTotal, 1)
        reopened.reset()
    }

    func testWakeUsesEditedFutureDurationsButKeepsCurrentSessionBoundary() {
        let (model, _, boundary, notifications, sound) = runningPomodoro(
            focusPreset: 1_200, breakPreset: 90)
        defer { model.reset() }

        model.refresh(at: boundary.addingTimeInterval(100), afterWake: true)

        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.total, 1_500)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.isComplete)
        model.startNextPhase()
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.total, 90)
        XCTAssertEqual(model.remaining, 90, accuracy: 0.01)
        XCTAssertEqual(notifications.pending?.seconds ?? -1, 90, accuracy: 0.01)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testWakeAfterBreakContinuesIntoFocus() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let now = Date()
        let boundary = now.addingTimeInterval(10)
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 0,
                               phase: .breakTime, total: 300,
                               deadline: boundary, pausedRemaining: nil), in: defaults)
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: now,
                               notificationClient: notifications, soundClient: sound)
        defer { model.reset() }

        model.refresh(at: boundary.addingTimeInterval(25), afterWake: true)

        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
        XCTAssertNil(notifications.pending)
        model.startNextPhase()
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(notifications.pending?.title, "Focus session complete")
        XCTAssertEqual(sound.playCount, 0)
    }

    func testInvalidSessionFallsBackToIdleAndCancelsOrphanedNotification() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "selectedPreset")
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 99,
                               phase: .focus, total: 1_500,
                               deadline: Date().addingTimeInterval(60), pausedRemaining: nil),
             in: defaults)
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, notificationClient: notifications)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertNil(defaults.data(forKey: SavedTimerSession.key))
        XCTAssertEqual(notifications.cancelCount, 1)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testMissingSessionCancelsOldPendingNotification() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = RecordingNotifications()
        _ = TimerModel(defaults: defaults, notificationClient: notifications)
        XCTAssertEqual(notifications.cancelCount, 1)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testMuteChangesRescheduleTheRunningNotification() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, notificationClient: notifications,
                               appIsActive: { true })
        model.start()
        XCTAssertEqual(notifications.pending?.playSound, true)

        model.muted = true
        XCTAssertEqual(notifications.pending?.playSound, false)
        model.muted = false
        XCTAssertEqual(notifications.pending?.playSound, true)
        XCTAssertEqual(notifications.scheduled.count, 3)
        model.pause()
        XCTAssertNil(notifications.pending)
    }

    func testAccessibilityStatusAndAnnouncementsFollowActionsNotClockTicks() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let announcer = RecordingAccessibilityAnnouncer()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               appIsActive: { true }, accessibilityAnnouncer: announcer)
        XCTAssertEqual(model.accessibilityValue,
                       "5-minute preset, Ready, 5 minutes remaining")
        XCTAssertTrue(announcer.messages.isEmpty)

        model.start()
        XCTAssertEqual(announcer.messages.count, 1)
        XCTAssertTrue(announcer.messages[0].contains("preset started"))
        model.refresh(at: Date().addingTimeInterval(2))
        XCTAssertEqual(announcer.messages.count, 1)
        XCTAssertTrue(model.accessibilityValue.contains("Running"))

        model.pause()
        XCTAssertEqual(announcer.messages.count, 2)
        XCTAssertTrue(announcer.messages[1].hasPrefix("Paused."))
        model.start()
        XCTAssertEqual(announcer.messages.count, 3)
        XCTAssertTrue(announcer.messages[2].hasPrefix("Resumed."))
        model.reset()
        XCTAssertEqual(announcer.messages.count, 4)
    }

    func testCompletionAndPomodoroPhaseAnnounceOnceWhileActive() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let announcer = RecordingAccessibilityAnnouncer()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               appIsActive: { true }, accessibilityAnnouncer: announcer)
        model.setPreset(2, seconds: 1)
        model.start()
        model.refresh(at: Date().addingTimeInterval(2))
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(announcer.messages.count, 2)
        XCTAssertTrue(announcer.messages[1].contains("Focus complete. Short Break running."))
        XCTAssertTrue(model.accessibilityValue.contains("Break session, 5-minute preset"))
        model.refresh(at: Date().addingTimeInterval(3))
        XCTAssertEqual(announcer.messages.count, 2)
        model.reset()
    }

    func testHiddenAppDoesNotPostAccessibilityAnnouncements() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let announcer = RecordingAccessibilityAnnouncer()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               appIsActive: { false }, accessibilityAnnouncer: announcer)
        model.start()
        model.pause()
        model.reset()
        XCTAssertTrue(announcer.messages.isEmpty)
    }

    func testCompletedSessionAnnouncesOnceAndDoesNotReplayOnRestore() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let announcer = RecordingAccessibilityAnnouncer()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               appIsActive: { true }, accessibilityAnnouncer: announcer)
        model.setPreset(0, seconds: 1)
        model.start()
        model.refresh(at: Date().addingTimeInterval(2))
        XCTAssertEqual(announcer.messages.last, "Timer complete.")
        XCTAssertEqual(model.accessibilityValue,
                       "5-minute preset, Complete, 0 seconds remaining")
        let count = announcer.messages.count
        model.refresh(at: Date().addingTimeInterval(3))
        XCTAssertEqual(announcer.messages.count, count)

        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  appIsActive: { true }, accessibilityAnnouncer: announcer)
        XCTAssertTrue(restored.isComplete)
        XCTAssertEqual(announcer.messages.count, count)
    }

    func testForegroundCompletionUsesTheAdjustableAlarm() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationClient: notifications,
                               soundClient: sound, appIsActive: { true })
        model.setPreset(0, seconds: 1)
        model.start()
        model.refresh(at: Date().addingTimeInterval(2))
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(sound.playCount, 1)
        XCTAssertEqual(notifications.pending?.playSound, true)
    }

    func testBundledCompletionAudioIsAvailableToTheSwiftPackage() throws {
        let mp3 = try XCTUnwrap(CompletionAudio.playbackURL())
        let caf = try XCTUnwrap(CompletionAudio.notificationURL())
        XCTAssertEqual(mp3.lastPathComponent, CompletionAudio.playbackFile)
        XCTAssertEqual(caf.lastPathComponent, CompletionAudio.notificationFile)
        XCTAssertGreaterThan(try Data(contentsOf: mp3).count, 1_000)
        XCTAssertEqual(String(decoding: try Data(contentsOf: caf).prefix(4), as: UTF8.self),
                       "caff")
        XCTAssertGreaterThan(try AVAudioPlayer(contentsOf: mp3).duration, 0.5)
    }

    func testBundledPresetAudioIsAvailableToTheSwiftPackage() throws {
        let mp3 = try XCTUnwrap(PresetAudio.playbackURL())
        XCTAssertEqual(mp3.lastPathComponent, PresetAudio.playbackFile)
        XCTAssertGreaterThan(try Data(contentsOf: mp3).count, 1_000)
        XCTAssertGreaterThan(try AVAudioPlayer(contentsOf: mp3).duration, 0.5)
    }

    func testEachCubeFaceSelectionPlaysOnceAndStartsItsPreset() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let presetSound = RecordingPresetSound()
        let completionSound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               soundClient: completionSound, presetSoundClient: presetSound)
        model.volume = 0.42
        // The physical cube has six numbered faces; the 5-minute preset repeats.
        for (click, preset) in [0, 1, 2, 3, 4, 0].enumerated() {
            model.selectAndStartCubeFace(preset)
            XCTAssertEqual(model.selectedPreset, preset)
            XCTAssertTrue(model.isRunning)
            XCTAssertEqual(model.total, TimeInterval(model.presetSeconds[preset]))
            XCTAssertEqual(presetSound.volumes.count, click + 1)
        }
        XCTAssertEqual(presetSound.volumes, Array(repeating: 0.42, count: 6))
        XCTAssertEqual(completionSound.playCount, 0)
        model.reset()
    }

    func testPresetSoundHonorsMuteAndCurrentVolumeAndOnlyFaceActionPlaysIt() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let presetSound = RecordingPresetSound()
        let completionSound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               soundClient: completionSound, presetSoundClient: presetSound)
        model.selectPreset(1)                 // visible button / Command-Left or Right
        model.selectAndStartPreset(2)         // keyboard / VoiceOver preset action
        model.startOrPause()                  // countdown click pauses
        model.startOrPause()                  // countdown click resumes
        model.reset()
        model.selectAndStartCubeFace(-1)      // invalid face
        XCTAssertTrue(presetSound.volumes.isEmpty)

        model.muted = true
        model.selectAndStartCubeFace(3)
        XCTAssertTrue(presetSound.volumes.isEmpty)
        model.muted = false
        model.volume = 0.2
        model.selectAndStartCubeFace(4)
        model.volume = 0.8
        model.selectAndStartCubeFace(4)       // selecting the same face restarts it
        XCTAssertEqual(presetSound.volumes, [0.2, 0.8])
        XCTAssertEqual(completionSound.playCount, 0)
        model.reset()
    }

    func testFocusAndShortBreakCompletionEachPlayOnceAtSelectedVolume() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, soundClient: sound,
                               timeSource: source, appIsActive: { true })
        model.autoStartNextPhase = false
        model.setPreset(2, seconds: 1)
        model.setPreset(0, seconds: 1)
        model.volume = 0.37
        model.start()
        XCTAssertEqual(notifications.pending?.playSound, true)
        source.advance(1)
        model.refresh()
        model.refresh()
        XCTAssertEqual(model.nextPhaseName, "Short Break")
        XCTAssertEqual(sound.volumes, [0.37])

        model.startNextPhase()
        source.advance(1)
        model.refresh()
        model.refresh()
        XCTAssertEqual(model.nextPhaseName, "Focus")
        XCTAssertEqual(sound.volumes, [0.37, 0.37])
        model.reset()
    }

    func testLongBreakCompletionPlaysOnce() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        save(SavedTimerSession(version: 5, state: .ready, selectedPreset: 0,
                               phase: .longBreak, total: 1, deadline: nil,
                               pausedRemaining: nil, activeFlowEnabled: true,
                               pomodoroModeEnabled: true, focusesInCycle: 0,
                               completedFocusTotal: 4, cycleTarget: 4), in: defaults)
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, soundClient: sound,
                               timeSource: source, appIsActive: { true })
        model.start()
        source.advance(1)
        model.refresh()
        model.refresh()
        XCTAssertEqual(sound.playCount, 1)
        XCTAssertEqual(model.phase, .focus)
        model.reset()
    }

    func testMuteSuppressesFocusAndBreakAudio() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, soundClient: sound,
                               timeSource: source, appIsActive: { true })
        model.autoStartNextPhase = false
        model.setPreset(2, seconds: 1)
        model.setPreset(0, seconds: 1)
        model.muted = true
        model.start()
        XCTAssertEqual(notifications.pending?.playSound, false)
        source.advance(1)
        model.refresh()
        model.startNextPhase()
        XCTAssertEqual(notifications.pending?.playSound, false)
        source.advance(1)
        model.refresh()
        XCTAssertEqual(sound.playCount, 0)
        model.reset()
    }

    func testPauseResetAndPresetReplacementNeverPlayCompletionAudio() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, soundClient: sound,
                               timeSource: source, appIsActive: { true })
        model.setPreset(0, seconds: 5)
        model.start()
        source.advance(1)
        model.refresh()
        model.pause()
        XCTAssertNil(notifications.pending)
        model.reset()
        model.selectAndStartPreset(1)
        source.advance(1)
        model.refresh()
        model.selectPreset(2)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
        model.reset()
    }

    func testBackgroundCompletionLeavesSoundToNotification() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationClient: notifications,
                               soundClient: sound, appIsActive: { false })
        model.setPreset(0, seconds: 1)
        model.start()
        model.refresh(at: Date().addingTimeInterval(2))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testDeniedNotificationSoundFallsBackToChimeWhileAppRuns() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = RecordingNotifications()
        notifications.systemSoundAvailable = false
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationClient: notifications,
                               soundClient: sound, appIsActive: { false })
        model.setPreset(0, seconds: 1)
        model.start()
        model.refresh(at: Date().addingTimeInterval(2))
        for _ in 0..<20 where sound.playCount == 0 { await Task.yield() }
        XCTAssertEqual(sound.playCount, 1)
    }

    func testSleepCancelsPendingRequestAndWaitsAtMissedBoundary() {
        let (model, _, boundary, notifications, sound) = runningPomodoro()
        defer { model.reset() }
        model.prepareForSleep()
        XCTAssertNil(notifications.pending)

        model.resumeAfterSleep(at: boundary.addingTimeInterval(20))
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testWakeBeforeDeadlineRearmsWithoutChangingPhase() {
        let (model, _, boundary, notifications, sound) = runningPomodoro()
        defer { model.reset() }
        model.prepareForSleep()
        model.resumeAfterSleep(at: boundary.addingTimeInterval(-5))
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(notifications.scheduled.count, 2)
        XCTAssertEqual(notifications.pending?.seconds ?? -1, 5, accuracy: 0.01)
        XCTAssertEqual(sound.playCount, 0)
    }

    func testSixtyMinutePresetStartsAndPersistsWithoutChangingExistingPresets() {
        let suite = "CubeTimerModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1_575, forKey: "presetSeconds.2")

        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertEqual(model.presetSeconds, [300, 600, 1_575, 3_000, 3_600])
        model.selectAndStartPreset(4)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.total, 3_600)
        XCTAssertEqual(model.remaining, model.total)

        model.setPreset(4, seconds: 3_661)
        let reloaded = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertEqual(reloaded.selectedPreset, 4)
        XCTAssertEqual(reloaded.presetSeconds, [300, 600, 1_575, 3_000, 3_661])
        model.reset()
    }

    func testPresetCyclingIncludesSixtyMinutesAndWraps() {
        let model = makeModel()
        model.selectPreset(3)
        model.turn(1)
        XCTAssertEqual(model.selectedPreset, 4)
        XCTAssertEqual(model.total, 3_600)
        model.turn(1)
        XCTAssertEqual(model.selectedPreset, 0)
        model.turn(-1)
        XCTAssertEqual(model.selectedPreset, 4)
    }

    func testFaceSelectionStartsEveryPresetFromIdle() {
        let model = makeModel()
        defer { model.reset() }

        for index in 0..<TimerModel.defaultDurations.count {
            model.selectAndStartPreset(index)
            XCTAssertEqual(model.selectedPreset, index)
            XCTAssertTrue(model.isRunning)
            XCTAssertEqual(model.total, TimeInterval(TimerModel.defaultDurations[index]))
            XCTAssertEqual(model.remaining, model.total)
        }
    }

    func testFaceSelectionReplacesRunningTimerAtFullDuration() {
        let model = makeModel()
        defer { model.reset() }

        model.selectAndStartPreset(0)
        model.refresh(at: Date().addingTimeInterval(20))
        XCTAssertLessThan(model.remaining, model.total)

        model.selectAndStartPreset(2)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remaining, 1500)
    }

    func testFaceSelectionReplacesPausedTimerAtFullDuration() {
        let model = makeModel()
        defer { model.reset() }

        model.selectAndStartPreset(0)
        Thread.sleep(forTimeInterval: 0.02)
        model.pause()
        XCTAssertTrue(model.isPaused)

        model.selectAndStartPreset(1)
        XCTAssertEqual(model.selectedPreset, 1)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remaining, 600)
    }

    func testClickingSelectedPresetFaceRestartsFromFullDuration() {
        let model = makeModel()
        defer { model.reset() }

        model.selectAndStartPreset(0)
        model.refresh(at: Date().addingTimeInterval(20))
        XCTAssertLessThan(model.remaining, model.total)

        model.selectAndStartPreset(0)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remaining, 300)
    }

    func testUndoFaceReplacementRestoresOriginalRunningDeadlineAndNotification() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, notificationClient: notifications)
        defer { model.reset() }

        model.start()
        let original = saved(in: defaults)!.deadline!
        model.selectAndStartPreset(2)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertNotNil(model.undoPresetLabel)
        XCTAssertEqual(notifications.pending?.title, "Timer complete")

        XCTAssertTrue(model.undoPresetChange())
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(saved(in: defaults)?.deadline, original)
        XCTAssertEqual(notifications.scheduled.count, 3)
        XCTAssertEqual(notifications.pending?.seconds ?? -1,
                       original.timeIntervalSinceNow, accuracy: 0.1)
        XCTAssertNil(model.undoPresetLabel)
    }

    func testUndoSelectOnlyRestoresPausedTimeAndLatestIdleSelectionKeepsUndo() {
        let model = makeModel()
        defer { model.reset() }
        model.start()
        model.pause()
        let paused = model.remaining

        model.selectPreset(1)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isPaused)
        model.selectPreset(3)
        XCTAssertEqual(model.selectedPreset, 3)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.remaining, paused, accuracy: 0.001)
    }

    func testUndoSelectOnlyRestoresRunningTimerAndItsSavedDeadline() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        defer { model.reset() }
        model.start()
        let original = saved(in: defaults)!.deadline!

        model.selectPreset(4)
        XCTAssertEqual(model.selectedPreset, 4)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertEqual(saved(in: defaults)?.deadline, original)
    }

    func testUndoFaceReplacementRestoresPausedTimer() {
        let model = makeModel()
        defer { model.reset() }
        model.start()
        model.pause()
        let paused = model.remaining

        model.selectAndStartPreset(2)
        XCTAssertTrue(model.isRunning)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertEqual(model.remaining, paused, accuracy: 0.001)
    }

    func testSecondRunningReplacementOnlyUndoesToImmediatelyPreviousSession() {
        let model = makeModel()
        defer { model.reset() }
        model.start()
        model.selectAndStartPreset(1)
        model.selectAndStartPreset(2)

        XCTAssertTrue(model.undoPresetChange())
        XCTAssertEqual(model.selectedPreset, 1)
        XCTAssertTrue(model.isRunning)
        XCTAssertFalse(model.undoPresetChange())
    }

    func testUndoRepeatedFaceClickRestoresPreviousRunningSession() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        defer { model.reset() }
        model.start()
        let original = saved(in: defaults)!.deadline!

        model.selectAndStartPreset(0)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertEqual(saved(in: defaults)?.deadline, original)
        XCTAssertEqual(model.selectedPreset, 0)
    }

    func testUndoOfferDoesNotSurviveRelaunch() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        model.start()
        model.selectAndStartPreset(1)
        XCTAssertNotNil(model.undoPresetLabel)

        let relaunched = TimerModel(defaults: defaults, notificationsEnabled: false)
        XCTAssertTrue(relaunched.isRunning)
        XCTAssertEqual(relaunched.selectedPreset, 1)
        XCTAssertNil(relaunched.undoPresetLabel)
        XCTAssertFalse(relaunched.undoPresetChange())
        model.reset()
        relaunched.reset()
    }

    func testUndoExpiryAndSubsequentTimerActionsClearOffer() {
        let model = makeModel()
        defer { model.reset() }
        model.start()
        model.selectPreset(1)
        XCTAssertNotNil(model.undoPresetLabel)
        XCTAssertFalse(model.undoPresetChange(at: Date().addingTimeInterval(7)))
        XCTAssertNil(model.undoPresetLabel)

        model.start()
        model.selectAndStartPreset(2)
        XCTAssertNotNil(model.undoPresetLabel)
        model.pause()
        XCTAssertNil(model.undoPresetLabel)
        model.selectPreset(0)
        XCTAssertNotNil(model.undoPresetLabel)
        model.start()
        XCTAssertNil(model.undoPresetLabel)
        model.selectAndStartPreset(3)
        XCTAssertNotNil(model.undoPresetLabel)
        model.reset()
        XCTAssertNil(model.undoPresetLabel)

        model.start()
        model.selectAndStartPreset(1)
        XCTAssertNotNil(model.undoPresetLabel)
        model.muted = true
        model.refresh(at: Date().addingTimeInterval(10_000))
        XCTAssertTrue(model.isComplete)
        XCTAssertNil(model.undoPresetLabel)
    }

    func testUndoExpiredOriginalTimerRestoresCompletionSilently() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 0,
                               phase: .focus, total: 300,
                               deadline: now.addingTimeInterval(1), pausedRemaining: nil),
             in: defaults)
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: now,
                               notificationClient: notifications, soundClient: sound)
        defer { model.reset() }

        model.selectAndStartPreset(1)
        XCTAssertTrue(model.undoPresetChange(at: now.addingTimeInterval(2)))
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.selectedPreset, 0)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
    }

    func testUndoExpiredPomodoroWaitsSilentlyAtBoundary() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        defaults.set(2, forKey: "presetSeconds.2")
        defaults.set(1, forKey: "presetSeconds.0")
        let now = Date()
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: now.addingTimeInterval(1), pausedRemaining: nil),
             in: defaults)
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: now,
                               notificationClient: notifications, soundClient: sound)
        defer { model.reset() }

        model.selectAndStartPreset(3)
        XCTAssertFalse(model.flowEnabled)
        XCTAssertTrue(model.undoPresetChange(at: now.addingTimeInterval(2.5)))
        XCTAssertTrue(model.flowEnabled)
        XCTAssertEqual(model.phase, .focus)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.total, 1_500)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertNil(notifications.pending)
        XCTAssertEqual(sound.playCount, 0)
        XCTAssertEqual(saved(in: defaults)?.state, .completed)
    }

    func testDisplayToggleResumesWithoutResettingRemainingTime() {
        let model = makeModel()
        defer { model.reset() }

        model.startOrPause()
        Thread.sleep(forTimeInterval: 0.02)
        model.startOrPause()
        let pausedRemaining = model.remaining
        XCTAssertTrue(model.isPaused)

        model.startOrPause()
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remaining, pausedRemaining)
        XCTAssertLessThan(model.remaining, model.total)
    }

    func testDeferredEnablePreservesRunningTimerAndCanBeCancelled() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, timeSource: source)
        defer { model.reset() }
        model.start()
        source.advance(30)
        model.refresh()
        model.setFlowEnabled(true)
        XCTAssertTrue(model.isRunning)
        XCTAssertFalse(model.flowEnabled)
        XCTAssertEqual(model.pendingFlowEnabled, true)
        XCTAssertEqual(model.remaining, 270, accuracy: 0.01)
        XCTAssertEqual(saved(in: defaults)?.pendingFlowEnabled, true)
        model.setFlowEnabled(false)
        XCTAssertNil(model.pendingFlowEnabled)
        model.setFlowEnabled(true)
        source.advance(270)
        model.refresh()
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.flowEnabled)
        XCTAssertTrue(model.pomodoroModeEnabled)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.remaining, 1_500)
        XCTAssertNil(model.pendingFlowEnabled)
        XCTAssertNil(notifications.pending)
    }

    func testDeferredDisableSurvivesPauseAndRelaunchThenResetAppliesIt() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.start()
        source.advance(11)
        model.pause()
        let paused = model.remaining
        model.setFlowEnabled(false)
        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertTrue(restored.isPaused)
        XCTAssertEqual(restored.remaining, paused, accuracy: 0.01)
        XCTAssertEqual(restored.pendingFlowEnabled, false)
        restored.reset()
        XCTAssertFalse(restored.pomodoroModeEnabled)
        XCTAssertFalse(restored.flowEnabled)
        XCTAssertNil(restored.pendingFlowEnabled)
        model.reset()
    }

    func testPendingModeChangeCarriesAcrossPresetReplacement() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.start()
        model.setFlowEnabled(true)
        model.selectAndStartPreset(1)
        XCTAssertEqual(model.pendingFlowEnabled, true)
        XCTAssertFalse(model.flowEnabled)
        source.advance(600)
        model.refresh()
        XCTAssertTrue(model.flowEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.selectedPreset, 2)
        XCTAssertEqual(model.remaining, 1_500)
    }

    func testImmediateModeOffRestoresSuspendedPhaseThroughUndo() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.start()
        model.selectPreset(1)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        model.setFlowEnabled(false)
        XCTAssertFalse(model.pomodoroModeEnabled)
        XCTAssertFalse(model.hasSuspendedPomodoro)
        XCTAssertEqual(model.undoPresetLabel, "Pomodoro")
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.pomodoroModeEnabled)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertNil(model.pendingFlowEnabled)
    }

    func testOneOffFreezesFocusAcrossRelaunchAndResumesManually() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let notifications = RecordingNotifications()
        let model = TimerModel(defaults: defaults, now: source.wallNow,
                               notificationClient: notifications, timeSource: source)
        model.start()
        source.advance(37)
        model.selectAndStartPreset(1)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertTrue(model.pomodoroModeEnabled)
        XCTAssertFalse(model.flowEnabled)
        XCTAssertEqual(model.suspendedPomodoro?.remaining ?? -1, 1_463, accuracy: 0.01)
        XCTAssertEqual(notifications.pending?.title, "Timer complete")
        source.advance(90)
        let restored = TimerModel(defaults: defaults, now: source.wallNow,
                                  notificationClient: notifications, timeSource: source)
        XCTAssertTrue(restored.hasSuspendedPomodoro)
        XCTAssertEqual(restored.suspendedPomodoro?.remaining ?? -1, 1_463, accuracy: 0.01)
        XCTAssertTrue(restored.resumePomodoro())
        XCTAssertTrue(restored.isRunning)
        XCTAssertEqual(restored.remaining, 1_463, accuracy: 0.01)
        XCTAssertEqual(restored.phase, .focus)
        XCTAssertEqual(notifications.pending?.title, "Focus session complete")
        restored.reset()
        model.reset()
    }

    func testPausedBreakSurvivesRepeatedOneOffSelectionsAndReset() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.selectPreset(0)
        model.start()
        source.advance(20)
        model.pause()
        let paused = model.remaining
        model.selectPreset(3)
        model.selectAndStartPreset(4)
        model.reset()
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertTrue(model.resumePomodoro())
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.phase, .breakTime)
        XCTAssertEqual(model.remaining, paused, accuracy: 0.01)
        model.reset()
    }

    func testSelectOnlyOneOffKeepsSuspendedPomodoroAfterRelaunch() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.start()
        source.advance(12)
        model.selectPreset(3)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(saved(in: defaults)?.state, .ready)
        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source)
        XCTAssertTrue(restored.hasSuspendedPomodoro)
        XCTAssertTrue(restored.resumePomodoro())
        XCTAssertEqual(restored.remaining, 1_488, accuracy: 0.01)
        restored.reset()
        model.reset()
    }

    func testResumePomodoroCancelsPendingModeOff() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let model = TimerModel(defaults: defaults, notificationsEnabled: false)
        defer { model.reset() }
        model.start()
        model.selectAndStartPreset(1)
        model.setFlowEnabled(false)
        XCTAssertEqual(model.pendingFlowEnabled, false)
        XCTAssertTrue(model.resumePomodoro())
        XCTAssertNil(model.pendingFlowEnabled)
        XCTAssertTrue(model.pomodoroModeEnabled)
    }

    func testMissedBoundaryWithPendingModeChangeIsSilent() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManualTimerTimeSource()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, soundClient: sound,
                               timeSource: source)
        defer { model.reset() }
        model.start()
        model.setFlowEnabled(true)
        model.prepareForSleep()
        source.advance(310)
        model.resumeAfterSleep()
        XCTAssertEqual(sound.playCount, 0)
        XCTAssertTrue(model.flowEnabled)
        XCTAssertFalse(model.isRunning)
    }

    func testResumePomodoroReplacesOneOffAndUndoRestoresItsDeadline() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.start()
        model.selectAndStartPreset(1)
        let oneOffDeadline = saved(in: defaults)?.continuousDeadline
        source.advance(5)
        XCTAssertTrue(model.resumePomodoro())
        XCTAssertTrue(model.flowEnabled)
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertFalse(model.flowEnabled)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertEqual(saved(in: defaults)?.continuousDeadline, oneOffDeadline)
    }

    func testCompletedOneOffWaitsForManualPomodoroResume() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        defer { model.reset() }
        model.start()
        model.selectAndStartPreset(1)
        source.advance(600)
        model.refresh()
        XCTAssertTrue(model.isComplete)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertFalse(model.flowEnabled)
        XCTAssertTrue(model.resumePomodoro())
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.phase, .focus)
    }

    func testDeferredDisableDiscardsSuspendedPomodoroWithUndoAfterClosedCompletion() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.start()
        model.selectAndStartPreset(1)
        model.setFlowEnabled(false)
        source.advance(601)
        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, soundClient: sound, timeSource: source)
        XCTAssertFalse(restored.pomodoroModeEnabled)
        XCTAssertFalse(restored.hasSuspendedPomodoro)
        XCTAssertEqual(restored.remaining, 600)
        XCTAssertNotNil(restored.undoPresetLabel)
        XCTAssertEqual(sound.playCount, 0)
        XCTAssertTrue(restored.undoPresetChange())
        XCTAssertTrue(restored.hasSuspendedPomodoro)
        XCTAssertTrue(restored.pomodoroModeEnabled)
        XCTAssertNil(restored.pendingFlowEnabled)
        restored.reset()
        model.reset()
    }

    func testClosedCompletionUndoGetsSixSecondsAfterAppBecomesActive() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        let source = ManualTimerTimeSource()
        let model = TimerModel(defaults: defaults, notificationsEnabled: false,
                               now: source.wallNow, timeSource: source)
        model.start()
        model.selectAndStartPreset(1)
        model.setFlowEnabled(false)
        source.advance(601)
        var active = false
        let restored = TimerModel(defaults: defaults, notificationsEnabled: false,
                                  now: source.wallNow, timeSource: source,
                                  appIsActive: { active })
        source.advance(30)
        restored.refresh()
        XCTAssertNotNil(restored.undoPresetLabel)
        active = true
        restored.refresh()
        source.advance(7)
        restored.refresh()
        XCTAssertNil(restored.undoPresetLabel)
        restored.reset()
        model.reset()
    }

    private func makeModel() -> TimerModel {
        let (defaults, suite) = isolatedDefaults()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return TimerModel(defaults: defaults, notificationsEnabled: false)
    }

    private func runningPomodoro(focusPreset: Int = 1_500, breakPreset: Int = 300)
        -> (TimerModel, UserDefaults, Date, RecordingNotifications, RecordingSound) {
        let (defaults, suite) = isolatedDefaults()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "flowEnabled")
        defaults.set(focusPreset, forKey: "presetSeconds.2")
        defaults.set(breakPreset, forKey: "presetSeconds.0")
        let now = Date()
        let boundary = now.addingTimeInterval(10)
        save(SavedTimerSession(version: 1, state: .running, selectedPreset: 2,
                               phase: .focus, total: 1_500,
                               deadline: boundary, pausedRemaining: nil), in: defaults)
        let notifications = RecordingNotifications()
        let sound = RecordingSound()
        let model = TimerModel(defaults: defaults, now: now,
                               notificationClient: notifications, soundClient: sound,
                               appIsActive: { true })
        return (model, defaults, boundary, notifications, sound)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "CubeTimerModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func save(_ session: SavedTimerSession, in defaults: UserDefaults) {
        defaults.set(try! JSONEncoder().encode(session), forKey: SavedTimerSession.key)
    }

    private func saved(in defaults: UserDefaults) -> SavedTimerSession? {
        defaults.data(forKey: SavedTimerSession.key)
            .flatMap { try? JSONDecoder().decode(SavedTimerSession.self, from: $0) }
    }
}

private final class ManualTimerTimeSource: TimerTimeSource {
    var wallNow: Date
    var continuousNow: TimeInterval
    var bootSessionID: String?

    init(wallNow: Date = Date(timeIntervalSince1970: 1_700_000_000),
         continuousNow: TimeInterval = 1_000, bootSessionID: String? = "boot-A") {
        self.wallNow = wallNow
        self.continuousNow = continuousNow
        self.bootSessionID = bootSessionID
    }

    func advance(_ seconds: TimeInterval) {
        wallNow.addTimeInterval(seconds)
        continuousNow += seconds
    }

    func jumpWall(_ seconds: TimeInterval) {
        wallNow.addTimeInterval(seconds)
    }
}

private final class RecordingNotifications: CompletionNotificationClient {
    var cancelCount = 0
    var scheduled: [TimeInterval] = []
    var pending: (seconds: TimeInterval, title: String, playSound: Bool)?
    var systemSoundAvailable = true

    func requestPermission() {}
    func schedule(after seconds: TimeInterval, title: String, playSound: Bool) {
        scheduled.append(seconds)
        pending = (seconds, title, playSound)
    }
    func canDeliverSound() async -> Bool { systemSoundAvailable }
    func cancel() {
        cancelCount += 1
        pending = nil
    }
}

private final class RecordingSound: CompletionSoundClient {
    var playCount = 0
    var volumes: [Double] = []
    func play(volume: Double) {
        playCount += 1
        volumes.append(volume)
    }
}

private final class RecordingPresetSound: PresetSoundClient {
    var volumes: [Double] = []
    func play(volume: Double) { volumes.append(volume) }
}

@MainActor
private final class RecordingAccessibilityAnnouncer: TimerAccessibilityAnnouncementClient {
    var messages: [String] = []
    func announce(_ message: String) { messages.append(message) }
}
