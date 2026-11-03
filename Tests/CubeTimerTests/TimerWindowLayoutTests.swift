import AppKit
import XCTest
@testable import CubeTimer

final class TimerWindowLayoutTests: XCTestCase {
    func testMinimumStandardSizeFitsCompactLayoutWithAllTransientRows() {
        let metrics = TimerWindowLayout.standardMetrics(
            size: NSSize(width: TimerWindowLayout.standardMinimumSize.width, height: 462),
            transientRowCount: 3)

        XCTAssertTrue(metrics.compact)
        XCTAssertEqual(metrics.spacing, 6)
        XCTAssertEqual(metrics.verticalPadding, 12)
        XCTAssertEqual(metrics.displayHeight, 174)
        XCTAssertLessThanOrEqual(metrics.displayHeight, 510)
    }

    func testNarrowStandardWindowUsesCompactLayoutEvenWhenTall() {
        let metrics = TimerWindowLayout.standardMetrics(size: NSSize(width: 380, height: 760))

        XCTAssertTrue(metrics.compact)
        XCTAssertEqual(metrics.spacing, 6)
        XCTAssertGreaterThan(metrics.displayHeight, 160)
    }

    func testExpandedStandardWindowUsesRoomierLayoutAndCapsDisplayHeight() {
        let compact = TimerWindowLayout.standardMetrics(size: NSSize(width: 380, height: 650))
        let expanded = TimerWindowLayout.standardMetrics(size: NSSize(width: 600, height: 900))
        let veryTall = TimerWindowLayout.standardMetrics(size: NSSize(width: 600, height: 1_200))

        XCTAssertFalse(expanded.compact)
        XCTAssertEqual(expanded.spacing, 12)
        XCTAssertEqual(expanded.verticalPadding, 20)
        XCTAssertGreaterThan(expanded.displayHeight, compact.displayHeight)
        XCTAssertEqual(veryTall.displayHeight, 510)
    }

    func testStandardFrameRestorationPreservesValidSizeAndPosition() {
        let saved = NSRect(x: 120, y: 80, width: 580, height: 720)
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(StandardWindowPosition.restoredFrame(saved, visibleFrames: [screen]), saved)
    }

    func testStandardFrameRestorationClampsSizeAndPositionToSupportedBounds() {
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 1_200)
        let tooSmall = StandardWindowPosition.restoredFrame(
            NSRect(x: 2_000, y: 2_000, width: 200, height: 200), visibleFrames: [screen])
        let tooLarge = StandardWindowPosition.restoredFrame(
            NSRect(x: 2_000, y: 2_000, width: 1_200, height: 1_400), visibleFrames: [screen])

        XCTAssertEqual(tooSmall.size, TimerWindowLayout.standardMinimumSize)
        XCTAssertEqual(tooSmall.origin, NSPoint(x: 1_090, y: 710))
        XCTAssertEqual(tooLarge.size, TimerWindowLayout.standardMaximumSize)
        XCTAssertEqual(tooLarge.origin, NSPoint(x: 590, y: 200))
    }

    func testFloatingResizeKeepsSquareAndAnchorsTopLeft() {
        let start = NSRect(x: 80, y: 480, width: 320, height: 320)
        let resized = BorderlessWindowPosition.resizedFrame(
            start: start, horizontalDelta: 120, verticalDelta: -40,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800))

        XCTAssertEqual(resized.size, NSSize(width: 440, height: 440))
        XCTAssertEqual(resized.minX, start.minX)
        XCTAssertEqual(resized.maxY, start.maxY)
    }

    func testFloatingResizeRespectsMinimumAndMaximumSides() {
        let visible = NSRect(x: 0, y: 0, width: 1_100, height: 1_000)
        let start = NSRect(x: 100, y: 680, width: 320, height: 320)
        let minimum = BorderlessWindowPosition.resizedFrame(
            start: start, horizontalDelta: -500, verticalDelta: 0,
            visibleFrame: visible)
        let maximum = BorderlessWindowPosition.resizedFrame(
            start: start, horizontalDelta: 1_000, verticalDelta: 0,
            visibleFrame: visible)

        XCTAssertEqual(minimum.size, NSSize(width: 240, height: 240))
        XCTAssertEqual(maximum.size, NSSize(width: 850, height: 850))
    }

    func testFloatingRestoreNormalizesSquareAndCapsMaximumSide() {
        let restored = BorderlessWindowPosition.restoredFrame(
            NSRect(x: 100, y: 100, width: 1_000, height: 1_000),
            visibleFrames: [NSRect(x: 0, y: 0, width: 1_200, height: 1_000)])

        XCTAssertEqual(restored.size, NSSize(width: 850, height: 850))
    }
}
