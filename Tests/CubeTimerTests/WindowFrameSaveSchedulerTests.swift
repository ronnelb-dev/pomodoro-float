import AppKit
import XCTest
@testable import CubeTimer

final class WindowFrameSaveSchedulerTests: XCTestCase {
    func testBurstOfFrameChangesSavesOnlyTheLatestFrameAfterDebounce() {
        var scheduledActions: [() -> Void] = []
        var savedFrames: [Int] = []
        let scheduler = WindowFrameSaveScheduler<Int>(
            debounceInterval: 0.3,
            scheduleAfter: { _, action in
                scheduledActions.append(action)
                return {}
            },
            save: { savedFrames.append($0) })

        scheduler.schedule(1)
        scheduler.schedule(2)
        scheduler.schedule(3)

        XCTAssertTrue(savedFrames.isEmpty)
        scheduledActions[0]()
        XCTAssertTrue(savedFrames.isEmpty)
        scheduledActions[1]()
        XCTAssertTrue(savedFrames.isEmpty)
        scheduledActions[2]()
        XCTAssertEqual(savedFrames, [3])
    }

    func testFlushPersistsPendingFrameImmediatelyAndIgnoresLaterCallback() {
        var scheduledAction: (() -> Void)?
        var savedFrames: [Int] = []
        let scheduler = WindowFrameSaveScheduler<Int>(
            debounceInterval: 0.3,
            scheduleAfter: { _, action in
                scheduledAction = action
                return {}
            },
            save: { savedFrames.append($0) })

        scheduler.schedule(42)
        scheduler.flush()
        scheduledAction?()

        XCTAssertEqual(savedFrames, [42])
    }
}
