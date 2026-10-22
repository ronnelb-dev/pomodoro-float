import AppKit

/// Keeps a draggable cube reachable without blocking movement between displays.
enum BorderlessWindowPosition {
    static func restoredFrame(_ saved: NSRect, visibleFrames: [NSRect]) -> NSRect {
        guard let screen = visibleFrames.filter({ $0.width > 0 && $0.height > 0 }).max(by: {
            let a = NSIntersectionRect($0, saved)
            let b = NSIntersectionRect($1, saved)
            return a.width * a.height < b.width * b.height
        }) else { return saved }
        var frame = saved
        let side = min(screen.width, screen.height, 850,
                       max(240, min(saved.width, saved.height)))
        frame.size = NSSize(width: side, height: side)
        frame.origin = clampedOrigin(frame.origin, size: frame.size,
                                     visibleFrames: visibleFrames)
        return frame
    }

    static func clampedOrigin(_ proposed: NSPoint, size: NSSize,
                              visibleFrames: [NSRect], minimumVisible: CGFloat = 120) -> NSPoint {
        guard size.width > 0, size.height > 0, !visibleFrames.isEmpty else { return proposed }
        let candidates = visibleFrames.filter { $0.width > 0 && $0.height > 0 }.map { screen in
            let visibleWidth = min(minimumVisible, size.width, screen.width)
            let visibleHeight = min(minimumVisible, size.height, screen.height)
            return NSPoint(
                x: min(max(proposed.x, screen.minX + visibleWidth - size.width),
                       screen.maxX - visibleWidth),
                y: min(max(proposed.y, screen.minY + visibleHeight - size.height),
                       screen.maxY - visibleHeight)
            )
        }
        return candidates.min {
            hypot($0.x - proposed.x, $0.y - proposed.y) <
                hypot($1.x - proposed.x, $1.y - proposed.y)
        } ?? proposed
    }
}
