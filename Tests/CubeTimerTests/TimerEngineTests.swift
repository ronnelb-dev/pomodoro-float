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
