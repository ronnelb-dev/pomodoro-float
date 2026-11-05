# Pomodoro Float

Pomodoro Float is a native macOS focus timer with three displays: a rotatable 3D cube, a classic seven-segment digital timer, and a localized Desk Clock. Use it in a standard window or as a compact floating timer beside your work.

## Screenshots

| Cube · Charcoal | Cube · Light |
| --- | --- |
| ![Charcoal Pomodoro Float cube showing a 25-minute countdown](assets/screenshots/pomodoro-float-cube-charcoal.png) | ![White Pomodoro Float cube showing a 25-minute countdown](assets/screenshots/pomodoro-float-cube-light.png) |

| Cube · Blue | Digital |
| --- | --- |
| ![Blue Pomodoro Float cube showing a 25-minute countdown](assets/screenshots/pomodoro-float-cube-blue.png) | ![Pomodoro Float seven-segment digital timer showing 05:00 ready](assets/screenshots/pomodoro-float-digital.png) |

## Features

- Choose Cube or Digital display; the choice is saved between launches.
- Switch to Desk Clock to show the localized current time with seconds, weekday, and date; the clock can be used while a timer continues running.
- Switch between the full standard window and a compact floating window. Keep the timer visible while working, and resize either window.
- Run customizable Pomodoro focus and break cycles, with progress, completion alerts, and session restore.
- Start a one-off countdown from 00:01 to 99:59 without changing saved presets, or use the MM:SS stopwatch.
- Personalize the five preset slots with names and Focus, Short Break, or General roles; Pomodoro follows the semantic roles rather than fixed positions.
- Save a one-off Countdown into a chosen preset slot, or restore all preset names, roles, and durations to their defaults without resetting an active timer.
- Adjust themes, cube appearance, sounds, and timer behavior in the built-in settings.

## Requirements

- macOS 14 or later.
- A full Xcode installation with Swift 5.9 or later. The app uses SwiftUI and SceneKit; Apple Command Line Tools alone are not sufficient to build it.

## Build and run

From the repository root:

```sh
./scripts/build-app.sh
open "build/Pomodoro Float.app"
```

The script builds a release executable, packages the app icon and sounds, and ad-hoc signs the app for local use. Select the Xcode installation to use with `DEVELOPER_DIR` if needed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
```

Run the test suite with:

```sh
swift test
```

## Project map

| Area | Responsibility |
| --- | --- |
| `Sources/CubeTimer/TimerEngine.swift` | Pure countdown math, formatting, and progress. |
| `Sources/CubeTimer/TimerSessionCoordinator.swift` and `TimerSessionPersistence.swift` | Session transitions, domain events, persistence, and restore compatibility. |
| `Sources/CubeTimer/TimerModel.swift` | SwiftUI-facing timer state, preferences, and coordination of macOS effects. |
| `Sources/CubeTimer/CubeSceneView.swift` and `DigitalTimerView.swift` | SceneKit cube display and seven-segment digital display. |
| `Sources/CubeTimer/CubeTimerApp.swift` | SwiftUI app, window configuration, and timer controls. |
| `Tests/CubeTimerTests/` | Timer behavior, persistence, display, appearance, and window-layout tests. |

## Useful controls

- **Start, pause, or resume:** Click the timer or press **Space**. **Command-R** resets it.
- **Start a preset:** **Command-1** through **Command-5** starts the five preset slots. Their names and durations can be customized in Settings.
- **Countdown or stopwatch:** Use the mode buttons below the presets in the standard window, the **Timer** menu, or the floating timer's right-click menu.
- **Desk Clock:** Choose **Clock** in the display picker or floating menu. The time, weekday, and date follow the Mac's locale and 12/24-hour preference. Digital and Clock modes can enter full screen; press **Esc** to return.
- **Settings:** Press **Command-,** to edit preset names, durations, and Focus/Short Break roles; configure Pomodoro cycles, appearance, sounds, and window behavior. Use **Reset Presets to Defaults** to restore the built-in slots without resetting an active timer.
- **Floating window:** Press **Command-Shift-B** to toggle it. **Control-drag** the cube to move the floating window; hold **Control** and drag its lower-right grip to resize it. Right-click for timer and window controls.

Pomodoro defaults are 25 minutes of focus, a 5-minute short break, and a 15-minute long break after four focuses. Timer sessions and preferences are saved across launches.

## Countdown and stopwatch

- **Countdown:** Click **COUNTDOWN** to enter any duration from 00:01 to 99:59, then click **Start**. Opening or dismissing the time-entry popover does not interrupt the current timer, and starting a countdown does not change the saved presets.
- **Save a Countdown:** In the Countdown popover, choose **Save as Preset**, select one of the five slots, and confirm its name. Saving changes only that slot’s future preset settings; it does not replace the active timer.
- **Stopwatch:** Click **STOPWATCH** to start counting up immediately. Use the regular timer control or **Space** to pause and resume, and **Command-R** to reset. The stopwatch stops at 99:59 without a completion alert.
- **During Pomodoro:** Starting either mode suspends the current phase. Use **Resume Pomodoro** to return to it. When a mode replaces an active timer, **Undo** is available for six seconds.

## License

[MIT](LICENSE)
