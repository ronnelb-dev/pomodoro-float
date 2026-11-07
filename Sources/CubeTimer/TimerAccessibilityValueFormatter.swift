import Foundation

enum TimerAccessibilityValueFormatter {
    static func value(snapshot: TimerSessionSnapshot, presetName: String) -> String {
        let state = snapshot.isComplete ? AppStrings.localized("timer.state.complete") :
            snapshot.isRunning ? AppStrings.localized("timer.state.running") :
            snapshot.isPaused ? AppStrings.localized("timer.state.paused") :
            AppStrings.localized("timer.state.ready")
        let session: String
        switch snapshot.sessionKind {
        case .stopwatch:
            session = AppStrings.localizedFormat(
                "accessibility.session.stopwatch",
                TimerEngine.spokenDuration(snapshot.remaining.rounded(.down)))
        case .customCountdown:
            session = AppStrings.localized("Countdown")
        case .presetCountdown:
            if snapshot.flowEnabled {
                let duration = snapshot.phase == .longBreak
                    ? TimerEngine.spokenDuration(snapshot.total) : presetName
                session = AppStrings.localizedFormat(
                    "accessibility.session.phase", snapshot.phase.displayName, duration)
            } else {
                session = snapshot.suspendedPomodoro == nil ? presetName :
                    AppStrings.localizedFormat("accessibility.session.presetPaused", presetName)
            }
        }
        let count = snapshot.pomodoroModeEnabled
            ? AppStrings.localizedFormat("accessibility.focusCycle", snapshot.focusesInCycle,
                                         snapshot.cycleTarget, snapshot.completedFocusTotal)
            : ""
        if snapshot.sessionKind == .stopwatch {
            return AppStrings.localizedFormat("accessibility.value.stopwatch", session, state, count)
        }
        return AppStrings.localizedFormat("accessibility.value.countdown", session, state,
                                          TimerEngine.spokenDuration(snapshot.remaining), count)
    }
}
