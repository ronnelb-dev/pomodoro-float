import SwiftUI

struct DeskClockPresentation: Equatable {
    let time: String
    let dateLine: String
}

enum DeskClockFormatter {
    static func presentation(for date: Date, locale: Locale = .current,
                             calendar: Calendar = .current,
                             timeZone: TimeZone = .current) -> DeskClockPresentation {
        DeskClockPresentation(
            time: formatted(date, template: "jmmss", locale: locale,
                            calendar: calendar, timeZone: timeZone),
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
                let timeSize = min(geometry.size.width * (compact ? 0.19 : 0.22),
                                   geometry.size.height * (compact ? 0.37 : 0.44))
                let dateSize = min(geometry.size.width * (compact ? 0.05 : 0.055),
                                   geometry.size.height * 0.11)
                VStack(spacing: compact ? 8 : 16) {
                    Text(presentation.time)
                        .font(.system(size: max(24, timeSize), weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.42)
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
                                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                        }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Desk clock")
                .accessibilityValue("\(presentation.time), \(presentation.dateLine)")
            }
        }
    }
}
