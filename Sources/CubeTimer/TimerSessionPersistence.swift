import Foundation

/// Owns the versioned timer-session record stored in UserDefaults.
struct TimerSessionPersistence {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load(defaultFlowEnabled: Bool,
               defaultPomodoroModeEnabled: Bool) -> SavedTimerSession? {
        guard let data = defaults.data(forKey: SavedTimerSession.key) else { return nil }
        guard let saved = try? decoder.decode(SavedTimerSession.self, from: data),
              Self.isValid(saved, defaultFlowEnabled: defaultFlowEnabled,
                           defaultPomodoroModeEnabled: defaultPomodoroModeEnabled) else {
            clear()
            return nil
        }
        return saved
    }

    func save(_ session: SavedTimerSession) {
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: SavedTimerSession.key)
    }

    func clear() {
        defaults.removeObject(forKey: SavedTimerSession.key)
    }

    private static func isValid(_ saved: SavedTimerSession,
                                defaultFlowEnabled: Bool,
                                defaultPomodoroModeEnabled: Bool) -> Bool {
        guard (1...6).contains(saved.version),
              (saved.version < 6 || saved.sessionKind != nil),
              (0..<5).contains(saved.selectedPreset),
              saved.total.isFinite,
              (1...Double(TimerEngine.maximumDuration)).contains(saved.total),
              (saved.sessionKind != .stopwatch || saved.total == Double(TimerEngine.maximumDuration)),
              (saved.sessionKind != .stopwatch || !(saved.activeFlowEnabled ?? defaultFlowEnabled)),
              (saved.sessionKind != .customCountdown || !(saved.activeFlowEnabled ?? defaultFlowEnabled)),
              (saved.version < 5 || saved.cycleTarget != nil),
              (2...8).contains(saved.cycleTarget ?? 4),
              (0...(saved.cycleTarget ?? 4)).contains(saved.focusesInCycle ?? 0),
              (saved.completedFocusTotal ?? 0) >= 0,
              !(saved.activeFlowEnabled ?? defaultFlowEnabled) ||
                  saved.selectedPreset == saved.phase.presetIndex,
              saved.suspendedPomodoro == nil ||
                  ((saved.pomodoroModeEnabled ?? defaultPomodoroModeEnabled) &&
                   !(saved.activeFlowEnabled ?? defaultFlowEnabled)) else {
            return false
        }
        if let suspended = saved.suspendedPomodoro {
            return suspended.total.isFinite && suspended.remaining.isFinite &&
                (1...Double(TimerEngine.maximumDuration)).contains(suspended.total) &&
                (0...suspended.total).contains(suspended.remaining)
        }
        return true
    }
}
