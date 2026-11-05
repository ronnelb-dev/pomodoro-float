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

enum TimerSessionKind: String, Codable {
    case presetCountdown
    case customCountdown
    case stopwatch
}

extension Notification.Name {
    static let cubeTimerWillChangeWindowMode = Notification.Name("CubeTimerWillChangeWindowMode")
    static let cubeTimerWindowModeDidChange = Notification.Name("CubeTimerWindowModeDidChange")
    static let cubeTimerDisplayFullscreenExitRequested =
        Notification.Name("CubeTimerDisplayFullscreenExitRequested")
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
    var sessionKind: TimerSessionKind? = nil
}

struct SuspendedPomodoroSession: Codable, Equatable {
    let state: SavedTimerSession.State
    let phase: SessionPhase
    let total: TimeInterval
    let remaining: TimeInterval
}

enum DurationSetting: Equatable {
    case preset(Int)
    case longBreak
}

enum DurationImmediateAction: Equatable {
    case applyNow
    case restartThisPhase
}

enum DurationEditAction {
    case useNextTime
    case applyNow
    case restartThisPhase
}

enum TimerDisplayStyle: String, CaseIterable, Identifiable {
    case cube
    case digital
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cube: "Cube"
        case .digital: "Digital"
        case .clock: "Clock"
        }
    }

    var supportsFullscreen: Bool { self == .digital || self == .clock }

    var fullscreenTitle: String {
        switch self {
        case .cube: "Full Screen"
        case .digital: "Full Screen Digital Timer"
        case .clock: "Full Screen Clock"
        }
    }
}

@MainActor
final class TimerModel: ObservableObject {
    static let presetNames = ["5 MIN", "10 MIN", "25 MIN", "50 MIN", "60 MIN"]
    static let defaultDurations = [300, 600, 1500, 3000, 3600]
    static let displayStyleKey = "timerDisplayStyle"
    static func spokenPresetName(_ index: Int) -> String {
        "\(defaultDurations[index] / 60)-minute preset"
    }

    @Published var alwaysOnTop: Bool {
        didSet { coordinator.alwaysOnTop = alwaysOnTop }
    }
    @Published private(set) var borderlessWindow: Bool
    @Published private(set) var isDisplayFullscreen = false
    @Published private(set) var isPreparingDisplayFullscreen = false
    @Published var muted: Bool {
        didSet { coordinator.muted = muted }
    }
    @Published var volume: Double {
        didSet { coordinator.volume = volume }
    }
    @Published var autoStartNextPhase: Bool {
        didSet {
            preferences.autoStartNextPhase = autoStartNextPhase
            coordinator.autoStartNextPhase = autoStartNextPhase
        }
    }
    @Published var displayStyle: TimerDisplayStyle {
        didSet { defaults.set(displayStyle.rawValue, forKey: Self.displayStyleKey) }
    }
    @Published private(set) var sessionSnapshot: TimerSessionSnapshot
    @Published private(set) var preferences: TimerSessionPreferences

