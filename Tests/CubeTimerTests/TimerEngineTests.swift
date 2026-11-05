import Foundation
import XCTest
@testable import CubeTimer

final class TimerEngineTests: XCTestCase {
    func testElapsedWallTimeIncludesSleepGap() {
        let start = Date(timeIntervalSince1970: 1_000)
        let deadline = start.addingTimeInterval(300)
        XCTAssertEqual(TimerEngine.remaining(until: deadline, at: start.addingTimeInterval(70)), 230)
        XCTAssertEqual(TimerEngine.remaining(until: deadline, at: start.addingTimeInterval(500)), 0)
    }

    func testDisplayRoundsUpUntilDeadline() {
        XCTAssertEqual(TimerEngine.display(0.1), "00:01")
        XCTAssertEqual(TimerEngine.display(60.1), "01:01")
        XCTAssertEqual(TimerEngine.display(5_999), "99:59")
    }

    func testStopwatchDisplayRoundsDownElapsedTime() {
        XCTAssertEqual(TimerEngine.stopwatchDisplay(0.9), "00:00")
        XCTAssertEqual(TimerEngine.stopwatchDisplay(60.9), "01:00")
        XCTAssertEqual(TimerEngine.stopwatchDisplay(5_999), "99:59")
    }

    func testCustomCountdownInputAcceptsOnlySupportedDurations() {
        XCTAssertEqual(CustomCountdownInput.duration(minutes: "00", seconds: "01"), 1)
        XCTAssertEqual(CustomCountdownInput.duration(minutes: "99", seconds: "59"), 5_999)
        XCTAssertNil(CustomCountdownInput.duration(minutes: "00", seconds: "00"))
        XCTAssertNil(CustomCountdownInput.duration(minutes: "100", seconds: "00"))
        XCTAssertNil(CustomCountdownInput.duration(minutes: "01", seconds: "60"))
        XCTAssertNil(CustomCountdownInput.duration(minutes: "1x", seconds: "30"))
    }

    func testSpokenDurationMatchesDisplayedSeconds() {
        XCTAssertEqual(TimerEngine.spokenDuration(0), "0 seconds")
        XCTAssertEqual(TimerEngine.spokenDuration(0.1), "1 second")
        XCTAssertEqual(TimerEngine.spokenDuration(60), "1 minute")
        XCTAssertEqual(TimerEngine.spokenDuration(61), "1 minute and 1 second")
        XCTAssertEqual(TimerEngine.spokenDuration(125), "2 minutes and 5 seconds")
    }

    func testDurationBoundsAndProgress() {
        XCTAssertEqual(TimerEngine.clampedDuration(0), 1)
        XCTAssertEqual(TimerEngine.clampedDuration(10_000), 5_999)
        XCTAssertEqual(TimerEngine.progress(remaining: 75, total: 100), 0.25)
    }
}
