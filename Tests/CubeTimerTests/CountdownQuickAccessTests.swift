import XCTest
@testable import CubeTimer

final class CountdownQuickAccessStoreTests: XCTestCase {
    func testRecentDurationsAreDeduplicatedPromotedAndCappedAtFive() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        [60, 120, 180, 240, 300, 360].forEach(store.recordStarted)
        XCTAssertEqual(store.recentDurations, [360, 300, 240, 180, 120])

        store.recordStarted(240)
        XCTAssertEqual(store.recentDurations, [240, 360, 300, 180, 120])
    }

    func testInvalidDurationsAreNotStoredOrFavorited() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordStarted(0)
        store.recordStarted(TimerEngine.maximumDuration + 1)

        XCTAssertEqual(store.recentDurations, [])
        XCTAssertEqual(store.toggleFavorite(0), .invalidDuration)
        XCTAssertEqual(store.favoriteDurations, [])
    }

    func testFavoritesPinInNewestFirstOrderAndRejectSixthUntilOneIsRemoved() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        [60, 120, 180, 240, 300].forEach {
            XCTAssertEqual(store.toggleFavorite($0), .added)
        }
        XCTAssertEqual(store.favoriteDurations, [300, 240, 180, 120, 60])
        XCTAssertEqual(store.toggleFavorite(360), .limitReached)
        XCTAssertEqual(store.favoriteDurations, [300, 240, 180, 120, 60])

        XCTAssertEqual(store.toggleFavorite(180), .removed)
        XCTAssertEqual(store.toggleFavorite(360), .added)
        XCTAssertEqual(store.favoriteDurations, [360, 300, 240, 120, 60])
    }

    func testRecentAndFavoritesPersistIndependentlyAndClearingRecentsKeepsFavorites() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordStarted(90)
        XCTAssertEqual(store.toggleFavorite(90), .added)
        store.recordStarted(180)

        let restored = CountdownQuickAccessStore(defaults: defaults)
        XCTAssertEqual(restored.recentDurations, [180, 90])
        XCTAssertEqual(restored.favoriteDurations, [90])

        restored.clearRecent()
        XCTAssertEqual(restored.recentDurations, [])
        XCTAssertEqual(restored.favoriteDurations, [90])
    }

    func testSameDurationCannotBePinnedTwice() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.toggleFavorite(90), .added)
        XCTAssertEqual(store.toggleFavorite(90), .removed)
        XCTAssertEqual(store.favoriteDurations, [])
    }

    private func makeStore() -> (CountdownQuickAccessStore, UserDefaults, String) {
        let suite = "CountdownQuickAccessStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CountdownQuickAccessStore(defaults: defaults), defaults, suite)
    }
}

@MainActor
final class CountdownQuickAccessModelTests: XCTestCase {
    func testOnlySuccessfullyStartedCountdownsEnterRecent() {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessionBeforeInvalidStart = model.sessionSnapshot

        XCTAssertFalse(model.startCustomCountdown(seconds: 0))
        XCTAssertEqual(model.sessionSnapshot, sessionBeforeInvalidStart)
        XCTAssertEqual(model.recentCountdowns, [])

        XCTAssertTrue(model.startCustomCountdown(seconds: 125))
        XCTAssertEqual(model.recentCountdowns, [125])
    }

    func testPinningAndClearingQuickAccessDoNotChangeTheActiveSession() {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(model.startCustomCountdown(seconds: 90))
        let activeSession = model.sessionSnapshot

        XCTAssertEqual(model.toggleFavoriteCountdown(90), .added)
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        XCTAssertEqual(model.favoriteCountdowns, [90])

        model.clearRecentCountdowns()
        XCTAssertEqual(model.sessionSnapshot, activeSession)
        XCTAssertEqual(model.recentCountdowns, [])
        XCTAssertEqual(model.favoriteCountdowns, [90])
    }

    func testStartingQuickCountdownPreservesPomodoroSuspensionAndUndo() {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setFlowEnabled(true)
        model.start()

        XCTAssertTrue(model.startCustomCountdown(seconds: 240))

        XCTAssertEqual(model.sessionKind, .customCountdown)
        XCTAssertTrue(model.isRunning)
        XCTAssertTrue(model.hasSuspendedPomodoro)
        XCTAssertNotNil(model.undoPresetLabel)
        XCTAssertEqual(model.recentCountdowns, [240])
        XCTAssertTrue(model.undoPresetChange())
        XCTAssertTrue(model.flowEnabled)
        XCTAssertFalse(model.hasSuspendedPomodoro)
    }

    func testQuickAccessListsRestoreWithTheSameLocalPreferences() {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(model.startCustomCountdown(seconds: 75))
        XCTAssertEqual(model.toggleFavoriteCountdown(75), .added)

        let restored = TimerModel(defaults: defaults, notificationsEnabled: false)

        XCTAssertEqual(restored.recentCountdowns, [75])
        XCTAssertEqual(restored.favoriteCountdowns, [75])
    }

    private func makeModel() -> (TimerModel, UserDefaults, String) {
        let suite = "CountdownQuickAccessModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (TimerModel(defaults: defaults, notificationsEnabled: false), defaults, suite)
    }
}