    var presetSeconds: [Int] { preferences.presetSeconds }
    var sessionKind: TimerSessionKind { sessionSnapshot.sessionKind }
    var selectedPreset: Int { sessionSnapshot.selectedPreset }
    var remaining: TimeInterval { sessionSnapshot.remaining }
    var total: TimeInterval { sessionSnapshot.total }
    var isRunning: Bool { sessionSnapshot.isRunning }
    var isPaused: Bool { sessionSnapshot.isPaused }
    var isComplete: Bool { sessionSnapshot.isComplete }
    var flowEnabled: Bool { sessionSnapshot.flowEnabled }
    var pomodoroModeEnabled: Bool { sessionSnapshot.pomodoroModeEnabled }
    var pendingFlowEnabled: Bool? { sessionSnapshot.pendingFlowEnabled }
    var suspendedPomodoro: SuspendedPomodoroSession? { sessionSnapshot.suspendedPomodoro }
    var phase: SessionPhase { sessionSnapshot.phase }
    var focusesInCycle: Int { sessionSnapshot.focusesInCycle }
    var completedFocusTotal: Int { sessionSnapshot.completedFocusTotal }
    var longBreakSeconds: Int { preferences.longBreakSeconds }
    var cycleTarget: Int { sessionSnapshot.cycleTarget }
    var requestedCycleTarget: Int { preferences.requestedCycleTarget }
    var alertText: String? { sessionSnapshot.alertText }
    var undoPresetLabel: String? { sessionSnapshot.undoPresetLabel }
    var progress: Double { sessionKind == .stopwatch ? 0 : TimerEngine.progress(remaining: remaining, total: total) }
    var timeLabel: String { sessionKind == .stopwatch ?
        TimerEngine.stopwatchDisplay(remaining) : TimerEngine.display(remaining) }
    var requestedFlowEnabled: Bool { pendingFlowEnabled ?? pomodoroModeEnabled }
    var hasSuspendedPomodoro: Bool { suspendedPomodoro != nil }
    var longBreakDue: Bool { focusesInCycle >= cycleTarget }
    var focusProgressLabel: String { "\(focusesInCycle)/\(cycleTarget)" }
    var cycleTargetChangePending: Bool { cycleTarget != requestedCycleTarget }
    var nextPhaseName: String? {
        guard flowEnabled, isComplete else { return nil }
        return phase == .focus ? (longBreakDue ? SessionPhase.longBreak.displayName : SessionPhase.breakTime.displayName)
            : SessionPhase.focus.displayName
    }
    var canSkipBreak: Bool {
        flowEnabled && (phase.isBreak && !isComplete || phase == .focus && isComplete && longBreakDue)
    }
    var skipBreakName: String {
        phase == .longBreak || phase == .focus && longBreakDue ? "Skip Long Break" : "Skip Short Break"
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
            ? "\(phase.displayName) session, \(phase == .longBreak ? TimerEngine.spokenDuration(total) : Self.spokenPresetName(selectedPreset))"
            : "\(Self.spokenPresetName(selectedPreset))\(hasSuspendedPomodoro ? ", Pomodoro paused" : "")"
        let count = pomodoroModeEnabled
            ? ", \(focusesInCycle) of \(cycleTarget) focuses toward long break, \(completedFocusTotal) completed focuses total"
            : ""
        return sessionKind == .stopwatch ? "\(session), \(state)\(count)" :
            "\(session), \(state), \(TimerEngine.spokenDuration(remaining)) remaining\(count)"
    }

    private let coordinator: TimerSessionCoordinator
    private let defaults: UserDefaults
    private let timeSource: TimerTimeSource
    private var observation: AnyCancellable?
    private var temporaryStandardWindowForDisplayFullscreen = false

