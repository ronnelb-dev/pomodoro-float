import AppKit

struct TimerStandardLayoutMetrics: Equatable {
    let compact: Bool
    let spacing: CGFloat
    let verticalPadding: CGFloat
    let displayHeight: CGFloat
}

enum TimerWindowLevelPolicy {
    static func shouldFloat(alwaysOnTop: Bool, isFullscreen: Bool) -> Bool {
        shouldFloat(alwaysOnTop: alwaysOnTop, isFullscreen: isFullscreen,
                    fullscreenTransitionActive: false)
    }

    static func shouldFloat(alwaysOnTop: Bool, isFullscreen: Bool,
                            fullscreenTransitionActive: Bool) -> Bool {
        alwaysOnTop && !isFullscreen && !fullscreenTransitionActive
    }
}

enum DisplayFullscreenExitPolicy {
    static func shouldExit(nativeFullscreen: Bool, modelFullscreen: Bool) -> Bool {
        nativeFullscreen || modelFullscreen
    }
}

enum DeskClockLayout {
    static func fullscreenPanelWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth * 0.85)
    }

    static func digitHeight(containerSize: CGSize, timeLabel: String,
                            compact: Bool) -> CGFloat {
        let padding: CGFloat = compact ? 12 : 24
        let dateHeight: CGFloat = compact ? 18 : 24
        let spacing: CGFloat = compact ? 8 : 16
        let availableWidth = max(0, containerSize.width - padding * 2)
        let availableHeight = max(0, containerSize.height - padding * 2
                                  - dateHeight - spacing)
        return min(availableHeight,
                   availableWidth / DigitalTimerLayout.aspectRatio(for: timeLabel))
    }
}

enum TimerWindowLayout {
    static let standardMinimumSize = NSSize(width: 420, height: 560)
    static let standardMaximumSize = NSSize(width: 850, height: 1_000)
    static let floatingMinimumSide: CGFloat = 240
    static let floatingMaximumSide: CGFloat = 850
    static let standardContentWidth: CGFloat = 610
    static let digitalPanelMaximumWidth: CGFloat = 1_200
    static let headerPickerRegularWidth: CGFloat = 126
    static let headerPickerMinimumWidth: CGFloat = 108
    static let immersiveCubeHeaderHeight: CGFloat = 36
    static let immersiveCubeReadoutHeight: CGFloat = 40
    static let immersiveCubeReadoutSpacing: CGFloat = 8
    private static let expandedPanelWidthFraction: CGFloat = 0.85

    static func immersiveCubeSide(availableSize: NSSize,
                                  reservedHeight: CGFloat = 0) -> CGFloat {
        let contentHeight = max(0, availableSize.height - max(0, reservedHeight))
        return max(0, min(availableSize.width, contentHeight) * 0.88)
    }

    static func headerPickerWidth(availableWidth: CGFloat, compact: Bool) -> CGFloat {
        let availableWidth = max(0, availableWidth)
        let target = compact ? availableWidth - 180 : headerPickerRegularWidth
        return min(headerPickerRegularWidth,
                   max(headerPickerMinimumWidth, target))
    }

    static func standardMetrics(size: NSSize, transientRowCount: Int = 0,
                                expandsDigitalDisplay: Bool = false)
        -> TimerStandardLayoutMetrics {
        let compact = size.height < 610 || size.width < 390
        let spacing: CGFloat = compact ? 6 : 12
        let verticalPadding: CGFloat = compact ? 12 : 20
        let fixedHeight: CGFloat = 30 + 13 + 20 + (compact ? 49 : 56)
            + (compact ? 36 : 44) + (compact ? 47 : 52) + 12
            + spacing * 9 + verticalPadding * 2
            + CGFloat(max(0, transientRowCount)) * 15
        let availableDisplayHeight = max(160, size.height - fixedHeight)
        let displayHeight = expandsDigitalDisplay
            ? availableDisplayHeight : min(510, availableDisplayHeight)

        return TimerStandardLayoutMetrics(compact: compact, spacing: spacing,
                                          verticalPadding: verticalPadding,
                                          displayHeight: displayHeight)
    }

