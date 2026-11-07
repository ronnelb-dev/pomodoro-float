import AppKit
import AVFoundation
import Combine
import Foundation
import UserNotifications
import Darwin

enum PresetRole: String, CaseIterable, Codable {
    case shortBreak
    case focus
    case general

    var title: String {
        switch self {
        case .shortBreak: "Short Break"
        case .focus: "Focus"
        case .general: "General"
        }
    }

    var pomodoroDescription: String {
        switch self {
        case .shortBreak: "Used for Pomodoro short breaks."
        case .focus: "Used for Pomodoro focus phases."
        case .general: "Starts as an independent timer outside Pomodoro phases."
        }
    }
}

struct SystemTimerTimeSource: TimerTimeSource {
    var wallNow: Date { Date() }
    // CLOCK_MONOTONIC_RAW advances during sleep and ignores wall-clock changes.
    var continuousNow: TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
    let bootSessionID: String? = {
        var length = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &length, nil, 0) == 0,
              length > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &length, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }()
}


private struct PresetUndo {
    let session: SavedTimerSession
    let flowEnabled: Bool
    let modeEnabled: Bool
    let pendingFlowEnabled: Bool?
    let suspendedPomodoro: SuspendedPomodoroSession?
    let continuousExpiresAt: TimeInterval
    let id: UUID
}


struct TimerSessionPreferences: Equatable {
    var presetSeconds: [Int]
    var longBreakSeconds: Int
    var requestedCycleTarget: Int
    var autoStartNextPhase: Bool
}

struct TimerSessionTime: Equatable {
    let wallNow: Date
    let continuousNow: TimeInterval
    let bootSessionID: String?
}

struct TimerSessionCommand {
    enum Action {
        case selectPreset(Int)
        case startCustomCountdown(Int)
        case startStopwatch
        case selectAndStartPreset(Int)
        case selectAndStartCubeFace(Int)
        case turn(Int)
        case setPreset(Int, Int)
        case setLongBreak(Int)
        case editDuration(DurationSetting, Int, DurationEditAction)
        case setCycleTarget(Int)
        case setFlowEnabled(Bool)
        case resumePomodoro
        case startOrPause
        case startNextPhase
        case skipBreak
        case start
        case pause
        case reset
        case refresh(afterWake: Bool)
        case prepareForSleep
        case resumeAfterSleep
        case undoPresetChange
    }

    let action: Action
    let preferences: TimerSessionPreferences
    let time: TimerSessionTime
}

struct TimerSessionSnapshot: Equatable {
    let sessionKind: TimerSessionKind
    let selectedPreset: Int
    let phase: SessionPhase
    let remaining: TimeInterval
    let total: TimeInterval
    let isRunning: Bool
    let isPaused: Bool
    let isComplete: Bool
    let flowEnabled: Bool
    let pomodoroModeEnabled: Bool
    let pendingFlowEnabled: Bool?
    let suspendedPomodoro: SuspendedPomodoroSession?
    let presetSeconds: [Int]
    let longBreakSeconds: Int
    let focusesInCycle: Int
    let completedFocusTotal: Int
    let cycleTarget: Int
    let requestedCycleTarget: Int
    let alertText: String?
    let undoPresetLabel: String?
}

enum TimerSessionEvent: Equatable {
    case started
    case paused
    case completed
    case reset
    case phaseChanged(from: SessionPhase, to: SessionPhase)
}

struct TimerSessionUpdate {
    let snapshot: TimerSessionSnapshot
    let events: [TimerSessionEvent]
    let accepted: Bool
}


@MainActor
final class TimerSessionCoordinator: ObservableObject {
    static let defaultPresetNames = ["5 MIN", "10 MIN", "25 MIN", "30 MIN", "45 MIN", "60 MIN"]
    static let defaultDurations = [300, 600, 1500, 1800, 2700, 3600]
    static func spokenPresetName(_ index: Int) -> String {
        "\(defaultDurations[index] / 60)-minute preset"
    }

