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
        return Self.migrateToCurrentPresetSlots(saved)
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
        let validPresetIndices = saved.version >= 7 ? 0..<6 : 0..<5
        guard (1...7).contains(saved.version),
              (saved.version < 6 || saved.sessionKind != nil),
              validPresetIndices.contains(saved.selectedPreset),
              saved.total.isFinite,
              (1...Double(TimerEngine.maximumDuration)).contains(saved.total),
              (saved.sessionKind != .stopwatch || saved.total == Double(TimerEngine.maximumDuration)),
              (saved.sessionKind != .stopwatch || !(saved.activeFlowEnabled ?? defaultFlowEnabled)),
              (saved.sessionKind != .customCountdown || !(saved.activeFlowEnabled ?? defaultFlowEnabled)),
              (saved.version < 5 || saved.cycleTarget != nil),
              (2...8).contains(saved.cycleTarget ?? 4),
              (0...(saved.cycleTarget ?? 4)).contains(saved.focusesInCycle ?? 0),
              (saved.completedFocusTotal ?? 0) >= 0,
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

    private static func migrateToCurrentPresetSlots(_ saved: SavedTimerSession) -> SavedTimerSession {
        guard saved.version < 7 else { return saved }
        return SavedTimerSession(
            version: 7,
            state: saved.state,
            selectedPreset: PresetSlotMigration.currentIndex(fromLegacy: saved.selectedPreset),
            phase: saved.phase,
            total: saved.total,
            deadline: saved.deadline,
            pausedRemaining: saved.pausedRemaining,
            bootSessionID: saved.bootSessionID,
            continuousDeadline: saved.continuousDeadline,
            activeFlowEnabled: saved.activeFlowEnabled,
            pomodoroModeEnabled: saved.pomodoroModeEnabled,
            pendingFlowEnabled: saved.pendingFlowEnabled,
            suspendedPomodoro: saved.suspendedPomodoro,
            focusesInCycle: saved.focusesInCycle,
            completedFocusTotal: saved.completedFocusTotal,
            cycleTarget: saved.cycleTarget,
            sessionKind: saved.sessionKind)
    }
}