    static func digitalPanelWidth(availableWidth: CGFloat) -> CGFloat {
        let availableWidth = max(0, availableWidth)
        guard availableWidth > standardContentWidth else { return availableWidth }
        return min(availableWidth, digitalPanelMaximumWidth,
                   max(standardContentWidth, availableWidth * expandedPanelWidthFraction))
    }

    static func standardClockPanelWidth(availableWidth: CGFloat) -> CGFloat {
        min(standardContentWidth, max(0, availableWidth))
    }

    static func resizedFloatingFrame(start: NSRect, horizontalDelta: CGFloat,
                                     verticalDelta: CGFloat,
                                     visibleFrame: NSRect?) -> NSRect {
        let delta = abs(horizontalDelta) >= abs(verticalDelta)
            ? horizontalDelta : verticalDelta
        let available = visibleFrame.map {
            min(floatingMaximumSide, $0.width, $0.height,
                $0.maxX - start.minX, start.maxY - $0.minY)
        } ?? floatingMaximumSide
        let maximumSide = max(floatingMinimumSide, available)
        let side = min(maximumSide,
                       max(floatingMinimumSide, start.width + delta))
        return NSRect(x: start.minX, y: start.maxY - side,
                      width: side, height: side)
    }
}

enum StandardWindowPosition {
    static func isBelowMinimum(_ frame: NSRect) -> Bool {
        frame.width < TimerWindowLayout.standardMinimumSize.width ||
            frame.height < TimerWindowLayout.standardMinimumSize.height
    }

    static func restoredFrame(_ saved: NSRect, visibleFrames: [NSRect]) -> NSRect {
        var frame = saved
        let screen = visibleFrames.max {
            let a = NSIntersectionRect($0, frame)
            let b = NSIntersectionRect($1, frame)
            return a.width * a.height < b.width * b.height
        }
        guard let visible = screen else { return frame }

        frame.size.width = min(visible.width, TimerWindowLayout.standardMaximumSize.width,
                               max(TimerWindowLayout.standardMinimumSize.width, frame.width))
        frame.size.height = min(visible.height, TimerWindowLayout.standardMaximumSize.height,
                                max(TimerWindowLayout.standardMinimumSize.height, frame.height))
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        return frame
    }
}

struct BorderlessWindowMoveGesture {
    private static let resizeGripHitSize: CGFloat = 48
    private var startPointer: NSPoint?
    private var startOrigin: NSPoint?
    private(set) var hasMoved = false

    var isTracking: Bool { startPointer != nil }

    static func shouldBegin(controlInEvent: Bool, controlCurrentlyHeld: Bool) -> Bool {
        controlInEvent || controlCurrentlyHeld
    }

    mutating func begin(pointer: NSPoint, frame: NSRect, moveIntent: Bool) {
        reset()
        guard moveIntent else { return }
        startPointer = pointer
        startOrigin = frame.origin
    }

    static func hitsResizeGrip(_ point: NSPoint, contentBounds: NSRect) -> Bool {
        point.x >= contentBounds.maxX - resizeGripHitSize &&
            point.y <= contentBounds.minY + resizeGripHitSize
    }

    mutating func proposedOrigin(pointer: NSPoint, size: NSSize,
                                 visibleFrames: [NSRect]) -> NSPoint? {
        guard let startPointer, let startOrigin else { return nil }
        let dx = pointer.x - startPointer.x
        let dy = pointer.y - startPointer.y
        guard hasMoved || hypot(dx, dy) > 5 else { return nil }
        hasMoved = true
        return BorderlessWindowPosition.clampedOrigin(
            NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy),
            size: size, visibleFrames: visibleFrames)
    }

    mutating func reset() {
        startPointer = nil
        startOrigin = nil
        hasMoved = false
    }
}
