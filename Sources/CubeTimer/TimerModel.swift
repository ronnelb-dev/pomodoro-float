import AppKit
import AVFoundation
import Combine
import Foundation
import UserNotifications
import Darwin

protocol TimerTimeSource {
    var wallNow: Date { get }
    var continuousNow: TimeInterval { get }
    var bootSessionID: String? { get }
}

private struct SystemTimerTimeSource: TimerTimeSource {
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

enum SessionPhase: String, Codable {
    case focus = "FOCUS"
    case breakTime = "BREAK"
    case longBreak = "LONG BREAK"

    var presetIndex: Int { self == .focus ? 2 : 0 }
    var isBreak: Bool { self != .focus }
    var displayName: String {
        switch self {
        case .focus: "Focus"
        case .breakTime: "Short Break"
        case .longBreak: "Long Break"
        }
    }
    var displayLabel: String { displayName.uppercased() }
}

extension Notification.Name {
    static let cubeTimerWillChangeWindowMode = Notification.Name("CubeTimerWillChangeWindowMode")
}

protocol CompletionNotificationClient: AnyObject {
    func requestPermission()
    func schedule(after seconds: TimeInterval, title: String, playSound: Bool)
    func cancel()
    func canDeliverSound() async -> Bool
}

protocol CompletionSoundClient: AnyObject {
    func play(volume: Double)
}

protocol PresetSoundClient: AnyObject {
    func play(volume: Double)
}

@MainActor
protocol TimerAccessibilityAnnouncementClient: AnyObject {
    func announce(_ message: String)
}

struct SavedTimerSession: Codable {
    enum State: String, Codable { case ready, running, paused, completed }

    static let key = "timerSession.v1"
    let version: Int
    let state: State
    let selectedPreset: Int
    let phase: SessionPhase
    let total: TimeInterval
    let deadline: Date?
    let pausedRemaining: TimeInterval?
    var bootSessionID: String? = nil
    var continuousDeadline: TimeInterval? = nil
    var activeFlowEnabled: Bool? = nil
    var pomodoroModeEnabled: Bool? = nil
    var pendingFlowEnabled: Bool? = nil
    var suspendedPomodoro: SuspendedPomodoroSession? = nil
    var focusesInCycle: Int? = nil
    var completedFocusTotal: Int? = nil
    var cycleTarget: Int? = nil
}

struct SuspendedPomodoroSession: Codable {
    let state: SavedTimerSession.State
    let phase: SessionPhase
    let total: TimeInterval
    let remaining: TimeInterval
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

@MainActor
final class TimerModel: ObservableObject {
    static let presetNames = ["5 MIN", "10 MIN", "25 MIN", "50 MIN", "60 MIN"]
    static let defaultDurations = [300, 600, 1500, 3000, 3600]
    static func spokenPresetName(_ index: Int) -> String {
        "\(defaultDurations[index] / 60)-minute preset"
    }

    @Published private(set) var presetSeconds: [Int]
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

