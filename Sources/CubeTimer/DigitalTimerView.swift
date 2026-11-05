import SwiftUI

enum DigitalTimerAccessibility {
    static func value(timeLabel: String, phaseLabel: String, statusLabel: String,
                      focusProgress: String?, isStopwatch: Bool = false) -> String {
        var value = "Time \(isStopwatch ? "elapsed" : "remaining") \(timeLabel), \(phaseLabel), \(statusLabel.lowercased())"
        if let focusProgress { value += ", focus progress \(focusProgress)" }
        return value
    }
}

enum DisplayFullscreenHint {
    static let durationSeconds = 3

    static func shouldShow(displayStyle: TimerDisplayStyle, isFullscreen: Bool) -> Bool {
        displayStyle.supportsFullscreen && isFullscreen
    }
}

enum DisplayFullscreenTransition {
    enum EntryAction: Equatable {
        case reject
        case toggleNow
        case waitForStandardWindow
    }

    enum ModeChangeAction: Equatable {
        case ignore
        case toggleNow
        case waitForStandardWindow
    }

    static func entryAction(supportsFullscreen: Bool, isNativeFullscreen: Bool,
                            isBorderless: Bool) -> EntryAction {
        guard supportsFullscreen else { return .reject }
        guard !isNativeFullscreen else { return .toggleNow }
        return isBorderless ? .waitForStandardWindow : .toggleNow
    }

    static func modeChangeAction(pendingEntry: Bool, windowMatches: Bool,
                                 isBorderless: Bool) -> ModeChangeAction {
        guard pendingEntry, windowMatches else { return .ignore }
        return isBorderless ? .waitForStandardWindow : .toggleNow
    }
}

enum SevenSegmentEncoding {
    // Order: top, upper-right, lower-right, bottom, lower-left, upper-left, middle.
    static func segments(for digit: Character) -> [Bool]? {
        let active: Set<Int>
        switch digit {
        case "0": active = [0, 1, 2, 3, 4, 5]
        case "1": active = [1, 2]
        case "2": active = [0, 1, 3, 4, 6]
        case "3": active = [0, 1, 2, 3, 6]
        case "4": active = [1, 2, 5, 6]
        case "5": active = [0, 2, 3, 5, 6]
        case "6": active = [0, 2, 3, 4, 5, 6]
        case "7": active = [0, 1, 2]
        case "8": active = [0, 1, 2, 3, 4, 5, 6]
        case "9": active = [0, 1, 2, 3, 5, 6]
        default: return nil
        }
        return (0..<7).map(active.contains)
    }
}

enum DigitalTimerLayout {
    static func aspectRatio(for timeLabel: String) -> CGFloat {
        max(2.2, timeLabel.reduce(0.0) { width, character in
            width + (character == ":" ? 0.18 : 0.62) + 0.055
        })
    }

    static func digitHeight(containerSize: CGSize, timeLabel: String, compact: Bool,
                            hasSessionNotice: Bool) -> CGFloat {
        let spacing = compact ? CGFloat(8) : CGFloat(16)
        let verticalPadding = compact ? CGFloat(24) : CGFloat(48)
        let phaseRow = compact ? CGFloat(11) : CGFloat(14)
        let noticeRow = hasSessionNotice ? (compact ? CGFloat(20) : CGFloat(24)) : 0
        let progressRow = compact ? CGFloat(3) : CGFloat(5)
        let gaps = hasSessionNotice ? 3 : 2
        let fixedHeight = verticalPadding + phaseRow + noticeRow + progressRow
            + spacing * CGFloat(gaps)
        let availableHeight = max(0, containerSize.height - fixedHeight)
        let availableWidth = max(0, containerSize.width)
        return min(availableHeight, availableWidth / aspectRatio(for: timeLabel))
    }
}

struct DigitalTimerPanel: View {
    let timeLabel: String
    let phaseLabel: String
    let statusLabel: String
    let focusProgress: String?
    let sessionNotice: String?
    let progress: Double
    let showsProgress: Bool
    let accent: Color
    let colors: UIColors
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let digitHeight = DigitalTimerLayout.digitHeight(
                containerSize: geometry.size, timeLabel: timeLabel,
                compact: compact, hasSessionNotice: sessionNotice != nil)

