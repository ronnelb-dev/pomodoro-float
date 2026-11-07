import SwiftUI

struct WelcomeGuideView: View {
    @EnvironmentObject private var appearance: AppearanceModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingPreference.hasSeenKey) private var hasSeenOnboarding = false

    private let sections: [(title: String, symbol: String)] = [
        ("Displays", "cube.fill"),
        ("Presets and Pomodoro", "square.grid.2x2"),
        ("Countdown and Stopwatch", "stopwatch"),
        ("Sounds and shortcuts", "keyboard"),
        ("Floating window", "macwindow")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(appearance.value.accent.swiftUIColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.localized("welcome.title"))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(AppStrings.localized("welcome.subtitle"))
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(sections, id: \.title) { section in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: section.symbol)
                                .frame(width: 22)
                                .foregroundStyle(appearance.value.accent.swiftUIColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(AppStrings.localized("welcome.section.\(section.title)"))
                                    .font(.headline)
                                Text(AppStrings.localized("welcome.detail.\(section.title)"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(AppStrings.localized("welcome.skip"), action: finish)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(AppStrings.localized("welcome.getStarted"), action: finish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 510)
        .background(appearance.value.body.swiftUIColor)
    }

    private func finish() {
        OnboardingPreference.markSeen(in: .standard)
        hasSeenOnboarding = true
        dismiss()
    }
}
