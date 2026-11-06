import SwiftUI

struct TimerHelpView: View {
    private let topics: [(title: String, details: String)] = [
        ("Start and control a timer",
         "Click the timer to start, pause, or resume. Press Space for the same action and Command-R to reset. Choose a preset and press Start; Command-1 through Command-5 start saved presets immediately."),
        ("Use the cube",
         "Drag to rotate the cube. Click a face to start that preset. Press Command-Left Arrow or Command-Right Arrow to turn a face. Right-click the cube for timer and window controls."),
        ("Use the floating window",
         "Press Command-Shift-B to switch window styles. In the borderless window, Control-drag the cube to move it and Control-drag the lower-right grip to resize it. The right-click menu contains timer controls."),
        ("Choose a display",
         "Use the display picker to choose Cube, Digital, or Clock. All three displays support full screen. Cube becomes an immersive interactive view; press Escape to leave it."),
        ("Countdown and stopwatch",
         "Choose Countdown to enter a one-off duration, or Stopwatch to count up. Command-R resets either mode. A one-off timer suspends an active Pomodoro; choose Resume Pomodoro or press Command-Shift-P to return to it."),
        ("Customize the timer",
         "Press Command-Comma to edit preset names, durations, and Pomodoro settings, and to change appearance, sound, and window options. Enable the menu bar timer from Settings > Window.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pomodoro Float Help")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("A quick reference for timer controls and shortcuts.")
                        .foregroundStyle(.secondary)
                }

                ForEach(topics, id: \.title) { topic in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(topic.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(topic.details)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 500)
    }
}
