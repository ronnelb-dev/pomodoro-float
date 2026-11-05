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

    func testFullscreenExitHintSupportsDigitalAndClockForThreeSeconds() {
        XCTAssertTrue(DisplayFullscreenHint.shouldShow(displayStyle: .digital,
                                                       isFullscreen: true))
        XCTAssertTrue(DisplayFullscreenHint.shouldShow(displayStyle: .clock,
                                                       isFullscreen: true))
        XCTAssertFalse(DisplayFullscreenHint.shouldShow(displayStyle: .cube,
                                                        isFullscreen: true))
        XCTAssertFalse(DisplayFullscreenHint.shouldShow(displayStyle: .clock,
                                                        isFullscreen: false))
        XCTAssertEqual(DisplayFullscreenHint.durationSeconds, 3)
    }

    func testFullscreenTransitionWaitsForBorderlessPromotion() {
        XCTAssertEqual(
            DisplayFullscreenTransition.entryAction(
                supportsFullscreen: true, isNativeFullscreen: false, isBorderless: true),
            .waitForStandardWindow)
        XCTAssertEqual(
            DisplayFullscreenTransition.modeChangeAction(
                pendingEntry: true, windowMatches: true, isBorderless: true),
            .waitForStandardWindow)
        XCTAssertEqual(
            DisplayFullscreenTransition.modeChangeAction(
                pendingEntry: true, windowMatches: true, isBorderless: false),
            .toggleNow)
    }

    func testFullscreenTransitionTogglesImmediatelyForStandardDigitalAndClockWindows() {
        for style in [TimerDisplayStyle.digital, .clock] {
            XCTAssertEqual(
                DisplayFullscreenTransition.entryAction(
                    supportsFullscreen: style.supportsFullscreen,
                    isNativeFullscreen: false, isBorderless: false),
                .toggleNow)
        }
    }

    func testFullscreenTransitionIgnoresCubeAndStaleNotifications() {
        XCTAssertEqual(
            DisplayFullscreenTransition.entryAction(
                supportsFullscreen: false, isNativeFullscreen: false, isBorderless: false),
            .reject)
        XCTAssertEqual(
            DisplayFullscreenTransition.modeChangeAction(
                pendingEntry: false, windowMatches: true, isBorderless: false),
            .ignore)
        XCTAssertEqual(
            DisplayFullscreenTransition.modeChangeAction(
                pendingEntry: true, windowMatches: false, isBorderless: false),
            .ignore)
    }

    func testDeskClockFormatsLocalizedTimeWithSecondsAndCompactDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utc = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2024, month: 1, day: 3,
                                                       hour: 13, minute: 5, second: 9))!

        let twelveHour = DeskClockFormatter.presentation(
            for: date, locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: utc)
        XCTAssertEqual(twelveHour.time, "1:05:09\u{202F}PM")
        XCTAssertEqual(twelveHour.dateLine, "Wed, 1/3/2024")

        let twentyFourHour = DeskClockFormatter.presentation(
            for: date, locale: Locale(identifier: "en_GB"), calendar: calendar, timeZone: utc)
        XCTAssertEqual(twentyFourHour.time, "13:05:09")
        XCTAssertEqual(twentyFourHour.dateLine, "Wed, 03/01/2024")
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
