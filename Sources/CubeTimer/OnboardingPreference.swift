import Foundation

enum OnboardingPreference {
    static let hasSeenKey = "hasSeenOnboarding"

    static func shouldShowAutomatically(in defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: hasSeenKey)
    }

    static func markSeen(in defaults: UserDefaults) {
        defaults.set(true, forKey: hasSeenKey)
    }
}
