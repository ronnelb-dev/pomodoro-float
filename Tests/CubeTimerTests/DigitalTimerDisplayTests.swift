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

    func testFullscreenExitHintIsDigitalOnlyAndLastsThreeSeconds() {
        XCTAssertTrue(DigitalFullscreenHint.shouldShow(displayStyle: .digital,
                                                       isFullscreen: true))
        XCTAssertFalse(DigitalFullscreenHint.shouldShow(displayStyle: .cube,
                                                        isFullscreen: true))
        XCTAssertFalse(DigitalFullscreenHint.shouldShow(displayStyle: .digital,
                                                        isFullscreen: false))
        XCTAssertEqual(DigitalFullscreenHint.durationSeconds, 3)
    }

    func testDigitHeightUsesBothAvailableDimensionsAndFitsShortPanel() {
        let compact = DigitalTimerLayout.digitHeight(
            containerSize: CGSize(width: 310, height: 174),
            timeLabel: "05:00", compact: true, hasSessionNotice: false)
        let expanded = DigitalTimerLayout.digitHeight(
            containerSize: CGSize(width: 1_200, height: 880),
            timeLabel: "05:00", compact: false, hasSessionNotice: false)
        let narrow = DigitalTimerLayout.digitHeight(
            containerSize: CGSize(width: 240, height: 700),
            timeLabel: "05:00", compact: true, hasSessionNotice: false)

        XCTAssertGreaterThan(expanded, compact)
        XCTAssertEqual(narrow, 240 / DigitalTimerLayout.aspectRatio(for: "05:00"), accuracy: 0.001)
        XCTAssertGreaterThan(compact, 0)
    }

    func testSessionNoticeReservesVerticalRoomForDigits() {
        let withoutNotice = DigitalTimerLayout.digitHeight(
            containerSize: CGSize(width: 500, height: 220),
            timeLabel: "25:00", compact: true, hasSessionNotice: false)
        let withNotice = DigitalTimerLayout.digitHeight(
            containerSize: CGSize(width: 500, height: 220),
            timeLabel: "25:00", compact: true, hasSessionNotice: true)

        XCTAssertLessThan(withNotice, withoutNotice)
    }
}