    @Published private(set) var presetSeconds: [Int]
    @Published private(set) var presetNames: [String]
    @Published private(set) var presetRoles: [PresetRole]
    @Published private(set) var sessionKind: TimerSessionKind = .presetCountdown
    @Published private(set) var selectedPreset: Int
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var total: TimeInterval
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isComplete = false
    @Published private(set) var flowEnabled: Bool
    @Published private(set) var pomodoroModeEnabled: Bool
    @Published private(set) var pendingFlowEnabled: Bool?
    @Published private(set) var suspendedPomodoro: SuspendedPomodoroSession?
    @Published private(set) var phase: SessionPhase = .focus
    @Published private(set) var focusesInCycle = 0
    @Published private(set) var completedFocusTotal = 0
    @Published private(set) var longBreakSeconds: Int
    @Published private(set) var cycleTarget: Int
    @Published private(set) var requestedCycleTarget: Int
    @Published private(set) var alertText: String?
    @Published private(set) var undoPresetLabel: String?

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }
    @Published private(set) var borderlessWindow: Bool {
        didSet { defaults.set(borderlessWindow, forKey: "borderlessWindow") }
    }
    @Published var muted: Bool {
        didSet {
            defaults.set(muted, forKey: "muted")
            scheduleCurrentNotification()
        }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: "volume") }
    }
    @Published var autoStartNextPhase: Bool {
        didSet { defaults.set(autoStartNextPhase, forKey: "autoStartNextPhase") }
    }

    var progress: Double { sessionKind == .stopwatch ? 0 : TimerEngine.progress(remaining: remaining, total: total) }
    var timeLabel: String { sessionKind == .stopwatch ?
        TimerEngine.stopwatchDisplay(remaining) : TimerEngine.display(remaining) }
    var requestedFlowEnabled: Bool { pendingFlowEnabled ?? pomodoroModeEnabled }
    var hasSuspendedPomodoro: Bool { suspendedPomodoro != nil }
    var longBreakDue: Bool { focusesInCycle >= cycleTarget }
    var focusProgressLabel: String { "\(focusesInCycle)/\(cycleTarget)" }
    var cycleTargetChangePending: Bool { cycleTarget != requestedCycleTarget }
    var focusPresetIndex: Int { presetRoles.firstIndex(of: .focus) ?? 2 }
    var shortBreakPresetIndex: Int { presetRoles.firstIndex(of: .shortBreak) ?? 0 }
    private static func defaultRole(for index: Int) -> PresetRole {
        index == 0 ? .shortBreak : index == 2 ? .focus : .general
    }
    private func presetIndex(for phase: SessionPhase) -> Int {
        phase == .focus ? focusPresetIndex : shortBreakPresetIndex
    }
    private func restoredPresetIndex(for phase: SessionPhase, savedIndex: Int) -> Int {
        flowEnabled && phase != .longBreak ? presetIndex(for: phase) : savedIndex
    }
    private var upcomingPhase: SessionPhase {
        phase == .focus ? (longBreakDue ? .longBreak : .breakTime) : .focus
    }
    var nextPhaseName: String? {
        guard flowEnabled, isComplete else { return nil }
        return upcomingPhase.displayName
    }
    var canSkipBreak: Bool {
        flowEnabled && (phase.isBreak && !isComplete ||
                        phase == .focus && isComplete && longBreakDue)
    }
    var skipBreakName: String {
        phase == .longBreak || phase == .focus && longBreakDue
            ? "Skip Long Break" : "Skip Short Break"
    }
    func presetBecomesOneOff(_ index: Int) -> Bool {
        flowEnabled && (![focusPresetIndex, shortBreakPresetIndex].contains(index) || longBreakDue || phase == .longBreak)
    }
    var pendingModeDescription: String? {
        guard let pendingFlowEnabled else { return nil }
        return "Pomodoro will turn \(pendingFlowEnabled ? "on" : "off") when this timer finishes"
    }
    var accessibilityValue: String {
        let state = isComplete ? "Complete" : isRunning ? "Running" : isPaused ? "Paused" : "Ready"
        let session = sessionKind == .stopwatch
            ? "Stopwatch, \(TimerEngine.spokenDuration(remaining.rounded(.down))) elapsed"
            : sessionKind == .customCountdown
            ? "Countdown"
            : flowEnabled
            ? "\(phase.displayName) session, \(phase == .longBreak ? TimerEngine.spokenDuration(total) : presetNames[selectedPreset])"
            : "\(presetNames[selectedPreset])\(hasSuspendedPomodoro ? ", Pomodoro paused" : "")"
        let count = pomodoroModeEnabled
            ? ", \(focusesInCycle) of \(cycleTarget) focuses toward long break, \(completedFocusTotal) completed focuses total"
            : ""
        return sessionKind == .stopwatch ? "\(session), \(state)\(count)" :
            "\(session), \(state), \(TimerEngine.spokenDuration(remaining)) remaining\(count)"
    }
    private let defaults: UserDefaults
    private let sessionPersistence: TimerSessionPersistence
    private let timeSource: TimerTimeSource
    private var commandTime: (wall: Date, continuous: TimeInterval)?
    private let testOriginWall: Date
    private let testOriginContinuous: TimeInterval
    private let notifications: CompletionNotificationClient?
    private var deadline: Date?
    private var continuousDeadline: TimeInterval?
    private var clock: Timer?
    private var alertClearTask: Task<Void, Never>?
    private let sound: CompletionSoundClient
    private let presetSound: PresetSoundClient
    private let appIsActive: @MainActor () -> Bool
    private let accessibilityAnnouncer: TimerAccessibilityAnnouncementClient
    private var wasSleeping = false
    private var presetUndo: PresetUndo?
    private var undoExpiryTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, notificationsEnabled: Bool = true,
         now: Date = Date(), notificationClient: CompletionNotificationClient? = nil,
         soundClient: CompletionSoundClient? = nil,
         presetSoundClient: PresetSoundClient? = nil,
         timeSource: TimerTimeSource = SystemTimerTimeSource(),
         appIsActive: @escaping @MainActor () -> Bool = {
             NSApp?.isActive == true && NSApp?.isHidden == false
         },
         accessibilityAnnouncer: TimerAccessibilityAnnouncementClient? = nil) {
        self.defaults = defaults
        sessionPersistence = TimerSessionPersistence(defaults: defaults)
        let hadExistingPresetData = PresetSlotMigration.hasExistingPresetData(in: defaults)
        PresetSlotMigration.migratePreferences(in: defaults)
        self.timeSource = timeSource
        testOriginWall = now
        testOriginContinuous = timeSource.continuousNow
        notifications = notificationsEnabled ? (notificationClient ?? CompletionNotifications.shared) : nil
        sound = soundClient ?? CompletionSound()
        presetSound = presetSoundClient ?? PresetSound()
        self.appIsActive = appIsActive
        self.accessibilityAnnouncer = accessibilityAnnouncer ?? SystemTimerAccessibilityAnnouncer()
        let loadedPresets = Self.defaultDurations.enumerated().map { index, fallback in
            let key = "presetSeconds.\(index)"
            return defaults.object(forKey: key) == nil
                ? fallback
                : TimerEngine.clampedDuration(defaults.integer(forKey: key))
        }
        let loadedNames = Self.defaultPresetNames.enumerated().map { index, fallback in
            let stored = defaults.string(forKey: "presetName.\(index)")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored.map { String($0.prefix(32)) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        }
        var loadedRoles = Self.defaultDurations.indices.map { index in
            let fallback = Self.defaultRole(for: index)
            return defaults.string(forKey: "presetRole.\(index)")
                .flatMap(PresetRole.init(rawValue:)) ?? fallback
        }
        if let focus = loadedRoles.firstIndex(of: .focus) {
            for index in loadedRoles.indices where index != focus && loadedRoles[index] == .focus {
                loadedRoles[index] = .general
            }
        }
        if let shortBreak = loadedRoles.firstIndex(of: .shortBreak) {
            for index in loadedRoles.indices where index != shortBreak && loadedRoles[index] == .shortBreak {
                loadedRoles[index] = .general
            }
        }
        if !loadedRoles.contains(.focus) {
            let index = loadedRoles.indices.first { loadedRoles[$0] != .shortBreak } ?? 2
            loadedRoles[index] = .focus
        }
        if !loadedRoles.contains(.shortBreak) {
            let index = loadedRoles.indices.first { loadedRoles[$0] != .focus } ?? 0
            loadedRoles[index] = .shortBreak
        }
        presetNames = loadedNames
        presetRoles = loadedRoles
        for index in loadedRoles.indices {
            defaults.set(loadedNames[index], forKey: "presetName.\(index)")
            defaults.set(loadedRoles[index].rawValue, forKey: "presetRole.\(index)")
        }
        let loadedFlow = defaults.bool(forKey: "flowEnabled")
        let loadedSelection = loadedFlow ? (loadedRoles.firstIndex(of: .focus) ?? 2) :
            defaults.object(forKey: "selectedPreset") == nil
                ? (hadExistingPresetData ? 0 : 2)
                : min(Self.defaultDurations.count - 1,
                      max(0, defaults.integer(forKey: "selectedPreset")))
        presetSeconds = loadedPresets
        longBreakSeconds = defaults.object(forKey: "longBreakSeconds") == nil
            ? 900 : TimerEngine.clampedDuration(defaults.integer(forKey: "longBreakSeconds"))
        let loadedCycleTarget = defaults.object(forKey: "focusesBeforeLongBreak") == nil
            ? 4 : min(8, max(2, defaults.integer(forKey: "focusesBeforeLongBreak")))
        cycleTarget = loadedCycleTarget
        requestedCycleTarget = loadedCycleTarget
        selectedPreset = loadedSelection
        defaults.set(loadedSelection, forKey: "selectedPreset")
        flowEnabled = loadedFlow
        pomodoroModeEnabled = loadedFlow
        pendingFlowEnabled = nil
        suspendedPomodoro = nil
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") == nil
            ? true : defaults.bool(forKey: "alwaysOnTop")
        borderlessWindow = defaults.bool(forKey: "borderlessWindow")
        muted = defaults.bool(forKey: "muted")
        volume = defaults.object(forKey: "volume") == nil
            ? 0.65 : min(1, max(0, defaults.double(forKey: "volume")))
        autoStartNextPhase = defaults.object(forKey: "autoStartNextPhase") == nil
            ? true : defaults.bool(forKey: "autoStartNextPhase")
        let loadedTotal = TimeInterval(loadedPresets[loadedSelection])
        total = loadedTotal
        remaining = loadedTotal

        clock = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(clock!, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.prepareForSleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAfterSleep() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        notifications?.requestPermission()
        restoreSession(at: now)
        // A running session replaces its request by identifier. Other states have no
        // pending completion and must clear any orphaned request from an older run.
        if !isRunning { notifications?.cancel() }
    }

    var sessionSnapshot: TimerSessionSnapshot {
        TimerSessionSnapshot(sessionKind: sessionKind, selectedPreset: selectedPreset, phase: phase,
                             remaining: remaining, total: total, isRunning: isRunning,
                             isPaused: isPaused, isComplete: isComplete,
                             flowEnabled: flowEnabled,
                             pomodoroModeEnabled: pomodoroModeEnabled,
                             pendingFlowEnabled: pendingFlowEnabled,
                             suspendedPomodoro: suspendedPomodoro,
                             presetSeconds: presetSeconds,
                             longBreakSeconds: longBreakSeconds,
                             focusesInCycle: focusesInCycle,
                             completedFocusTotal: completedFocusTotal,
                             cycleTarget: cycleTarget,
                             requestedCycleTarget: requestedCycleTarget,
                             alertText: alertText,
                             undoPresetLabel: undoPresetLabel)
    }

    @discardableResult
    func handle(_ command: TimerSessionCommand) -> TimerSessionUpdate {
        commandTime = (command.time.wallNow, command.time.continuousNow)
        defer { commandTime = nil }
        let before = sessionSnapshot
        var accepted = true
        switch command.action {
        case .selectPreset(let index): selectPreset(index)
        case .startCustomCountdown(let seconds):
            accepted = startCustomCountdown(seconds: seconds)
        case .startStopwatch: startStopwatch()
        case .selectAndStartPreset(let index): selectAndStartPreset(index)
        case .selectAndStartCubeFace(let index): selectAndStartCubeFace(index)
        case .turn(let direction): turn(direction)
        case .setPreset(let index, let seconds): setPreset(index, seconds: seconds)
        case .setLongBreak(let seconds): setLongBreak(seconds: seconds)
        case .editDuration(let setting, let seconds, let action):
            accepted = editDuration(setting, seconds: seconds, action: action)
        case .setCycleTarget(let target): setCycleTarget(target)
        case .setFlowEnabled(let enabled): setFlowEnabled(enabled)
        case .resumePomodoro: accepted = resumePomodoro()
        case .startOrPause: startOrPause()
        case .startNextPhase: startNextPhase()
        case .skipBreak: skipBreak()
        case .start: start()
        case .pause: pause()
        case .reset: reset()
        case .refresh(let afterWake): refresh(at: command.time.wallNow, afterWake: afterWake)
        case .prepareForSleep: prepareForSleep()
        case .resumeAfterSleep: resumeAfterSleep(at: command.time.wallNow)
        case .undoPresetChange: accepted = undoPresetChange(at: command.time.wallNow)
        }
        let after = sessionSnapshot
        var events: [TimerSessionEvent] = []
        if !before.isRunning && after.isRunning { events.append(.started) }
        if before.isRunning && after.isPaused { events.append(.paused) }
        if !before.isComplete && after.isComplete { events.append(.completed) }
        if before.phase != after.phase { events.append(.phaseChanged(from: before.phase, to: after.phase)) }
        if case .reset = command.action { events.append(.reset) }
        return TimerSessionUpdate(snapshot: after, events: events, accepted: accepted)
    }

    func selectPreset(_ index: Int) {
        selectPreset(index, recordsUndo: true)
    }

    private func selectPreset(_ index: Int, recordsUndo: Bool) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        if recordsUndo { preparePresetUndo() }
        if presetBecomesOneOff(index) && suspendedPomodoro == nil {
            suspendedPomodoro = frozenPomodoro()
        }
        stop()
        sessionKind = .presetCountdown
        selectedPreset = index
        defaults.set(index, forKey: "selectedPreset")
        if suspendedPomodoro != nil {
            flowEnabled = false
        } else if flowEnabled {
            if index == focusPresetIndex { phase = .focus }
            else if index == shortBreakPresetIndex { phase = .breakTime }
            else { flowEnabled = false }
        }
        total = TimeInterval(presetSeconds[index])
        remaining = total
        clearAlert()
        saveSession()
    }

    func selectAndStartPreset(_ index: Int) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        selectPreset(index)
        start(preservingPresetUndo: true)
    }

    func selectAndStartCubeFace(_ index: Int) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        selectAndStartPreset(index)
        if !muted { presetSound.play(volume: volume) }
    }

    @discardableResult
    func startCustomCountdown(seconds: Int) -> Bool {
        guard (TimerEngine.minimumDuration...TimerEngine.maximumDuration).contains(seconds) else {
            return false
        }
        preparePresetUndo()
        if flowEnabled && suspendedPomodoro == nil { suspendedPomodoro = frozenPomodoro() }
        stop()
        flowEnabled = false
        sessionKind = .customCountdown
        total = TimeInterval(seconds)
        remaining = total
        clearAlert()
        start(preservingPresetUndo: true)
        return true
    }

    func startStopwatch() {
        preparePresetUndo()
        if flowEnabled && suspendedPomodoro == nil { suspendedPomodoro = frozenPomodoro() }
        stop()
        flowEnabled = false
        sessionKind = .stopwatch
        total = TimeInterval(TimerEngine.maximumDuration)
        remaining = 0
        clearAlert()
        start(preservingPresetUndo: true)
    }

    func turn(_ direction: Int) {
        let count = Self.defaultDurations.count
        selectPreset(((selectedPreset + direction) % count + count) % count)
    }

    func setBorderlessWindow(_ enabled: Bool) {
        guard borderlessWindow != enabled else { return }
        NotificationCenter.default.post(name: .cubeTimerWillChangeWindowMode, object: nil)
        borderlessWindow = enabled
    }

    func setPreset(_ index: Int, seconds: Int) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        let value = TimerEngine.clampedDuration(seconds)
        guard value != presetSeconds[index] else { return }
        presetSeconds[index] = value
        defaults.set(value, forKey: "presetSeconds.\(index)")
        if sessionKind == .presetCountdown && index == selectedPreset &&
            !(flowEnabled && phase == .longBreak) &&
            !isRunning && !isPaused && !isComplete {
            total = TimeInterval(value)
            remaining = total
            saveSession()
        }
    }

    func setPresetName(_ index: Int, name: String) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let value = String(trimmed.prefix(32))
        presetNames[index] = value
        defaults.set(value, forKey: "presetName.\(index)")
    }

    func setPresetRole(_ index: Int, role: PresetRole) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        let previousRole = presetRoles[index]
        guard previousRole != role else { return }

        // Moving a semantic role must leave the old role represented somewhere
        // else. Prefer a General slot, then the role's default slot.
        func replacementSlot(for role: PresetRole) -> Int? {
            guard role != .general else { return nil }
            let preferred = role == .focus ? 2 : 0
            if preferred != index, presetRoles[preferred] == .general { return preferred }
            return presetRoles.indices.first { $0 != index && presetRoles[$0] == .general }
        }

        if previousRole != .general, let replacement = replacementSlot(for: previousRole) {
            presetRoles[replacement] = previousRole
            defaults.set(previousRole.rawValue, forKey: "presetRole.\(replacement)")
        }
        if role != .general, let other = presetRoles.firstIndex(of: role), other != index {
            presetRoles[other] = .general
            defaults.set(PresetRole.general.rawValue, forKey: "presetRole.\(other)")
        }
        presetRoles[index] = role
        defaults.set(role.rawValue, forKey: "presetRole.\(index)")
    }

    func savePreset(_ index: Int, seconds: Int, name: String) {
        guard (TimerEngine.minimumDuration...TimerEngine.maximumDuration).contains(seconds),
              Self.defaultDurations.indices.contains(index) else { return }
        setPresetName(index, name: name)
        setPreset(index, seconds: seconds)
    }

    func resetPreset(_ index: Int) {
        guard Self.defaultDurations.indices.contains(index) else { return }
        setPreset(index, seconds: Self.defaultDurations[index])
        setPresetName(index, name: Self.defaultPresetNames[index])
        setPresetRole(index, role: Self.defaultRole(for: index))
    }

    func resetPresetSettings() {
        for index in Self.defaultDurations.indices {
            setPreset(index, seconds: Self.defaultDurations[index])
            setPresetName(index, name: Self.defaultPresetNames[index])
            presetRoles[index] = Self.defaultRole(for: index)
            defaults.set(presetRoles[index].rawValue, forKey: "presetRole.\(index)")
        }
        setLongBreak(seconds: 900)
        setCycleTarget(4)
    }

    func setLongBreak(seconds: Int) {
        let value = TimerEngine.clampedDuration(seconds)
        guard value != longBreakSeconds else { return }
        longBreakSeconds = value
        defaults.set(value, forKey: "longBreakSeconds")
        if flowEnabled && phase == .longBreak && !isRunning && !isPaused && !isComplete {
            total = TimeInterval(value)
            remaining = total
            saveSession()
        }
    }

    /// Recheck this when a row action is chosen: the running timer may have
    /// crossed the proposed duration while Settings was open.
    func immediateDurationAction(for setting: DurationSetting,
                                 seconds: Int) -> DurationImmediateAction? {
        guard isRunning || isPaused, durationSettingIsCurrent(setting) else { return nil }
        let now = currentContinuousNow
        if isRunning, (continuousDeadline ?? 0) <= now { return nil }
        let elapsed = elapsedForDurationEdit(at: now)
        return TimeInterval(TimerEngine.clampedDuration(seconds)) > elapsed
            ? .applyNow : .restartThisPhase
    }

    @discardableResult
    func editDuration(_ setting: DurationSetting, seconds: Int,
                      action: DurationEditAction) -> Bool {
        guard durationSettingIsValid(setting) else { return false }
        let value = TimerEngine.clampedDuration(seconds)
        if case .useNextTime = action {
            saveDurationPreference(setting, seconds: value)
            return true
        }
        guard isRunning || isPaused, durationSettingIsCurrent(setting) else { return false }
        let now = currentContinuousNow
        if isRunning, (continuousDeadline ?? 0) <= now { return false }
        let elapsed = elapsedForDurationEdit(at: now)
        let restarts = TimeInterval(value) <= elapsed
        switch action {
        case .applyNow where restarts, .restartThisPhase where !restarts:
            return false
        case .useNextTime:
            return false
        default:
            break
        }

        saveDurationPreference(setting, seconds: value)
        total = TimeInterval(value)
        remaining = restarts ? total : total - elapsed
        if isRunning {
            continuousDeadline = now + remaining
            deadline = currentWallNow.addingTimeInterval(remaining)
        }
        // A settings edit must not call completion or advance Auto-Cycle.
        notifications?.cancel()
        saveSession()
        if isRunning { scheduleCurrentNotification() }
        return true
    }

    private func durationSettingIsValid(_ setting: DurationSetting) -> Bool {
        switch setting {
        case .preset(let index): Self.defaultDurations.indices.contains(index)
        case .longBreak: true
        }
    }

    private func durationSettingIsCurrent(_ setting: DurationSetting) -> Bool {
        guard sessionKind == .presetCountdown else { return false }
        switch setting {
        case .preset(let index):
            return index == selectedPreset && !(flowEnabled && phase == .longBreak)
        case .longBreak:
            return flowEnabled && phase == .longBreak
        }
    }

    private func elapsedForDurationEdit(at continuousNow: TimeInterval) -> TimeInterval {
        let currentRemaining = isRunning
            ? max(0, (continuousDeadline ?? continuousNow) - continuousNow)
            : remaining
        return min(total, max(0, total - currentRemaining))
    }

    private func saveDurationPreference(_ setting: DurationSetting, seconds: Int) {
        switch setting {
        case .preset(let index): setPreset(index, seconds: seconds)
        case .longBreak: setLongBreak(seconds: seconds)
        }
    }

    func setCycleTarget(_ target: Int) {
        let value = min(8, max(2, target))
        guard value != requestedCycleTarget else { return }
        requestedCycleTarget = value
        defaults.set(value, forKey: "focusesBeforeLongBreak")
        // Preserve an underway cycle, including a long break whose marks have
        // already been cleared. A new cycle can adopt the choice immediately.
        if focusesInCycle == 0 && phase != .longBreak &&
            suspendedPomodoro?.phase != .longBreak {
            cycleTarget = value
        }
        saveSession()
    }

    private func finishLongBreakCycle() {
        focusesInCycle = 0
        cycleTarget = requestedCycleTarget
    }

    private func duration(for phase: SessionPhase) -> TimeInterval {
        phase == .longBreak ? TimeInterval(longBreakSeconds) :
            TimeInterval(presetSeconds[presetIndex(for: phase)])
    }

    private func recordFocusCompletionIfNeeded() {
        guard flowEnabled && phase == .focus else { return }
        completedFocusTotal += 1
        focusesInCycle = min(cycleTarget, focusesInCycle + 1)
    }

    private func frozenPomodoro() -> SuspendedPomodoroSession {
        let state: SavedTimerSession.State = isRunning ? .running : isPaused ? .paused :
            isComplete ? .completed : .ready
        let frozenRemaining: TimeInterval
        if isRunning, let continuousDeadline {
            frozenRemaining = max(0, continuousDeadline - currentContinuousNow)
        } else {
            frozenRemaining = remaining
        }
        return SuspendedPomodoroSession(state: state, phase: phase, total: total,
                                         remaining: min(total, frozenRemaining))
    }

    private func applyModeChange(_ enabled: Bool) {
        if !enabled && suspendedPomodoro != nil {
            prepareModeUndo()
        } else {
            clearPresetUndo()
        }
        stop()
        sessionKind = .presetCountdown
        pendingFlowEnabled = nil
        pomodoroModeEnabled = enabled
        defaults.set(enabled, forKey: "flowEnabled")
        flowEnabled = enabled
        if enabled {
            suspendedPomodoro = nil
            phase = longBreakDue ? .longBreak : .focus
            selectedPreset = presetIndex(for: phase)
            defaults.set(selectedPreset, forKey: "selectedPreset")
        } else {
            suspendedPomodoro = nil
        }
        total = flowEnabled ? duration(for: phase) : TimeInterval(presetSeconds[selectedPreset])
        remaining = total
        saveSession()
        if !enabled && undoPresetLabel != nil { showAlert("Pomodoro ended · Undo available") }
    }

    func setFlowEnabled(_ enabled: Bool) {
        guard enabled != requestedFlowEnabled else { return }
        if enabled == pomodoroModeEnabled {
            pendingFlowEnabled = nil
            saveSession()
        } else if isRunning || isPaused {
            pendingFlowEnabled = enabled
            saveSession()
        } else {
            applyModeChange(enabled)
        }
    }

    @discardableResult
    func resumePomodoro() -> Bool {
        guard let suspended = suspendedPomodoro else { return false }
        preparePresetUndo()
        stop()
        sessionKind = .presetCountdown
        suspendedPomodoro = nil
        pendingFlowEnabled = nil
        pomodoroModeEnabled = true
        defaults.set(true, forKey: "flowEnabled")
        flowEnabled = true
        phase = suspended.phase
        selectedPreset = presetIndex(for: phase)
        defaults.set(selectedPreset, forKey: "selectedPreset")
        total = suspended.total
        remaining = suspended.remaining
        switch suspended.state {
        case .running:
            deadline = currentWallNow.addingTimeInterval(remaining)
            continuousDeadline = currentContinuousNow + remaining
            isRunning = true
            scheduleCurrentNotification()
        case .paused:
            isPaused = true
        case .completed:
            isComplete = true
        case .ready:
            break
        }
        saveSession()
        showAlert("Pomodoro \(phase.displayName) restored")
        announce("Pomodoro \(phase.displayName) restored. \(TimerEngine.spokenDuration(remaining)) remaining.")
        return true
    }

    func startOrPause() {
        if isRunning { pause() }
        else { start() }
    }

    func startNextPhase() {
        guard nextPhaseName != nil else { return }
        start()
    }

    func skipBreak() {
        guard canSkipBreak else { return }
        clearPresetUndo()
        stop()
        sessionKind = .presetCountdown
        if phase == .longBreak || longBreakDue { finishLongBreakCycle() }
        phase = .focus
        selectedPreset = focusPresetIndex
        defaults.set(selectedPreset, forKey: "selectedPreset")
        total = TimeInterval(presetSeconds[selectedPreset])
        remaining = total
        saveSession()
        showAlert("Break skipped · Focus ready")
        announce("Break skipped. Focus ready. Press Start.")
    }

    func start() {
        start(preservingPresetUndo: false)
    }

    private func start(preservingPresetUndo: Bool) {
        guard !isRunning else { return }
        if !preservingPresetUndo { clearPresetUndo() }
        let wasPaused = isPaused
        let wasComplete = isComplete
        if sessionKind == .stopwatch {
            if isComplete { remaining = 0 }
        } else if isComplete {
            if flowEnabled {
                phase = upcomingPhase
                selectedPreset = presetIndex(for: phase)
                defaults.set(selectedPreset, forKey: "selectedPreset")
            }
            total = flowEnabled ? duration(for: phase) :
                sessionKind == .customCountdown ? total : TimeInterval(presetSeconds[selectedPreset])
            remaining = total
        } else if remaining <= 0 {
            total = flowEnabled ? duration(for: phase) :
                sessionKind == .customCountdown ? total : TimeInterval(presetSeconds[selectedPreset])
            remaining = total
        }
        if flowEnabled && phase == .longBreak && longBreakDue { focusesInCycle = 0 }
        let timeToLimit = sessionKind == .stopwatch ? total - remaining : remaining
        deadline = currentWallNow.addingTimeInterval(timeToLimit)
        continuousDeadline = currentContinuousNow + timeToLimit
        isRunning = true
        isPaused = false
        isComplete = false
        clearAlert()
        saveSession()
        scheduleCurrentNotification()
        if wasPaused {
            announce(sessionKind == .stopwatch ? "Stopwatch resumed." :
                     "Resumed. \(TimerEngine.spokenDuration(remaining)) remaining.")
        } else if wasComplete && flowEnabled {
            announce("\(phase.displayName) session started. \(TimerEngine.spokenDuration(remaining)) remaining.")
        } else if sessionKind == .stopwatch {
            announce("Stopwatch started.")
        } else if sessionKind == .customCountdown {
            announce("Countdown started. \(TimerEngine.spokenDuration(remaining)) remaining.")
        } else {
            announce("\(presetNames[selectedPreset]) started. \(TimerEngine.spokenDuration(remaining)) remaining.")
        }
    }

    func pause() {
        guard isRunning else { return }
        clearPresetUndo()
        if let continuousDeadline {
            let timeToLimit = max(0, continuousDeadline - currentContinuousNow)
            remaining = sessionKind == .stopwatch ? total - timeToLimit : timeToLimit
        }
        if (sessionKind == .stopwatch ? remaining >= total : remaining == 0) {
            refresh()
            return
        }
        deadline = nil
        continuousDeadline = nil
        isRunning = false
        isPaused = true
        saveSession()
        notifications?.cancel()
        announce(sessionKind == .stopwatch ?
                 "Stopwatch paused at \(TimerEngine.stopwatchDisplay(remaining))." :
                 "Paused. \(TimerEngine.spokenDuration(remaining)) remaining.")
    }

    func reset() {
        clearPresetUndo()
        stop()
        if let pendingFlowEnabled {
            applyModeChange(pendingFlowEnabled)
            announce("Timer reset. \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready.")
            return
        }
        total = flowEnabled ? duration(for: phase) : sessionKind == .customCountdown ? total :
            sessionKind == .stopwatch ? TimeInterval(TimerEngine.maximumDuration) :
            TimeInterval(presetSeconds[selectedPreset])
        remaining = sessionKind == .stopwatch ? 0 : total
        clearAlert()
        saveSession()
        announce(sessionKind == .stopwatch ? "Stopwatch reset." :
                 "Timer reset. \(TimerEngine.spokenDuration(remaining)) ready.")
    }

    private var currentWallNow: Date { commandTime?.wall ?? timeSource.wallNow }
    private var currentContinuousNow: TimeInterval {
        commandTime?.continuous ?? timeSource.continuousNow
    }

    private func clockValues(at testingWallNow: Date?) -> (wall: Date, continuous: TimeInterval) {
        if let commandTime {
            return (testingWallNow ?? commandTime.wall, commandTime.continuous)
        }
        let wall = timeSource.wallNow
        let continuous = timeSource.continuousNow
        guard let testingWallNow else { return (wall, continuous) }
        // Existing deterministic tests advance time through the wall-date argument.
        return (testingWallNow,
                testOriginContinuous + testingWallNow.timeIntervalSince(testOriginWall))
    }

    func refresh(at now: Date? = nil, afterWake: Bool = false) {
        let current = clockValues(at: now)
        activateDeferredModeUndoIfNeeded(at: current.continuous)
        expirePresetUndo(at: current.continuous)
        guard isRunning, let continuousDeadline else { return }
        if sessionKind == .stopwatch {
            remaining = min(total, max(0, total - (continuousDeadline - current.continuous)))
            if remaining >= total {
                deadline = nil
                self.continuousDeadline = nil
                isRunning = false
                isComplete = true
                notifications?.cancel()
                if let pendingFlowEnabled {
                    applyModeChange(pendingFlowEnabled)
                    showAlert("Stopwatch stopped at 99:59")
                } else {
                    saveSession()
                }
                announce("Stopwatch stopped at 99:59.")
            } else if let deadline,
                      abs(deadline.timeIntervalSince(current.wall) - (total - remaining)) > 1 {
                self.deadline = current.wall.addingTimeInterval(total - remaining)
                saveSession()
            }
            return
        }
        remaining = max(0, continuousDeadline - current.continuous)
        if remaining == 0 {
            complete(expiredDeadline: continuousDeadline, at: current,
                     afterWake: afterWake || wasSleeping)
        } else if let deadline,
                  abs(deadline.timeIntervalSince(current.wall) - remaining) > 1 {
            // A manual/NTP clock jump must not change elapsed timer time. Keep the
            // wall deadline useful as a fallback after the next Mac reboot.
            self.deadline = current.wall.addingTimeInterval(remaining)
            saveSession()
        }
    }

    func prepareForSleep() {
        wasSleeping = true
        if isRunning { notifications?.cancel() }
    }

    func resumeAfterSleep(at now: Date? = nil) {
        refresh(at: now, afterWake: true)
        wasSleeping = false
        scheduleCurrentNotification(at: clockValues(at: now).continuous)
    }

    private func scheduleCurrentNotification(at continuousNow: TimeInterval? = nil) {
        guard sessionKind != .stopwatch, !wasSleeping, isRunning,
              let continuousDeadline else { return }
        let timeLeft = max(0, continuousDeadline - (continuousNow ?? currentContinuousNow))
        guard timeLeft > 0 else { return }
        notifications?.schedule(after: timeLeft, title: notificationTitle,
                                playSound: !muted)
    }

    private func playCompletionSound(forceInApp: Bool = false) {
        guard !muted else { return }
        if forceInApp || appIsActive() || notifications == nil {
            sound.play(volume: volume)
            return
        }
        guard let notifications else { return }
        Task { [weak self] in
            let available = await notifications.canDeliverSound()
            guard let self, !available, !self.muted else { return }
            self.sound.play(volume: self.volume)
        }
    }

    private func announce(_ message: String) {
        guard appIsActive() else { return }
        accessibilityAnnouncer.announce(message)
    }

    private var notificationTitle: String {
        flowEnabled ? "\(phase.displayName) session complete" : "Timer complete"
    }

    private func complete(expiredDeadline: TimeInterval,
                          at now: (wall: Date, continuous: TimeInterval), afterWake: Bool) {
        clearPresetUndo()
        let completedPhase = phase
        recordFocusCompletionIfNeeded()
        if completedPhase == .longBreak { finishLongBreakCycle() }
        if let pendingFlowEnabled {
            deadline = nil
            continuousDeadline = nil
            isRunning = false
            isPaused = false
            isComplete = true
            remaining = 0
            applyModeChange(pendingFlowEnabled)
            showAlert("\(completedPhase.displayName) complete · \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready")
            if !afterWake && now.continuous - expiredDeadline <= 2 {
                playCompletionSound()
            }
            announce("Timer complete. \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready. Press Start.")
            return
        }
        if flowEnabled {
            let missed = afterWake || now.continuous - expiredDeadline > 2
            let nextPhase = upcomingPhase
            let nextPreset = presetIndex(for: nextPhase)
            let nextDuration = duration(for: nextPhase)
            if autoStartNextPhase && !missed && now.continuous < expiredDeadline + nextDuration {
                phase = nextPhase
                if nextPhase == .longBreak { focusesInCycle = 0 }
                selectedPreset = nextPreset
                defaults.set(selectedPreset, forKey: "selectedPreset")
                total = nextDuration
                continuousDeadline = expiredDeadline + nextDuration
                remaining = max(0, expiredDeadline + nextDuration - now.continuous)
                deadline = now.wall.addingTimeInterval(remaining)
                isRunning = true
                isPaused = false
                isComplete = false
                showAlert("\(completedPhase.displayName) complete")
                playCompletionSound()
                announce("\(completedPhase.displayName) complete. \(phase.displayName) running. \(TimerEngine.spokenDuration(remaining)) remaining.")
                saveSession()
                scheduleCurrentNotification(at: now.continuous)
            } else {
                deadline = nil
                continuousDeadline = nil
                isRunning = false
                isPaused = false
                isComplete = true
                remaining = 0
                notifications?.cancel()
                showAlert(missed
                    ? "\(completedPhase.displayName) elapsed while away · Start \(nextPhase.displayName)"
                    : "\(completedPhase.displayName) complete · Start \(nextPhase.displayName)")
                if !missed { playCompletionSound() }
                announce("\(completedPhase.displayName) complete. Start \(nextPhase.displayName) when ready.")
                saveSession()
            }
        } else {
            deadline = nil
            continuousDeadline = nil
            isRunning = false
            isPaused = false
            isComplete = true
            remaining = 0
            showAlert("Time is up")
            playCompletionSound(forceInApp: afterWake)
            announce("Timer complete.")
            saveSession()
        }
    }

    private func preparePresetUndo() {
        let now = currentContinuousNow
        let previous: SavedTimerSession
        if isRunning || isPaused {
            previous = snapshotSession()
        } else if let pending = presetUndo, now < pending.continuousExpiresAt {
            // A select-only button may leave the new preset idle. Keep the
            // displaced session available if another preset is selected.
            previous = pending.session
        } else {
            clearPresetUndo()
            return
        }
        installUndo(previous, at: now)
    }

    private func prepareModeUndo() {
        var previous = snapshotSession()
        previous.pendingFlowEnabled = nil
        installUndo(previous, at: currentContinuousNow, label: "Pomodoro",
                    deferUntilActive: true)
    }

    private func snapshotSession() -> SavedTimerSession {
        let state: SavedTimerSession.State = isRunning ? .running : isPaused ? .paused :
            isComplete ? .completed : .ready
        return SavedTimerSession(version: 7, state: state,
                                 selectedPreset: selectedPreset, phase: phase, total: total,
                                 deadline: isRunning ? deadline : nil,
                                 pausedRemaining: isPaused ? remaining : nil,
                                 bootSessionID: isRunning ? timeSource.bootSessionID : nil,
                                 continuousDeadline: isRunning ? continuousDeadline : nil,
                                 activeFlowEnabled: flowEnabled,
                                 pomodoroModeEnabled: pomodoroModeEnabled,
                                 pendingFlowEnabled: pendingFlowEnabled,
                                 suspendedPomodoro: suspendedPomodoro,
                                 focusesInCycle: focusesInCycle,
                                 completedFocusTotal: completedFocusTotal,
                                 cycleTarget: cycleTarget,
                                 sessionKind: sessionKind)
    }

    private func installUndo(_ previous: SavedTimerSession, at now: TimeInterval,
                             label: String? = nil, deferUntilActive: Bool = false) {
        let undo = PresetUndo(session: previous,
                              flowEnabled: previous.activeFlowEnabled ?? flowEnabled,
                              modeEnabled: previous.pomodoroModeEnabled ?? pomodoroModeEnabled,
                              pendingFlowEnabled: previous.pendingFlowEnabled,
                              suspendedPomodoro: previous.suspendedPomodoro,
                              continuousExpiresAt: deferUntilActive && !appIsActive()
                                  ? .infinity : now + 6, id: UUID())
        presetUndo = undo
        undoPresetLabel = label ?? (previous.sessionKind == .stopwatch ? "Stopwatch" :
            previous.sessionKind == .customCountdown ? "Countdown" :
            TimerEngine.display(previous.total))
        undoExpiryTask?.cancel()
        if undo.continuousExpiresAt.isFinite { scheduleUndoExpiry(for: undo) }
    }

    private func scheduleUndoExpiry(for undo: PresetUndo) {
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, self?.presetUndo?.id == undo.id else { return }
            self?.clearPresetUndo()
        }
    }

    private func activateDeferredModeUndoIfNeeded(at now: TimeInterval) {
        guard appIsActive(), let previous = presetUndo,
              previous.continuousExpiresAt == .infinity else { return }
        let active = PresetUndo(session: previous.session, flowEnabled: previous.flowEnabled,
                                modeEnabled: previous.modeEnabled,
                                pendingFlowEnabled: previous.pendingFlowEnabled,
                                suspendedPomodoro: previous.suspendedPomodoro,
                                continuousExpiresAt: now + 6, id: previous.id)
        presetUndo = active
        scheduleUndoExpiry(for: active)
    }

    @discardableResult
    func undoPresetChange(at now: Date? = nil) -> Bool {
        let current = clockValues(at: now)
        guard let undo = presetUndo else { return false }
        guard current.continuous < undo.continuousExpiresAt else {
            clearPresetUndo()
            return false
        }
        clearPresetUndo()
        stop()
        clearAlert()
        flowEnabled = undo.flowEnabled
        cycleTarget = undo.session.cycleTarget ?? 4
        focusesInCycle = undo.session.focusesInCycle ?? 0
        completedFocusTotal = undo.session.completedFocusTotal ?? 0
        pomodoroModeEnabled = undo.modeEnabled
        pendingFlowEnabled = undo.pendingFlowEnabled
        suspendedPomodoro = undo.suspendedPomodoro
        defaults.set(pomodoroModeEnabled, forKey: "flowEnabled")
        selectedPreset = undo.session.selectedPreset
        defaults.set(selectedPreset, forKey: "selectedPreset")
        phase = undo.session.phase
        sessionKind = undo.session.sessionKind ?? .presetCountdown
        total = undo.session.total

        switch undo.session.state {
        case .ready:
            remaining = sessionKind == .stopwatch ? 0 : total
            saveSession()
            showAlert("Timer restored")
        case .paused:
            remaining = undo.session.pausedRemaining ?? total
            isPaused = true
            saveSession()
            showAlert("Paused timer restored")
            announce("Paused timer restored. \(TimerEngine.spokenDuration(remaining)) remaining.")
        case .running:
            guard let originalDeadline = undo.session.deadline else { return false }
            let originalContinuous = undo.session.continuousDeadline ??
                current.continuous + originalDeadline.timeIntervalSince(current.wall)
            let timeLeft = max(0, originalContinuous - current.continuous)
            if timeLeft > 0 {
                deadline = abs(originalDeadline.timeIntervalSince(current.wall) - timeLeft) <= 1
                    ? originalDeadline : current.wall.addingTimeInterval(timeLeft)
                continuousDeadline = originalContinuous
                remaining = sessionKind == .stopwatch ? total - min(total, timeLeft) :
                    min(total, timeLeft)
                isRunning = true
                saveSession()
                scheduleCurrentNotification(at: current.continuous)
                showAlert("Timer restored")
                announce(sessionKind == .stopwatch ? "Stopwatch restored." :
                         "Timer restored. \(TimerEngine.spokenDuration(remaining)) remaining.")
            } else if sessionKind == .stopwatch {
                remaining = total
                isComplete = true
                saveSession()
                showAlert("Stopwatch restored · Stopped at 99:59")
            } else if let pendingFlowEnabled {
                applyModeChange(pendingFlowEnabled)
                showAlert("Timer restored · \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready")
            } else if flowEnabled {
                remaining = 0
                isComplete = true
                recordFocusCompletionIfNeeded()
                if phase == .longBreak { finishLongBreakCycle() }
                saveSession()
                showAlert("Timer restored · \(phase.displayName) complete")
                announce("Timer restored. \(phase.displayName) complete. Start the next phase when ready.")
            } else {
                remaining = 0
                isComplete = true
                saveSession()
                showAlert("Timer restored · Time is up")
                announce("Timer restored. Timer complete.")
            }
        case .completed:
            remaining = sessionKind == .stopwatch ? total : 0
            isComplete = true
            saveSession()
            showAlert("Completed timer restored")
        }
        return true
    }

    private func expirePresetUndo(at now: TimeInterval) {
        if let presetUndo, now >= presetUndo.continuousExpiresAt { clearPresetUndo() }
    }

    private func clearPresetUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        presetUndo = nil
        undoPresetLabel = nil
    }

    private func stop() {
        deadline = nil
        continuousDeadline = nil
        isRunning = false
        isPaused = false
        isComplete = false
        sessionPersistence.clear()
        notifications?.cancel()
    }

    private func saveSession() {
        if sessionKind == .presetCountdown && !isRunning && !isPaused && !isComplete && !flowEnabled &&
            suspendedPomodoro == nil && pendingFlowEnabled == nil &&
            completedFocusTotal == 0 && focusesInCycle == 0 {
            sessionPersistence.clear()
            return
        }
        sessionPersistence.save(snapshotSession())
    }

    private func restoreSession(at now: Date) {
        guard let saved = sessionPersistence.load(defaultFlowEnabled: flowEnabled,
                                                 defaultPomodoroModeEnabled: pomodoroModeEnabled)
        else { return }
        flowEnabled = saved.activeFlowEnabled ?? flowEnabled
        cycleTarget = saved.cycleTarget ?? 4
        focusesInCycle = saved.focusesInCycle ?? 0
        completedFocusTotal = saved.completedFocusTotal ?? 0
        pomodoroModeEnabled = saved.pomodoroModeEnabled ?? pomodoroModeEnabled
        pendingFlowEnabled = saved.pendingFlowEnabled
        suspendedPomodoro = saved.suspendedPomodoro
        sessionKind = saved.sessionKind ?? .presetCountdown
        defaults.set(pomodoroModeEnabled, forKey: "flowEnabled")
        switch saved.state {
        case .running:
            guard let savedDeadline = saved.deadline,
                  savedDeadline.timeIntervalSince1970.isFinite else {
                sessionPersistence.clear()
                return
            }
            let sameBoot = saved.version >= 2 && saved.bootSessionID != nil &&
                saved.bootSessionID == timeSource.bootSessionID
            let savedContinuous = saved.continuousDeadline
            let timeLeft: TimeInterval
            if sameBoot, let savedContinuous, savedContinuous.isFinite,
               savedContinuous >= 0 {
                timeLeft = max(0, savedContinuous - currentContinuousNow)
            } else {
                timeLeft = TimerEngine.remaining(until: savedDeadline, at: now)
            }
            phase = saved.phase
            selectedPreset = restoredPresetIndex(for: phase, savedIndex: saved.selectedPreset)
            total = saved.total
            if timeLeft > 0 {
                remaining = sessionKind == .stopwatch ? total - min(total, timeLeft) :
                    min(total, timeLeft)
                deadline = now.addingTimeInterval(timeLeft)
                continuousDeadline = testOriginContinuous + timeLeft
                isRunning = true
                saveSession()
                scheduleCurrentNotification()
            } else {
                remaining = sessionKind == .stopwatch ? total : 0
                isComplete = true
                if sessionKind != .stopwatch { recordFocusCompletionIfNeeded() }
                if phase == .longBreak { finishLongBreakCycle() }
                if let pendingFlowEnabled {
                    applyModeChange(pendingFlowEnabled)
                    showAlert("Timer complete · \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready")
                } else {
                    saveSession()
                    showAlert(sessionKind == .stopwatch ? "Stopwatch stopped at 99:59" :
                              flowEnabled ? "\(phase.displayName) complete" : "Time is up")
                }
            }
        case .paused:
            guard let paused = saved.pausedRemaining, paused.isFinite,
                  paused >= (sessionKind == .stopwatch ? 0 : 1), paused <= saved.total else {
                sessionPersistence.clear()
                return
            }
            phase = saved.phase
            selectedPreset = restoredPresetIndex(for: phase, savedIndex: saved.selectedPreset)
            total = saved.total
            remaining = paused
            isPaused = true
            saveSession()
        case .completed:
            phase = saved.phase
            selectedPreset = restoredPresetIndex(for: phase, savedIndex: saved.selectedPreset)
            total = saved.total
            remaining = sessionKind == .stopwatch ? total : 0
            isComplete = true
            saveSession()
        case .ready:
            phase = saved.phase
            selectedPreset = restoredPresetIndex(for: phase, savedIndex: saved.selectedPreset)
            total = saved.total
            remaining = sessionKind == .stopwatch ? 0 : total
            saveSession()
        }
        defaults.set(selectedPreset, forKey: "selectedPreset")
    }

    private func showAlert(_ text: String) {
        alertClearTask?.cancel()
        alertText = text
        alertClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.alertText = nil
        }
    }

    private func clearAlert() {
        alertClearTask?.cancel()
        alertText = nil
    }
}

