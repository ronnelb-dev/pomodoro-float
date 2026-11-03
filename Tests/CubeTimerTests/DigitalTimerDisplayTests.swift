import XCTest
@testable import CubeTimer

final class DigitalTimerDisplayTests: XCTestCase {
    func testSevenSegmentEncodingCoversAllDecimalDigits() {
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "0"),
                       [true, true, true, true, true, true, false])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "1"),
                       [false, true, true, false, false, false, false])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "2"),
                       [true, true, false, true, true, false, true])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "3"),
                       [true, true, true, true, false, false, true])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "4"),
                       [false, true, true, false, false, true, true])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "5"),
                       [true, false, true, true, false, true, true])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "6"),
                       [true, false, true, true, true, true, true])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "7"),
                       [true, true, true, false, false, false, false])
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "8"),
                       Array(repeating: true, count: 7))
        XCTAssertEqual(SevenSegmentEncoding.segments(for: "9"),
                       [true, true, true, true, false, true, true])
        XCTAssertNil(SevenSegmentEncoding.segments(for: ":"))
    }

    func testAccessibilityValueIncludesTimerPhaseStatusAndFocusProgress() {
        XCTAssertEqual(
            DigitalTimerAccessibility.value(timeLabel: "24:53", phaseLabel: "Focus",
                                            statusLabel: "RUNNING", focusProgress: "2/4"),
            "Time remaining 24:53, Focus, running, focus progress 2/4")
    }

    func testAccessibilityValueOmitsFocusProgressForCountdown() {
        XCTAssertEqual(
            DigitalTimerAccessibility.value(timeLabel: "05:00", phaseLabel: "Countdown",
                                            statusLabel: "READY", focusProgress: nil),
            "Time remaining 05:00, Countdown, ready")
    }
}