    var progress: Double { TimerEngine.progress(remaining: remaining, total: total) }
    var timeLabel: String { TimerEngine.display(remaining) }
    var requestedFlowEnabled: Bool { pendingFlowEnabled ?? pomodoroModeEnabled }
    var hasSuspendedPomodoro: Bool { suspendedPomodoro != nil }
    var longBreakDue: Bool { focusesInCycle >= cycleTarget }
    var focusProgressLabel: String { "\(focusesInCycle)/\(cycleTarget)" }
    var cycleTargetChangePending: Bool { cycleTarget != requestedCycleTarget }
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
        flowEnabled && (![0, 2].contains(index) || longBreakDue || phase == .longBreak)
    }
    var pendingModeDescription: String? {
        guard let pendingFlowEnabled else { return nil }
        return "Pomodoro will turn \(pendingFlowEnabled ? "on" : "off") when this timer finishes"
    }
    var accessibilityValue: String {
        let state = isComplete ? "Complete" : isRunning ? "Running" : isPaused ? "Paused" : "Ready"
        let session = flowEnabled
            ? "\(phase.displayName) session, \(phase == .longBreak ? TimerEngine.spokenDuration(total) : Self.spokenPresetName(selectedPreset))"
            : "\(Self.spokenPresetName(selectedPreset))\(hasSuspendedPomodoro ? ", Pomodoro paused" : "")"
        let count = pomodoroModeEnabled
            ? ", \(focusesInCycle) of \(cycleTarget) focuses toward long break, \(completedFocusTotal) completed focuses total"
            : ""
        return "\(session), \(state), \(TimerEngine.spokenDuration(remaining)) remaining\(count)"
    }
    private let defaults: UserDefaults
    private let timeSource: TimerTimeSource
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
        let loadedFlow = defaults.bool(forKey: "flowEnabled")
        let loadedSelection = loadedFlow ? 2 : min(Self.defaultDurations.count - 1,
                                                   max(0, defaults.integer(forKey: "selectedPreset")))
        presetSeconds = loadedPresets
        longBreakSeconds = defaults.object(forKey: "longBreakSeconds") == nil
            ? 900 : TimerEngine.clampedDuration(defaults.integer(forKey: "longBreakSeconds"))
        let loadedCycleTarget = defaults.object(forKey: "focusesBeforeLongBreak") == nil
            ? 4 : min(8, max(2, defaults.integer(forKey: "focusesBeforeLongBreak")))
        cycleTarget = loadedCycleTarget
        requestedCycleTarget = loadedCycleTarget
        selectedPreset = loadedSelection
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
        selectedPreset = index
        defaults.set(index, forKey: "selectedPreset")
        if suspendedPomodoro != nil {
            flowEnabled = false
        } else if flowEnabled {
            if index == 2 { phase = .focus }
            else if index == 0 { phase = .breakTime }
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
        if index == selectedPreset && !(flowEnabled && phase == .longBreak) &&
            !isRunning && !isPaused && !isComplete {
            total = TimeInterval(value)
            remaining = total
            saveSession()
        }
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
            TimeInterval(presetSeconds[phase.presetIndex])
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
            frozenRemaining = max(0, continuousDeadline - timeSource.continuousNow)
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
        pendingFlowEnabled = nil
        pomodoroModeEnabled = enabled
        defaults.set(enabled, forKey: "flowEnabled")
        flowEnabled = enabled
        if enabled {
            suspendedPomodoro = nil
            phase = longBreakDue ? .longBreak : .focus
            selectedPreset = phase.presetIndex
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
        suspendedPomodoro = nil
        pendingFlowEnabled = nil
        pomodoroModeEnabled = true
        defaults.set(true, forKey: "flowEnabled")
        flowEnabled = true
        phase = suspended.phase
        selectedPreset = phase.presetIndex
        defaults.set(selectedPreset, forKey: "selectedPreset")
        total = suspended.total
        remaining = suspended.remaining
        switch suspended.state {
        case .running:
            deadline = timeSource.wallNow.addingTimeInterval(remaining)
            continuousDeadline = timeSource.continuousNow + remaining
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
        if phase == .longBreak || longBreakDue { finishLongBreakCycle() }
        phase = .focus
        selectedPreset = 2
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
        if isComplete {
            if flowEnabled {
                phase = upcomingPhase
                selectedPreset = phase.presetIndex
                defaults.set(selectedPreset, forKey: "selectedPreset")
            }
            total = flowEnabled ? duration(for: phase) : TimeInterval(presetSeconds[selectedPreset])
            remaining = total
        } else if remaining <= 0 {
            total = flowEnabled ? duration(for: phase) : TimeInterval(presetSeconds[selectedPreset])
            remaining = total
        }
        if flowEnabled && phase == .longBreak && longBreakDue { focusesInCycle = 0 }
        deadline = timeSource.wallNow.addingTimeInterval(remaining)
        continuousDeadline = timeSource.continuousNow + remaining
        isRunning = true
        isPaused = false
        isComplete = false
        clearAlert()
        saveSession()
        scheduleCurrentNotification()
        if wasPaused {
            announce("Resumed. \(TimerEngine.spokenDuration(remaining)) remaining.")
        } else if wasComplete && flowEnabled {
            announce("\(phase.displayName) session started. \(TimerEngine.spokenDuration(remaining)) remaining.")
        } else {
            announce("\(Self.spokenPresetName(selectedPreset)) started. \(TimerEngine.spokenDuration(remaining)) remaining.")
        }
    }

    func pause() {
        guard isRunning else { return }
        clearPresetUndo()
        if let continuousDeadline {
            remaining = max(0, continuousDeadline - timeSource.continuousNow)
        }
        if remaining == 0 { refresh(); return }
        deadline = nil
        continuousDeadline = nil
        isRunning = false
        isPaused = true
        saveSession()
        notifications?.cancel()
        announce("Paused. \(TimerEngine.spokenDuration(remaining)) remaining.")
    }

    func reset() {
        clearPresetUndo()
        stop()
        if let pendingFlowEnabled {
            applyModeChange(pendingFlowEnabled)
            announce("Timer reset. \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready.")
            return
        }
        total = flowEnabled ? duration(for: phase) : TimeInterval(presetSeconds[selectedPreset])
        remaining = total
        clearAlert()
        saveSession()
        announce("Timer reset. \(TimerEngine.spokenDuration(remaining)) ready.")
    }

    private func clockValues(at testingWallNow: Date?) -> (wall: Date, continuous: TimeInterval) {
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
        guard !wasSleeping, isRunning, let continuousDeadline else { return }
        let timeLeft = max(0, continuousDeadline - (continuousNow ?? timeSource.continuousNow))
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
            let nextPreset = nextPhase.presetIndex
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
        let now = timeSource.continuousNow
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
        installUndo(previous, at: timeSource.continuousNow, label: "Pomodoro",
                    deferUntilActive: true)
    }

    private func snapshotSession() -> SavedTimerSession {
        let state: SavedTimerSession.State = isRunning ? .running : isPaused ? .paused :
            isComplete ? .completed : .ready
        return SavedTimerSession(version: 5, state: state,
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
                                 cycleTarget: cycleTarget)
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
        undoPresetLabel = label ?? TimerEngine.display(previous.total)
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
        total = undo.session.total

        switch undo.session.state {
        case .ready:
            remaining = total
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
                remaining = min(total, timeLeft)
                isRunning = true
                saveSession()
                scheduleCurrentNotification(at: current.continuous)
                showAlert("Timer restored")
                announce("Timer restored. \(TimerEngine.spokenDuration(remaining)) remaining.")
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
            remaining = 0
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
        defaults.removeObject(forKey: SavedTimerSession.key)
        notifications?.cancel()
    }

    private func saveSession() {
        if !isRunning && !isPaused && !isComplete && !flowEnabled &&
            suspendedPomodoro == nil && pendingFlowEnabled == nil &&
            completedFocusTotal == 0 && focusesInCycle == 0 {
            defaults.removeObject(forKey: SavedTimerSession.key)
            return
        }
        let saved = snapshotSession()
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: SavedTimerSession.key)
        }
    }

    private func restoreSession(at now: Date) {
        guard let data = defaults.data(forKey: SavedTimerSession.key) else { return }
        guard let saved = try? JSONDecoder().decode(SavedTimerSession.self, from: data),
              (1...5).contains(saved.version),
              Self.defaultDurations.indices.contains(saved.selectedPreset),
              saved.total.isFinite,
              (1...Double(TimerEngine.maximumDuration)).contains(saved.total),
              (saved.version < 5 || saved.cycleTarget != nil),
              (2...8).contains(saved.cycleTarget ?? 4),
              (0...(saved.cycleTarget ?? 4)).contains(saved.focusesInCycle ?? 0),
              (saved.completedFocusTotal ?? 0) >= 0,
              !(saved.activeFlowEnabled ?? flowEnabled) ||
                  saved.selectedPreset == saved.phase.presetIndex,
              saved.suspendedPomodoro == nil ||
                  ((saved.pomodoroModeEnabled ?? pomodoroModeEnabled) &&
                   !(saved.activeFlowEnabled ?? flowEnabled)) else {
            defaults.removeObject(forKey: SavedTimerSession.key)
            return
        }
        if let suspended = saved.suspendedPomodoro {
            guard suspended.total.isFinite, suspended.remaining.isFinite,
                  (1...Double(TimerEngine.maximumDuration)).contains(suspended.total),
                  (0...suspended.total).contains(suspended.remaining) else {
                defaults.removeObject(forKey: SavedTimerSession.key)
                return
            }
        }
        flowEnabled = saved.activeFlowEnabled ?? flowEnabled
        cycleTarget = saved.cycleTarget ?? 4
        focusesInCycle = saved.focusesInCycle ?? 0
        completedFocusTotal = saved.completedFocusTotal ?? 0
        pomodoroModeEnabled = saved.pomodoroModeEnabled ?? pomodoroModeEnabled
        pendingFlowEnabled = saved.pendingFlowEnabled
        suspendedPomodoro = saved.suspendedPomodoro
        defaults.set(pomodoroModeEnabled, forKey: "flowEnabled")
        switch saved.state {
        case .running:
            guard let savedDeadline = saved.deadline,
                  savedDeadline.timeIntervalSince1970.isFinite else {
                defaults.removeObject(forKey: SavedTimerSession.key)
                return
            }
            let sameBoot = saved.version >= 2 && saved.bootSessionID != nil &&
                saved.bootSessionID == timeSource.bootSessionID
            let savedContinuous = saved.continuousDeadline
            let timeLeft: TimeInterval
            if sameBoot, let savedContinuous, savedContinuous.isFinite,
               savedContinuous >= 0 {
                timeLeft = max(0, savedContinuous - timeSource.continuousNow)
            } else {
                timeLeft = TimerEngine.remaining(until: savedDeadline, at: now)
            }
            selectedPreset = saved.selectedPreset
            phase = saved.phase
            total = saved.total
            if timeLeft > 0 {
                remaining = min(total, timeLeft)
                deadline = now.addingTimeInterval(remaining)
                continuousDeadline = testOriginContinuous + remaining
                isRunning = true
                saveSession()
                scheduleCurrentNotification()
            } else {
                remaining = 0
                isComplete = true
                recordFocusCompletionIfNeeded()
                if phase == .longBreak { finishLongBreakCycle() }
                if let pendingFlowEnabled {
                    applyModeChange(pendingFlowEnabled)
                    showAlert("Timer complete · \(pendingFlowEnabled ? "Pomodoro" : "Countdown") ready")
                } else {
                    saveSession()
                    showAlert(flowEnabled ? "\(phase.displayName) complete" : "Time is up")
                }
            }
        case .paused:
            guard let paused = saved.pausedRemaining, paused.isFinite,
                  paused > 0, paused <= saved.total else {
                defaults.removeObject(forKey: SavedTimerSession.key)
                return
            }
            selectedPreset = saved.selectedPreset
            phase = saved.phase
            total = saved.total
            remaining = paused
            isPaused = true
            saveSession()
        case .completed:
            selectedPreset = saved.selectedPreset
            phase = saved.phase
            total = saved.total
            remaining = 0
            isComplete = true
            saveSession()
        case .ready:
            selectedPreset = saved.selectedPreset
            phase = saved.phase
            total = saved.total
            remaining = total
            saveSession()
        }
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

enum CompletionAudio {
    static let playbackFile = "alarm-titititi.mp3"
    static let notificationFile = "alarm-titititi.caf"

    static func playbackURL() -> URL? {
        Bundle.main.url(forResource: "alarm-titititi", withExtension: "mp3") ??
            Bundle.module.url(forResource: "alarm-titititi", withExtension: "mp3")
    }

    static func notificationURL() -> URL? {
        Bundle.main.url(forResource: "alarm-titititi", withExtension: "caf") ??
            Bundle.module.url(forResource: "alarm-titititi", withExtension: "caf")
    }
}

enum PresetAudio {
    static let playbackFile = "human-thud.mp3"

    static func playbackURL() -> URL? {
        Bundle.main.url(forResource: "human-thud", withExtension: "mp3") ??
            Bundle.module.url(forResource: "human-thud", withExtension: "mp3")
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
