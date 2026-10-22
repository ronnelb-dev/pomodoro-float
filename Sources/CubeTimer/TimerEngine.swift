import Foundation

/// Pure countdown math. The deadline is a wall-clock date, so elapsed time during
/// backgrounding and Mac sleep is reflected on the next update.
enum TimerEngine {
    static let minimumDuration = 1
    static let maximumDuration = 99 * 60 + 59

    static func clampedDuration(_ seconds: Int) -> Int {
        min(max(seconds, minimumDuration), maximumDuration)
    }

    static func remaining(until deadline: Date, at now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    static func display(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func spokenDuration(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(remaining)))
        let minutes = seconds / 60
        let extraSeconds = seconds % 60
        let minutePart = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        let secondPart = "\(extraSeconds) second\(extraSeconds == 1 ? "" : "s")"
        if minutes == 0 { return secondPart }
        if extraSeconds == 0 { return minutePart }
        return "\(minutePart) and \(secondPart)"
    }

    static func progress(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }
}
