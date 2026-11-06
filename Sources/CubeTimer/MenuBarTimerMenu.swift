import AppKit
import SwiftUI

enum MenuBarTimerIndicator {
    static func stateLabel(isRunning: Bool, isPaused: Bool, isComplete: Bool) -> String {
        if isRunning { return "Running" }
        if isPaused { return "Paused" }
        if isComplete { return "Complete" }
        return "Ready"
    }

    static func systemImage(isRunning: Bool, isPaused: Bool, isComplete: Bool) -> String {
        if isRunning { return "pause.fill" }
        if isPaused { return "play.fill" }
        if isComplete { return "checkmark.circle.fill" }
        return "timer"
    }

    static func primaryActionTitle(isRunning: Bool, isPaused: Bool,
                                   nextPhaseName: String?) -> String {
        if isRunning { return "Pause" }
        if isPaused { return "Resume" }
        if let nextPhaseName { return "Start \(nextPhaseName)" }
        return "Start"
    }
}

struct MenuBarTimerMenu: View {
    @EnvironmentObject private var timer: TimerModel
    @Environment(\.openWindow) private var openWindow

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
            Button("Resume Pomodoro") { timer.resumePomodoro() }
        }
        if timer.canSkipBreak {
            Button(timer.skipBreakName) { timer.skipBreak() }
        }

        Menu("Start Preset") {
            ForEach(timer.presetNames.indices, id: \.self) { index in
                Button("Start \(timer.presetNames[index])") {
                    timer.selectAndStartPreset(index)
                }
            }
        }

        Divider()
        Button("Open Pomodoro Float") { openTimerWindow() }
        Button("Pomodoro Float Help…") {
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

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Pomodoro Float Help") {
                openWindow(id: TimerApplicationDelegate.helpWindowSceneID)
            }
        }
    }
}