    init(defaults: UserDefaults = .standard, notificationsEnabled: Bool = true,
         now: Date = Date(), notificationClient: CompletionNotificationClient? = nil,
         soundClient: CompletionSoundClient? = nil,
         presetSoundClient: PresetSoundClient? = nil,
         timeSource: TimerTimeSource = SystemTimerTimeSource(),
         appIsActive: @escaping @MainActor () -> Bool = {
             NSApp?.isActive == true && NSApp?.isHidden == false
         },
         accessibilityAnnouncer: TimerAccessibilityAnnouncementClient? = nil) {
        self.timeSource = timeSource
        self.defaults = defaults
        coordinator = TimerSessionCoordinator(
            defaults: defaults, notificationsEnabled: notificationsEnabled, now: now,
            notificationClient: notificationClient, soundClient: soundClient,
            presetSoundClient: presetSoundClient, timeSource: timeSource,
            appIsActive: appIsActive, accessibilityAnnouncer: accessibilityAnnouncer)
        sessionSnapshot = coordinator.sessionSnapshot
        alwaysOnTop = coordinator.alwaysOnTop
        borderlessWindow = coordinator.borderlessWindow
        muted = coordinator.muted
        volume = coordinator.volume
        autoStartNextPhase = coordinator.autoStartNextPhase
        displayStyle = TimerDisplayStyle(rawValue: defaults.string(forKey: Self.displayStyleKey) ?? "") ?? .cube
        preferences = TimerSessionPreferences(presetSeconds: coordinator.presetSeconds,
                                              longBreakSeconds: coordinator.longBreakSeconds,
                                              requestedCycleTarget: coordinator.requestedCycleTarget,
                                              autoStartNextPhase: coordinator.autoStartNextPhase)
        observation = coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sessionSnapshot = self.coordinator.sessionSnapshot
                self.syncPreferencesFromSessionRuntime()
                self.borderlessWindow = self.temporaryStandardWindowForDisplayFullscreen
                    ? false : self.coordinator.borderlessWindow
                self.objectWillChange.send()
        }
    }

    private func send(_ action: TimerSessionCommand.Action,
                      wallNow: Date? = nil) -> TimerSessionUpdate {
        let update = coordinator.handle(TimerSessionCommand(action: action,
                                                             preferences: preferences,
                                                             time: TimerSessionTime(
                                                                wallNow: wallNow ?? timeSource.wallNow,
                                                                continuousNow: timeSource.continuousNow,
                                                                bootSessionID: timeSource.bootSessionID)))
        sessionSnapshot = update.snapshot
        syncPreferencesFromSessionRuntime()
        return update
    }

    private func syncPreferencesFromSessionRuntime() {
        preferences.presetSeconds = coordinator.presetSeconds
        preferences.longBreakSeconds = coordinator.longBreakSeconds
        preferences.requestedCycleTarget = coordinator.requestedCycleTarget
        if autoStartNextPhase != coordinator.autoStartNextPhase {
            autoStartNextPhase = coordinator.autoStartNextPhase
        } else {
            preferences.autoStartNextPhase = coordinator.autoStartNextPhase
        }
    }

    func selectPreset(_ index: Int) { _ = send(.selectPreset(index)) }
    func startCustomCountdown(seconds: Int) { _ = send(.startCustomCountdown(seconds)) }
    func startStopwatch() { _ = send(.startStopwatch) }
    func presetBecomesOneOff(_ index: Int) -> Bool {
        coordinator.presetBecomesOneOff(index)
    }
    func selectAndStartPreset(_ index: Int) { _ = send(.selectAndStartPreset(index)) }
    func selectAndStartCubeFace(_ index: Int) { _ = send(.selectAndStartCubeFace(index)) }
    func turn(_ direction: Int) { _ = send(.turn(direction)) }
    func setBorderlessWindow(_ enabled: Bool) {
        guard !isDisplayFullscreen, !isPreparingDisplayFullscreen else { return }
        coordinator.setBorderlessWindow(enabled)
        borderlessWindow = temporaryStandardWindowForDisplayFullscreen
            ? false : coordinator.borderlessWindow
    }

    @discardableResult
    func prepareForDisplayFullscreen() -> Bool {
        guard displayStyle.supportsFullscreen else { return false }
        isPreparingDisplayFullscreen = true
        guard coordinator.borderlessWindow,
              !temporaryStandardWindowForDisplayFullscreen else { return true }

        NotificationCenter.default.post(name: .cubeTimerWillChangeWindowMode, object: nil)
        temporaryStandardWindowForDisplayFullscreen = true
        borderlessWindow = false
        return true
    }

    func didEnterDisplayFullscreen() {
        guard displayStyle.supportsFullscreen else { return }
        isPreparingDisplayFullscreen = false
        isDisplayFullscreen = true
    }

    func finishDisplayFullscreen() {
        isPreparingDisplayFullscreen = false
        isDisplayFullscreen = false
        guard temporaryStandardWindowForDisplayFullscreen else { return }

        NotificationCenter.default.post(name: .cubeTimerWillChangeWindowMode, object: nil)
        temporaryStandardWindowForDisplayFullscreen = false
        borderlessWindow = coordinator.borderlessWindow
    }
    func setPreset(_ index: Int, seconds: Int) { _ = send(.setPreset(index, seconds)) }
    func setLongBreak(seconds: Int) { _ = send(.setLongBreak(seconds)) }
    func immediateDurationAction(for setting: DurationSetting,
                                 seconds: Int) -> DurationImmediateAction? {
        coordinator.immediateDurationAction(for: setting, seconds: seconds)
    }
    @discardableResult
    func editDuration(_ setting: DurationSetting, seconds: Int,
                      action: DurationEditAction) -> Bool {
        send(.editDuration(setting, seconds, action)).accepted
    }
    func setCycleTarget(_ target: Int) { _ = send(.setCycleTarget(target)) }
    func setFlowEnabled(_ enabled: Bool) { _ = send(.setFlowEnabled(enabled)) }
    @discardableResult func resumePomodoro() -> Bool {
        send(.resumePomodoro).accepted
    }
    func startOrPause() { _ = send(.startOrPause) }
    func startNextPhase() { _ = send(.startNextPhase) }
    func skipBreak() { _ = send(.skipBreak) }
    func start() { _ = send(.start) }
    func pause() { _ = send(.pause) }
    func reset() { _ = send(.reset) }
    func refresh(at now: Date? = nil, afterWake: Bool = false) {
        _ = send(.refresh(afterWake: afterWake), wallNow: now)
    }
    func prepareForSleep() { _ = send(.prepareForSleep) }
    func resumeAfterSleep(at now: Date? = nil) {
        _ = send(.resumeAfterSleep, wallNow: now)
    }
    @discardableResult func undoPresetChange(at now: Date? = nil) -> Bool {
        send(.undoPresetChange, wallNow: now).accepted
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
