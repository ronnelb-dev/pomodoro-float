import AppKit

@MainActor
final class TimerApplicationDelegate: NSObject, NSApplicationDelegate {
    static let timerWindowIdentifier = NSUserInterfaceItemIdentifier("pomodoro-float.timer-window")

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                      hasVisibleWindows: Bool) -> Bool {
        let timerWindow = sender.orderedWindows.first(where: Self.isTimerWindow)
            ?? sender.windows.reversed().first(where: Self.isTimerWindow)
        return handleReopen(timerWindowExists: timerWindow != nil) {
            guard let timerWindow else { return }
            if timerWindow.isMiniaturized {
                timerWindow.deminiaturize(nil)
            }
            timerWindow.makeKeyAndOrderFront(nil)
        }
    }

    func handleReopen(timerWindowExists: Bool,
                      bringWindowToFront: () -> Void) -> Bool {
        guard timerWindowExists else { return true }
        bringWindowToFront()
        return false
    }

    private static func isTimerWindow(_ window: NSWindow) -> Bool {
        window.identifier == timerWindowIdentifier
    }
}
