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
