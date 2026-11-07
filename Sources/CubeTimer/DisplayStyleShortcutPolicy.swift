import Foundation

struct DisplayStyleShortcutPolicy {
    struct Entry: Equatable {
        let number: Character
        let style: TimerDisplayStyle
    }

    static let entries: [Entry] = [
        Entry(number: "1", style: .cube),
        Entry(number: "2", style: .digital),
        Entry(number: "3", style: .clock)
    ]

    static func style(forCommandShiftNumber number: Character) -> TimerDisplayStyle? {
        entries.first { $0.number == number }?.style
    }
}

enum PresetShortcutPolicy {
    static func commandNumber(forPresetIndex index: Int) -> Character? {
        guard (0..<6).contains(index) else { return nil }
        return Character(String(index + 1))
    }
}

enum PresetTileAccessibilityPolicy {
    static func hint(displayStyle: TimerDisplayStyle) -> String {
        if displayStyle == .cube {
            return AppStrings.localized(
                "Starts or restarts this preset immediately and plays the preset sound.")
        }
        return AppStrings.localized("Selects this preset without starting the timer.")
    }
}
