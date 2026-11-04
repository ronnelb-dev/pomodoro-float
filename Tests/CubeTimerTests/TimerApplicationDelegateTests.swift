import XCTest
@testable import CubeTimer

@MainActor
final class TimerApplicationDelegateTests: XCTestCase {
    func testDockReopenUsesExistingWindowWithoutRequestingNewWindow() {
        let delegate = TimerApplicationDelegate()
        var didBringExistingWindowForward = false

        let shouldContinueDefaultReopen = delegate.handleReopen(timerWindowExists: true) {
            didBringExistingWindowForward = true
        }

        XCTAssertFalse(shouldContinueDefaultReopen)
        XCTAssertTrue(didBringExistingWindowForward)
    }

    func testDockReopenAllowsDefaultWindowGroupReopenWhenTimerWindowDoesNotExist() {
        let delegate = TimerApplicationDelegate()

        XCTAssertTrue(delegate.handleReopen(timerWindowExists: false) {
            XCTFail("No window should be raised when the timer window does not exist")
        })
    }
}
