import AppKit
import XCTest
@testable import CubeTimer

final class TimerWindowLayoutTests: XCTestCase {
    func testStandardMinimumSizeMatchesDefaultWindowSize() {
        XCTAssertEqual(TimerWindowLayout.standardMinimumSize,
                       NSSize(width: 420, height: 560))
        XCTAssertEqual(TimerWindowLayout.floatingMinimumSide, 240)
    }

    func testStandardFrameMinimumPredicateCoversEitherDimension() {
        XCTAssertTrue(StandardWindowPosition.isBelowMinimum(
            NSRect(x: 0, y: 0, width: 419, height: 560)))
        XCTAssertTrue(StandardWindowPosition.isBelowMinimum(
            NSRect(x: 0, y: 0, width: 420, height: 559)))
        XCTAssertTrue(StandardWindowPosition.isBelowMinimum(
            NSRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertFalse(StandardWindowPosition.isBelowMinimum(
            NSRect(x: 0, y: 0, width: 420, height: 560)))
        XCTAssertFalse(StandardWindowPosition.isBelowMinimum(
            NSRect(x: 0, y: 0, width: 600, height: 700)))
    }

    func testAlwaysOnTopIsSuspendedDuringNativeFullscreen() {
        XCTAssertTrue(TimerWindowLevelPolicy.shouldFloat(alwaysOnTop: true, isFullscreen: false))
        XCTAssertFalse(TimerWindowLevelPolicy.shouldFloat(alwaysOnTop: true, isFullscreen: true))
        XCTAssertFalse(TimerWindowLevelPolicy.shouldFloat(alwaysOnTop: false, isFullscreen: false))
        XCTAssertFalse(TimerWindowLevelPolicy.shouldFloat(
            alwaysOnTop: true, isFullscreen: false, fullscreenTransitionActive: true))
    }

    func testFullscreenExitUsesNativeOrModelState() {
        XCTAssertTrue(DisplayFullscreenExitPolicy.shouldExit(nativeFullscreen: true,
                                                              modelFullscreen: false))
        XCTAssertTrue(DisplayFullscreenExitPolicy.shouldExit(nativeFullscreen: false,
                                                              modelFullscreen: true))
        XCTAssertFalse(DisplayFullscreenExitPolicy.shouldExit(nativeFullscreen: false,
                                                               modelFullscreen: false))
    }

    func testFullscreenDeskClockUses85PercentOfAvailableWidth() {
        XCTAssertEqual(DeskClockLayout.fullscreenPanelWidth(availableWidth: 1_000), 850)
        XCTAssertEqual(DeskClockLayout.fullscreenPanelWidth(availableWidth: 240), 204)
        XCTAssertEqual(DeskClockLayout.fullscreenPanelWidth(availableWidth: -10), 0)
    }

    func testImmersiveCubeUsesMostOfTheAvailableFullscreenArea() {
        XCTAssertEqual(TimerWindowLayout.immersiveCubeSide(
            availableSize: NSSize(width: 1_600, height: 900)), 792)
        XCTAssertEqual(TimerWindowLayout.immersiveCubeSide(
            availableSize: NSSize(width: 700, height: 1_200)), 616)
        XCTAssertEqual(TimerWindowLayout.immersiveCubeSide(
            availableSize: NSSize(width: -10, height: 600)), 0)
    }

    func testImmersiveCubeReservesHeaderAndOptionalReadoutSpace() {
        let fullscreenSize = NSSize(width: 1_600, height: 900)

        XCTAssertEqual(TimerWindowLayout.immersiveCubeSide(
            availableSize: fullscreenSize, reservedHeight: 76), 725.12, accuracy: 0.01)
        XCTAssertEqual(TimerWindowLayout.immersiveCubeSide(
            availableSize: fullscreenSize, reservedHeight: 124), 682.88, accuracy: 0.01)
        XCTAssertEqual(TimerWindowLayout.immersiveCubeSide(
            availableSize: fullscreenSize, reservedHeight: 1_000), 0)
    }

    func testMinimumStandardSizeFitsCompactLayoutWithAllTransientRows() {
        let metrics = TimerWindowLayout.standardMetrics(
            size: TimerWindowLayout.standardMinimumSize,
            transientRowCount: 3)

        XCTAssertTrue(metrics.compact)
        XCTAssertEqual(metrics.spacing, 6)
        XCTAssertEqual(metrics.verticalPadding, 12)
        XCTAssertEqual(metrics.displayHeight, 230)
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

    func testExpandedDigitalPanelUsesMostAvailableWidthAndCapsAt1200Points() {
        XCTAssertEqual(TimerWindowLayout.digitalPanelWidth(availableWidth: 320), 320)
        XCTAssertEqual(TimerWindowLayout.digitalPanelWidth(availableWidth: 600), 600)
        XCTAssertEqual(TimerWindowLayout.digitalPanelWidth(availableWidth: 800), 680)
        XCTAssertEqual(TimerWindowLayout.digitalPanelWidth(availableWidth: 2_000), 1_200)
    }

    func testStandardClockPanelWidthFitsNarrowWindowsAndCapsRegularWindows() {
        XCTAssertEqual(TimerWindowLayout.standardClockPanelWidth(availableWidth: 419), 419)
        XCTAssertEqual(TimerWindowLayout.standardClockPanelWidth(availableWidth: 610), 610)
        XCTAssertEqual(TimerWindowLayout.standardClockPanelWidth(availableWidth: 900), 610)
        XCTAssertEqual(TimerWindowLayout.standardClockPanelWidth(availableWidth: 0), 0)
        XCTAssertEqual(TimerWindowLayout.standardClockPanelWidth(availableWidth: -20), 0)
    }

    func testHeaderPickerWidthStaysCenteredWithinRegularBounds() {
        XCTAssertEqual(TimerWindowLayout.headerPickerWidth(availableWidth: 610, compact: false), 126)
        XCTAssertEqual(TimerWindowLayout.headerPickerWidth(availableWidth: 310, compact: true), 126)
        XCTAssertEqual(TimerWindowLayout.headerPickerWidth(availableWidth: 260, compact: true), 108)
    }

    func testDigitalDisplayUsesAvailableHeightWhileCubeKeepsExistingCap() {
        let size = NSSize(width: 1_000, height: 1_200)
        let digital = TimerWindowLayout.standardMetrics(size: size,
                                                        expandsDigitalDisplay: true)
        let cube = TimerWindowLayout.standardMetrics(size: size)

        XCTAssertGreaterThan(digital.displayHeight, 510)
        XCTAssertEqual(cube.displayHeight, 510)
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
        XCTAssertEqual(tooSmall.origin, NSPoint(x: 1_020, y: 640))
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
