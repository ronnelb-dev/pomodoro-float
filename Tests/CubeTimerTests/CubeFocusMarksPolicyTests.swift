import XCTest
@testable import CubeTimer

final class CubeFocusMarksPolicyTests: XCTestCase {
    func testOneOffCountdownHidesPomodoroMarkersWhilePomodoroIsSuspended() {
        XCTAssertNil(CubeFocusMarksPolicy.markers(
            sessionKind: .customCountdown, pomodoroModeEnabled: true,
            completed: 2, target: 4))
    }

    func testStopwatchHidesPomodoroMarkers() {
        XCTAssertNil(CubeFocusMarksPolicy.markers(
            sessionKind: .stopwatch, pomodoroModeEnabled: true,
            completed: 2, target: 4))
    }

    func testPomodoroPresetSessionShowsCompletedAndTargetCounts() {
        XCTAssertEqual(CubeFocusMarksPolicy.markers(
            sessionKind: .presetCountdown, pomodoroModeEnabled: true,
            completed: 2, target: 4), CubeFocusProgress(completed: 2, target: 4))
    }

    func testPresetSessionWithoutPomodoroHidesMarkers() {
        XCTAssertNil(CubeFocusMarksPolicy.markers(
            sessionKind: .presetCountdown, pomodoroModeEnabled: false,
            completed: 2, target: 4))
    }
}
