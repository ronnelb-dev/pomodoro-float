import AppKit
import SwiftUI

@MainActor
enum MenuBarQuickAction {
    case countdown
    case stopwatch

    func perform(using timer: TimerModel, requestCountdownEntry: () -> Void) {
        switch self {
        case .countdown:
            requestCountdownEntry()
        case .stopwatch:
            timer.startStopwatch()
        }
    }
}

enum MenuBarTimerIndicator {
    static func stateLabel(isRunning: Bool, isPaused: Bool, isComplete: Bool) -> String {
        if isRunning { return AppStrings.localized("timer.state.running") }
        if isPaused { return AppStrings.localized("timer.state.paused") }
        if isComplete { return AppStrings.localized("timer.state.complete") }
        return AppStrings.localized("timer.state.ready")
    }

    static func systemImage(isRunning: Bool, isPaused: Bool, isComplete: Bool) -> String {
        if isRunning { return "pause.fill" }
        if isPaused { return "play.fill" }
        if isComplete { return "checkmark.circle.fill" }
        return "timer"
    }

    static func primaryActionTitle(isRunning: Bool, isPaused: Bool,
                                   nextPhaseName: String?) -> String {
        if isRunning { return AppStrings.localized("Pause") }
        if isPaused { return AppStrings.localized("Resume") }
        if let nextPhaseName {
            return AppStrings.localizedFormat("menu.startPhase", nextPhaseName)
        }
        return AppStrings.localized("Start")
    }
}

struct MenuBarTimerMenu: View {
    @EnvironmentObject private var timer: TimerModel
    @Environment(\.openWindow) private var openWindow
    @Binding var showingCustomCountdown: Bool

    private var stateLabel: String {
        MenuBarTimerIndicator.stateLabel(isRunning: timer.isRunning,
                                         isPaused: timer.isPaused,
                                         isComplete: timer.isComplete)
    }

    private var sessionLabel: String {
        if timer.sessionKind == .stopwatch { return "Stopwatch" }
        if timer.sessionKind == .customCountdown { return "Countdown" }
        if timer.flowEnabled { return timer.phase.displayName }
        if timer.hasSuspendedPomodoro { return "One-Off · Pomodoro Paused" }
        return timer.presetNames[timer.selectedPreset]
    }

    private var primaryActionTitle: String {
        MenuBarTimerIndicator.primaryActionTitle(isRunning: timer.isRunning,
                                                 isPaused: timer.isPaused,
                                                 nextPhaseName: timer.nextPhaseName)
    }

    var body: some View {
        Text("\(sessionLabel) · \(stateLabel)")
        Text(timer.timeLabel)
            .monospacedDigit()
        Button(primaryActionTitle) { timer.startOrPause() }

        if timer.hasSuspendedPomodoro {
            Button(AppStrings.localized("Resume Pomodoro")) { timer.resumePomodoro() }
        }
        if timer.canSkipBreak {
            Button(timer.skipBreakName) { timer.skipBreak() }
        }

        Menu(AppStrings.localized("Start Preset")) {
            ForEach(timer.presetNames.indices, id: \.self) { index in
                Button("Start \(timer.presetNames[index])") {
                    timer.selectAndStartPreset(index)
                }
            }
        }

        Divider()
        Button(AppStrings.localized("Countdown…")) {
            MenuBarQuickAction.countdown.perform(using: timer) {
                showingCustomCountdown = true
                openTimerWindow()
            }
        }
        Button(AppStrings.localized("Start Stopwatch")) {
            MenuBarQuickAction.stopwatch.perform(using: timer) {}
        }

        Divider()
        Button(AppStrings.localized("Open Pomodoro Float")) { openTimerWindow() }
        Button(AppStrings.localized("Pomodoro Float Help…")) {
            openWindow(id: TimerApplicationDelegate.helpWindowSceneID)
        }
    }

    private func openTimerWindow() {
        if !TimerApplicationDelegate.presentTimerWindowIfAvailable() {
            openWindow(id: TimerApplicationDelegate.timerWindowSceneID)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct TimerHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Binding var showingWelcomeGuide: Bool

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(AppStrings.localized("Welcome Guide…")) { showingWelcomeGuide = true }
            Button(AppStrings.localized("Pomodoro Float Help")) {
                openWindow(id: TimerApplicationDelegate.helpWindowSceneID)
            }
        }
    }
}
