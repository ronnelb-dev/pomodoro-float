import SwiftUI

enum SevenSegmentEncoding {
    // Order: top, upper-right, lower-right, bottom, lower-left, upper-left, middle.
    static func segments(for digit: Character) -> [Bool]? {
        guard let value = digit.wholeNumberValue, (0...9).contains(value) else { return nil }

        let active: Set<Int>
        switch value {
        case 0: active = [0, 1, 2, 3, 4, 5]
        case 1: active = [1, 2]
        case 2: active = [0, 1, 3, 4, 6]
        case 3: active = [0, 1, 2, 3, 6]
        case 4: active = [1, 2, 5, 6]
        case 5: active = [0, 2, 3, 5, 6]
        case 6: active = [0, 2, 3, 4, 5, 6]
        case 7: active = [0, 1, 2]
        case 8: active = [0, 1, 2, 3, 4, 5, 6]
        case 9: active = [0, 1, 2, 3, 5, 6]
        default: return nil
        }
        return (0..<7).map(active.contains)
    }
}

struct SevenSegmentTimeDisplay: View {
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
