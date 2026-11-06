import SwiftUI

struct DeskClockPresentation: Equatable {
    let time: String
    let segmentTime: String?
    let dayPeriod: String?
    let dayPeriodPlacement: DeskClockDayPeriodPlacement?
    let dateLine: String
}

enum DeskClockDayPeriodPlacement: Equatable {
    case leading
    case trailing
}

enum DeskClockFormatter {
    static func presentation(for date: Date, locale: Locale = .current,
                             calendar: Calendar = .current,
                             timeZone: TimeZone = .current) -> DeskClockPresentation {
        let time = formatted(date, template: "jmmss", locale: locale,
                             calendar: calendar, timeZone: timeZone)
        let localizedDayPeriod = formatted(date, template: "a", locale: locale,
                                           calendar: calendar, timeZone: timeZone)
        let dayPeriodRange: Range<String.Index>?
        if localizedDayPeriod.isEmpty {
            dayPeriodRange = nil
        } else {
            dayPeriodRange = time.range(of: localizedDayPeriod)
        }
        let dayPeriod = dayPeriodRange.map { _ in localizedDayPeriod }
        let dayPeriodPlacement: DeskClockDayPeriodPlacement?
        if let dayPeriodRange,
           let firstDigit = time.firstIndex(where: { $0.wholeNumberValue != nil }) {
            dayPeriodPlacement = dayPeriodRange.lowerBound < firstDigit ? .leading : .trailing
        } else {
            dayPeriodPlacement = nil
        }
        let timeWithoutDayPeriod: String
        if let dayPeriodRange {
            timeWithoutDayPeriod = String(time[..<dayPeriodRange.lowerBound])
                + String(time[dayPeriodRange.upperBound...])
        } else {
            timeWithoutDayPeriod = time
        }
        let candidateSegmentTime = timeWithoutDayPeriod
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segmentTime = !candidateSegmentTime.isEmpty &&
            candidateSegmentTime.allSatisfy({ $0 == ":" || $0.wholeNumberValue != nil })
            ? candidateSegmentTime : nil

        return DeskClockPresentation(
            time: time,
            segmentTime: segmentTime,
            dayPeriod: dayPeriod,
            dayPeriodPlacement: dayPeriodPlacement,
            dateLine: formatted(date, template: "EEEyMd", locale: locale,
                                calendar: calendar, timeZone: timeZone))
    }

    private static func formatted(_ date: Date, template: String, locale: Locale,
                                  calendar: Calendar, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

struct DeskClockPanel: View {
    let colors: UIColors
    let accent: Color
    let compact: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let presentation = DeskClockFormatter.presentation(for: context.date)
            GeometryReader { geometry in
                let digitHeight = DeskClockLayout.digitHeight(
                    containerSize: geometry.size, timeLabel: presentation.time,
                    compact: compact)
                let dateSize = min(geometry.size.width * (compact ? 0.05 : 0.055),
                                   geometry.size.height * 0.11)
                VStack(spacing: compact ? 8 : 16) {
                    if let segmentTime = presentation.segmentTime {
                        HStack(alignment: .center, spacing: max(4, digitHeight * 0.08)) {
                            if presentation.dayPeriodPlacement == .leading {
                                dayPeriodLabel(presentation.dayPeriod, digitHeight: digitHeight)
                            }
                            SevenSegmentTimeDisplay(timeLabel: segmentTime,
                                                    height: digitHeight, accent: accent)
                            if presentation.dayPeriodPlacement != .leading {
                                dayPeriodLabel(presentation.dayPeriod, digitHeight: digitHeight)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    } else {
                        Text(presentation.time)
                            .font(.system(size: max(24, digitHeight * 0.68),
                                          weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                            .accessibilityHidden(true)
                    }
                    Text(presentation.dateLine)
                        .font(.system(size: max(11, dateSize), weight: .semibold,
                                      design: .rounded))
                        .tracking(compact ? 0.8 : 1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(colors.secondary)
                }
                .foregroundStyle(colors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(compact ? 12 : 24)
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
                .accessibilityLabel("Desk clock")
                .accessibilityValue("\(presentation.time), \(presentation.dateLine)")
            }
        }
    }

    private func dayPeriodLabel(_ dayPeriod: String?, digitHeight: CGFloat) -> some View {
        Group {
            if let dayPeriod {
                Text(dayPeriod)
                    .font(.system(size: max(11, digitHeight * 0.24),
                                  weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(colors.secondary)
            }
        }
    }
}
