# Pomodoro Float

Pomodoro Float is a native macOS focus timer built around a rotatable 3D cube. Keep it floating beside your work, click a numbered face to start a countdown, and customize how it looks and sounds.

- Five editable timer presets, with 5, 10, 25, 50, and 60 minutes by default.
- Pomodoro focus, short-break, and long-break cycles.
- A resizable window or a transparent, borderless floating cube.
- Appearance controls, completion alerts, saved sessions, and VoiceOver support.

## Requirements

- macOS 14 or later.
- Xcode with a Swift 5.9 or newer toolchain.

## Build, launch, and test

Run these commands from the repository root:

```sh
./scripts/build-app.sh
open "build/Pomodoro Float.app"
```

The script builds a release executable, packages the sound resources, and ad-hoc signs the app for local use. The Swift package and executable are still named `CubeTimer`; you can run that target from Xcode, but use the packaged `.app` for macOS notifications.

Run the test suite with:

```sh
swift test
```

## Quick start

Drag the cube to rotate it. Click a numbered face to bring it forward and **start** that preset from its full duration. Click the countdown display, press **Space**, or use the visible controls to start, pause, or resume the current timer.

The five preset buttons in the standard window behave differently: they **select without starting**. Selecting a different preset stops the current countdown and leaves the new duration ready for **Start**.

| Action | Control |
| --- | --- |
| Start, pause, or resume | Click the countdown display or press **Space** |
| Select and start a preset | Click its numbered cube face or press **Command-1** through **Command-5** |
| Select a preset without starting | Click a visible preset button or press **Command-Left/Right** |
| Reset the timer | Use **Reset** or press **Command-R** |
| Undo a timer replacement | Use **Undo** or press **Command-Z** while the six-second offer is visible |
| Bring the countdown face back | Click the **viewfinder**; the timer keeps its state and remaining time |
| Open Settings | Press **Command-,** |
| Toggle the borderless window | Press **Command-Shift-B** |
| Resume a paused Pomodoro phase | Press **Command-Shift-P** |
| Skip a short or long break | Press **Command-Shift-K** |

## Pomodoro sessions

Turn on **Auto-cycle focus and break** in **Settings → Timer**. The defaults are a 25-minute focus, a 5-minute short break, and a 15-minute long break after four completed focuses. You can set each duration from 00:01 to 99:59 and choose a long break after 2–8 focuses. The cube shows the current phase and progress toward the long break.

**Automatically start next phase** is on by default for sessions that finish while the app is running on time. Turn it off to start each phase yourself. If a phase ends while the Mac sleeps or the app catches up later, the next phase waits for **Start** rather than skipping ahead. Only focuses that reach their deadline count toward the saved total.

Selecting or starting a 10-, 50-, or 60-minute preset during Pomodoro pauses the current phase behind a one-off timer. Use **Resume Pomodoro** in the window or cube menu, or press **Command-Shift-P**, to return to it. A Pomodoro mode change requested during a running or paused timer takes effect when that timer finishes.

## Make it yours

- **Timer settings:** Edit presets, break length, cycle length, mute, and in-app sound volume.
- **Appearance:** Choose Dark, Light, or Midnight; Matte, Satin, or Gloss; and the cube, accent, and digit colors. Lighting and shadow controls are available. **Automatic readable digits** adjusts low-contrast digits by default without replacing your saved color.
- **Window:** Use the pin to toggle **Always on Top**. Resize the standard window from an edge or corner. In borderless mode, hold **Control** to reveal the resize grip; **Control-drag** the cube to move the window, or the grip to resize it. Right-click the cube for window controls and **Hide PomoFloat**.

The app remembers each window mode's size and position. When the countdown face turns away, a small readout keeps the time visible; the viewfinder returns the display face without changing the timer.

## Alerts, accessibility, and saved sessions

Running and paused sessions, timer settings, appearance, and Pomodoro progress survive relaunch. The countdown accounts for Mac sleep. A timer that finishes while the app is closed is shown as complete when you reopen it, without replaying the alarm.

Completion notifications depend on macOS notification and sound settings. The app's volume slider controls sounds while it is active; macOS system volume controls notification sound when it is hidden or closed. Mute applies to both. The cube and controls expose timer actions, preset durations, and phase information to VoiceOver, with announcements for actions and phase changes.
