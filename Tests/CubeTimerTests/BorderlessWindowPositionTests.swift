import AppKit
import XCTest
@testable import CubeTimer

final class BorderlessWindowPositionTests: XCTestCase {
    func testRestoreKeepsIntentionalPartialOffscreenPosition() {
        let saved = NSRect(x: -180, y: 260, width: 320, height: 320)
        let screen = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        XCTAssertEqual(BorderlessWindowPosition.restoredFrame(saved, visibleFrames: [screen]), saved)
    }

    func testRestoreMovesCubeToReachableDisplayWhenMonitorIsGone() {
        let saved = NSRect(x: 1_500, y: 150, width: 320, height: 320)
        let screen = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let restored = BorderlessWindowPosition.restoredFrame(saved, visibleFrames: [screen])
        XCTAssertEqual(restored.origin, NSPoint(x: 880, y: 150))
        XCTAssertEqual(restored.size, saved.size)
    }

    func testKeepsReachableAreaAtEveryEdge() {
        let screen = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let size = NSSize(width: 320, height: 320)
        XCTAssertEqual(BorderlessWindowPosition.clampedOrigin(NSPoint(x: -1_000, y: -1_000),
                                                             size: size, visibleFrames: [screen]),
                       NSPoint(x: -200, y: -200))
        XCTAssertEqual(BorderlessWindowPosition.clampedOrigin(NSPoint(x: 2_000, y: 2_000),
                                                             size: size, visibleFrames: [screen]),
                       NSPoint(x: 880, y: 680))
    }

    func testAllowsMovementToSecondDisplayWithoutChangingSize() {
        let screens = [NSRect(x: 0, y: 0, width: 1_000, height: 800),
                       NSRect(x: 1_000, y: 100, width: 900, height: 700)]
        let proposed = NSPoint(x: 1_400, y: 200)
        XCTAssertEqual(BorderlessWindowPosition.clampedOrigin(
            proposed, size: NSSize(width: 320, height: 320), visibleFrames: screens), proposed)
    }

    func testTinyDestinationDisplayStillLeavesReachableArea() {
        let proposed = NSPoint(x: 5_000, y: 5_000)
        let result = BorderlessWindowPosition.clampedOrigin(
            proposed, size: NSSize(width: 850, height: 850),
            visibleFrames: [NSRect(x: 0, y: 0, width: 100, height: 90)])
        XCTAssertEqual(result, NSPoint(x: 0, y: 0))
    }

    func testOrdinaryDragDoesNotMoveFloatingWindow() {
        var gesture = BorderlessWindowMoveGesture()
        gesture.begin(pointer: NSPoint(x: 300, y: 300),
                      frame: NSRect(x: 100, y: 120, width: 320, height: 320),
                      moveIntent: false)

        XCTAssertNil(gesture.proposedOrigin(
            pointer: NSPoint(x: 350, y: 360), size: NSSize(width: 320, height: 320),
            visibleFrames: [NSRect(x: 0, y: 0, width: 1_000, height: 800)]))
        XCTAssertFalse(gesture.hasMoved)
    }

    func testControlDragMovesOnlyAfterThresholdAndClampsToVisibleArea() {
        var gesture = BorderlessWindowMoveGesture()
        let frame = NSRect(x: 100, y: 120, width: 320, height: 320)
        let screens = [NSRect(x: 0, y: 0, width: 1_000, height: 800)]
        gesture.begin(pointer: NSPoint(x: 300, y: 300), frame: frame, moveIntent: true)

        XCTAssertNil(gesture.proposedOrigin(pointer: NSPoint(x: 303, y: 303),
                                            size: frame.size,
                                            visibleFrames: screens))
        XCTAssertEqual(gesture.proposedOrigin(pointer: NSPoint(x: 310, y: 320),
                                              size: frame.size,
                                              visibleFrames: screens),
                       NSPoint(x: 110, y: 140))
        XCTAssertEqual(gesture.proposedOrigin(pointer: NSPoint(x: 2_000, y: 2_000),
                                              size: frame.size,
                                              visibleFrames: screens),
                       NSPoint(x: 880, y: 680))
    }

    func testControlDragInCornerGripIsReservedForResize() {
        let contentBounds = NSRect(x: 0, y: 0, width: 360, height: 360)
        XCTAssertTrue(BorderlessWindowMoveGesture.hitsResizeGrip(
            NSPoint(x: 350, y: 10), contentBounds: contentBounds))
        XCTAssertFalse(BorderlessWindowMoveGesture.hitsResizeGrip(
            NSPoint(x: 300, y: 60), contentBounds: contentBounds))
    }

    func testControlGestureIsDetectedFromEventOrCurrentModifierState() {
        XCTAssertTrue(BorderlessWindowMoveGesture.shouldBegin(
            controlInEvent: true, controlCurrentlyHeld: false))
        XCTAssertTrue(BorderlessWindowMoveGesture.shouldBegin(
            controlInEvent: false, controlCurrentlyHeld: true))
        XCTAssertFalse(BorderlessWindowMoveGesture.shouldBegin(
            controlInEvent: false, controlCurrentlyHeld: false))
    }

    func testControlClickWithoutDraggingDoesNotMoveWindow() {
        var gesture = BorderlessWindowMoveGesture()
        let frame = NSRect(x: 100, y: 120, width: 320, height: 320)
        gesture.begin(pointer: NSPoint(x: 300, y: 300), frame: frame, moveIntent: true)

        XCTAssertTrue(gesture.isTracking)
        XCTAssertNil(gesture.proposedOrigin(pointer: NSPoint(x: 301, y: 301),
                                            size: frame.size,
                                            visibleFrames: [NSRect(x: 0, y: 0,
                                                                   width: 1_000, height: 800)]))
        gesture.reset()

        XCTAssertFalse(gesture.isTracking)
        XCTAssertNil(gesture.proposedOrigin(pointer: NSPoint(x: 500, y: 500),
                                            size: frame.size,
                                            visibleFrames: [NSRect(x: 0, y: 0,
                                                                   width: 1_000, height: 800)]))
    }
}
