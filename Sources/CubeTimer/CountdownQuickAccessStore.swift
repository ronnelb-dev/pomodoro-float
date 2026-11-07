import Foundation

enum FavoriteCountdownToggleResult: Equatable {
    case added
    case removed
    case limitReached
    case invalidDuration
}

/// Persists one-off Countdown shortcuts separately from timer sessions and presets.
struct CountdownQuickAccessStore {
    static let maximumRecentCount = 5
    static let maximumFavoriteCount = 5

    private enum Key {
        static let recent = "countdownRecentDurations.v1"
        static let favorites = "countdownFavoriteDurations.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var recentDurations: [Int] {
        loadDurations(forKey: Key.recent, limit: Self.maximumRecentCount)
    }

    var favoriteDurations: [Int] {
        loadDurations(forKey: Key.favorites, limit: Self.maximumFavoriteCount)
    }

    func recordStarted(_ seconds: Int) {
        guard Self.isValidDuration(seconds) else { return }
        let updated = ([seconds] + recentDurations.filter { $0 != seconds })
            .prefix(Self.maximumRecentCount)
        defaults.set(Array(updated), forKey: Key.recent)
    }

    func toggleFavorite(_ seconds: Int) -> FavoriteCountdownToggleResult {
        guard Self.isValidDuration(seconds) else { return .invalidDuration }

        var favorites = favoriteDurations
        if favorites.contains(seconds) {
            favorites.removeAll { $0 == seconds }
            defaults.set(favorites, forKey: Key.favorites)
            return .removed
        }

        guard favorites.count < Self.maximumFavoriteCount else { return .limitReached }
        favorites.insert(seconds, at: 0)
        defaults.set(favorites, forKey: Key.favorites)
        return .added
    }

    func clearRecent() {
        defaults.removeObject(forKey: Key.recent)
    }

    private func loadDurations(forKey key: String, limit: Int) -> [Int] {
        guard let values = defaults.array(forKey: key) as? [Int] else { return [] }
        var seen = Set<Int>()
        return values.filter { value in
            Self.isValidDuration(value) && seen.insert(value).inserted
        }.prefix(limit).map { $0 }
    }

    private static func isValidDuration(_ seconds: Int) -> Bool {
        (TimerEngine.minimumDuration...TimerEngine.maximumDuration).contains(seconds)
    }
}
