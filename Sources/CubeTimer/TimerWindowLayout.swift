import AppKit

struct TimerStandardLayoutMetrics: Equatable {
    let compact: Bool
    let spacing: CGFloat
    let verticalPadding: CGFloat
    let displayHeight: CGFloat
}

enum TimerWindowLayout {
    static let standardMinimumSize = NSSize(width: 350, height: 490)
    static let standardMaximumSize = NSSize(width: 850, height: 1_000)
    static let floatingMinimumSide: CGFloat = 240
    static let floatingMaximumSide: CGFloat = 850

    static func standardMetrics(size: NSSize, transientRowCount: Int = 0)
        -> TimerStandardLayoutMetrics {
        let compact = size.height < 610 || size.width < 390
        let spacing: CGFloat = compact ? 6 : 12
        let verticalPadding: CGFloat = compact ? 12 : 20
        let fixedHeight: CGFloat = 30 + 13 + 20 + (compact ? 49 : 56)
            + (compact ? 47 : 52) + 12 + spacing * 8 + verticalPadding * 2
            + CGFloat(max(0, transientRowCount)) * 15
        let displayHeight = min(510, max(160, size.height - fixedHeight))

        return TimerStandardLayoutMetrics(compact: compact, spacing: spacing,
                                          verticalPadding: verticalPadding,
                                          displayHeight: displayHeight)
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