private final class CompletionNotifications: NSObject, UNUserNotificationCenterDelegate,
                                             CompletionNotificationClient {
    static let shared = CompletionNotifications()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "cube-timer-completion"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func schedule(after seconds: TimeInterval, title: String, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Pomodoro Float is ready for the next step."
        // Foreground delivery omits .sound in willPresent; the app plays its
        // volume-adjusted copy. Background delivery uses the bundled CAF.
        content.sound = playSound
            ? UNNotificationSound(named: UNNotificationSoundName(rawValue: CompletionAudio.notificationFile))
            : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func canDeliverSound() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let permitted = settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
                continuation.resume(returning: permitted && settings.soundSetting == .enabled)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}


private final class PresetSound: PresetSoundClient {
    private var player: AVAudioPlayer?

    func play(volume: Double) {
        if player == nil {
            guard let url = PresetAudio.playbackURL() else {
                NSLog("Pomodoro Float preset audio is missing from the app bundle")
                return
            }
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = 0
                player?.prepareToPlay()
            } catch {
                NSLog("Pomodoro Float could not load its preset audio: %@", String(describing: error))
                return
            }
        }
        guard let player else { return }
        player.stop()
        player.currentTime = 0
        player.volume = Float(max(0, min(1, volume)))
        if !player.play() {
            NSLog("Pomodoro Float could not start its preset audio")
        }
    }
}

private final class CompletionSound: CompletionSoundClient {
    private var player: AVAudioPlayer?

    func play(volume: Double) {
        guard let url = CompletionAudio.playbackURL() else {
            NSLog("Pomodoro Float completion audio is missing from the app bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(max(0, min(1, volume)))
            player.numberOfLoops = 0
            player.prepareToPlay()
            self.player = player
            if !player.play() {
                NSLog("Pomodoro Float could not start its completion audio")
            }
        } catch {
            NSLog("Pomodoro Float could not play its completion audio: %@", String(describing: error))
        }
    }
}

@MainActor
private final class SystemTimerAccessibilityAnnouncer: TimerAccessibilityAnnouncementClient {
    func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