            VStack(spacing: compact ? 8 : 16) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusLabel == "RUNNING" ? accent : colors.secondary)
                        .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                    Text(phaseLabel.uppercased())
                        .font(.system(size: compact ? 9 : 12, weight: .bold,
                                      design: .rounded))
                        .tracking(compact ? 1.1 : 1.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text(statusLabel)
                        .font(.system(size: compact ? 8 : 10, weight: .semibold,
                                      design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(colors.secondary)
                }
                .foregroundStyle(colors.text)

                if let sessionNotice {
                    Text(sessionNotice)
                        .font(.system(size: compact ? 8 : 10, weight: .medium,
                                      design: .rounded))
                        .foregroundStyle(colors.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SevenSegmentTimeDisplay(timeLabel: timeLabel, height: digitHeight,
                                        accent: accent)
                    .frame(height: digitHeight)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                if showsProgress {
                    HStack(spacing: 10) {
                        if let focusProgress {
                            Text("FOCUS  \(focusProgress)")
                                .font(.system(size: compact ? 8 : 10, weight: .bold,
                                              design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(colors.secondary)
                        }
                        GeometryReader { progressGeometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(colors.edge)
                                Capsule()
                                    .fill(accent)
                                    .frame(width: progressGeometry.size.width *
                                           min(1, max(0, progress)))
                            }
                        }
                        .frame(height: compact ? 3 : 5)
                        .accessibilityHidden(true)
                    }
                }
            }
            .padding(compact ? 12 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: compact ? 18 : 26, style: .continuous)
                    .fill(colors.panel.opacity(compact ? 0.90 : 0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 18 : 26,
                                         style: .continuous)
                            .strokeBorder(colors.edge, lineWidth: 1)
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Digital timer")
            .accessibilityValue(DigitalTimerAccessibility.value(
                timeLabel: timeLabel, phaseLabel: phaseLabel,
                statusLabel: statusLabel, focusProgress: focusProgress,
                isStopwatch: !showsProgress))
        }
    }
}

private struct SevenSegmentTimeDisplay: View {
    let timeLabel: String
    let height: CGFloat
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: height * 0.055) {
            ForEach(Array(timeLabel.enumerated()), id: \.offset) { _, character in
                if character == ":" {
                    VStack(spacing: height * 0.19) {
                        dot
                        dot
                    }
                    .frame(width: height * 0.12, height: height * 0.58)
                } else if let segments = SevenSegmentEncoding.segments(for: character) {
                    SevenSegmentDigit(segments: segments, accent: accent)
                        .frame(width: height * 0.58, height: height)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var dot: some View {
        Circle()
            .fill(accent)
            .frame(width: height * 0.085, height: height * 0.085)
            .shadow(color: accent.opacity(0.55), radius: height * 0.035)
    }
}

private struct SevenSegmentDigit: View {
    let segments: [Bool]
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let thickness = min(width * 0.18, height * 0.105)
            let verticalLength = height * 0.39
            let positions: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (width / 2, thickness / 2, width * 0.68, thickness),
                (width - thickness / 2, height * 0.275, thickness, verticalLength),
                (width - thickness / 2, height * 0.725, thickness, verticalLength),
                (width / 2, height - thickness / 2, width * 0.68, thickness),
                (thickness / 2, height * 0.725, thickness, verticalLength),
                (thickness / 2, height * 0.275, thickness, verticalLength),
                (width / 2, height / 2, width * 0.68, thickness)
            ]

            ForEach(0..<7, id: \.self) { index in
                let position = positions[index]
                RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
                    .fill(accent.opacity(segments[index] ? 1 : 0.10))
                    .shadow(color: segments[index] ? accent.opacity(0.58) : .clear,
                            radius: segments[index] ? thickness * 0.52 : 0)
                    .frame(width: position.2, height: position.3)
                    .position(x: position.0, y: position.1)
            }
        }
    }
}
