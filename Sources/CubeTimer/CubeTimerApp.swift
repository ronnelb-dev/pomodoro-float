import AppKit
import SwiftUI

@main
struct CubeTimerApp: App {
    @StateObject private var timer = TimerModel()
    @StateObject private var appearance = AppearanceModel()
    @State private var showingSettings = false

    var body: some Scene {
        WindowGroup("Pomodoro Float") {
            TimerView(showingSettings: $showingSettings)
                .environmentObject(timer)
                .environmentObject(appearance)
                .background(WindowConfigurator(alwaysOnTop: timer.alwaysOnTop,
                                               borderless: timer.borderlessWindow))
        }
        .defaultSize(width: 420, height: 560)
        .commands {
            CommandGroup(before: .undoRedo) {
                if timer.undoPresetLabel != nil {
                    Button("Undo Timer Change") { timer.undoPresetChange() }
                        .keyboardShortcut("z", modifiers: .command)
                }
            }
            CommandMenu("Timer") {
                Button(timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" :
                       timer.nextPhaseName.map { "Start \($0)" } ?? "Start")) {
                    timer.startOrPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Reset") { timer.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                if timer.hasSuspendedPomodoro {
                    Button("Resume Pomodoro") { timer.resumePomodoro() }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                }
                if timer.canSkipBreak {
                    Button(timer.skipBreakName) { timer.skipBreak() }
                        .keyboardShortcut("k", modifiers: [.command, .shift])
                }
                Divider()
                Button("Previous Face") { timer.turn(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Next Face") { timer.turn(1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Divider()
                ForEach(TimerModel.presetNames.indices, id: \.self) { index in
                    Button("Start \(TimerModel.presetNames[index]) Preset") {
                        timer.selectAndStartPreset(index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                      modifiers: .command)
                }
                Divider()
                Button("Settings…") { showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Borderless Window") {
                    timer.setBorderlessWindow(!timer.borderlessWindow)
                }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Always on Top") { timer.alwaysOnTop.toggle() }
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let alwaysOnTop: Bool
    let borderless: Bool
    final class Coordinator: NSObject {
        weak var configuredWindow: NSWindow?
        var observers: [NSObjectProtocol] = []
        var appliedBorderless: Bool?
        var isSwitchingMode = false
        var standardStyleMask: NSWindow.StyleMask?
        private var frameBeforeZoom: NSRect?
        private var zoomedFrame: NSRect?

        @objc func toggleZoom(_ sender: Any?) {
            guard let window = configuredWindow,
                  let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
            if let previous = frameBeforeZoom, let zoomedFrame,
               abs(window.frame.width - zoomedFrame.width) < 2,
               abs(window.frame.height - zoomedFrame.height) < 2 {
                window.setFrame(previous, display: true)
                frameBeforeZoom = nil
                self.zoomedFrame = nil
            } else {
                let width = min(850, visible.width)
                let height = min(1000, visible.height)
                let target = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                                    width: width, height: height)
                frameBeforeZoom = window.frame
                zoomedFrame = target
                // The native animated Zoom path aborts in AppKit on macOS 27.0.1.
                window.setFrame(target, display: true)
            }
        }

        func resetZoom() {
            frameBeforeZoom = nil
            zoomedFrame = nil
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { [coordinator] in
            guard let window = view.window else { return }
            if coordinator.configuredWindow !== window {
                coordinator.observers.forEach(NotificationCenter.default.removeObserver)
                coordinator.observers.removeAll()
                coordinator.configuredWindow = window
                coordinator.appliedBorderless = nil
                coordinator.standardStyleMask = window.styleMask
                for event in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                    coordinator.observers.append(NotificationCenter.default.addObserver(
                        forName: event, object: window, queue: .main
                    ) { [weak window, weak coordinator] _ in
                        guard let window, let coordinator, !coordinator.isSwitchingMode,
                              let mode = coordinator.appliedBorderless,
                              !window.styleMask.contains(.fullScreen) else { return }
                        let frame = window.frame
                        guard mode ? abs(frame.width - frame.height) < 2
                                   : (frame.width >= 350 && frame.height >= 490) else { return }
                        Self.saveFrame(window, borderless: mode)
                    })
                }
                coordinator.observers.append(NotificationCenter.default.addObserver(
                    forName: .cubeTimerWillChangeWindowMode, object: nil, queue: nil
                ) { [weak window, weak coordinator] _ in
                    guard let window, let coordinator,
                          let mode = coordinator.appliedBorderless else { return }
                    coordinator.isSwitchingMode = true
                    Self.saveFrame(window, borderless: mode)
                })
            }
            if coordinator.appliedBorderless != borderless {
                coordinator.isSwitchingMode = true
                coordinator.resetZoom()
                configureChrome(window, borderless: borderless,
                                standardStyleMask: coordinator.standardStyleMask)
                let frame = restoredFrame(for: window, borderless: borderless,
                                          previousMode: coordinator.appliedBorderless)
                window.setFrame(frame, display: true)
                coordinator.appliedBorderless = borderless
                Self.saveFrame(window, borderless: borderless)
                coordinator.isSwitchingMode = false
            }
            if !borderless, let zoom = window.standardWindowButton(.zoomButton) {
                zoom.target = coordinator
                zoom.action = #selector(Coordinator.toggleZoom(_:))
            }
            window.level = alwaysOnTop ? .floating : .normal
            if alwaysOnTop {
                window.collectionBehavior.insert(.canJoinAllSpaces)
                window.collectionBehavior.insert(.fullScreenAuxiliary)
            } else {
                window.collectionBehavior.remove(.canJoinAllSpaces)
                window.collectionBehavior.remove(.fullScreenAuxiliary)
            }
        }
    }

    fileprivate static func saveFrame(_ window: NSWindow, borderless: Bool) {
        UserDefaults.standard.set(NSStringFromRect(window.frame),
                                  forKey: frameKey(borderless: borderless))
    }

    private static func frameKey(borderless: Bool) -> String {
        borderless ? "CubeTimerBorderlessWindowFrame" : "CubeTimerWindowFrame"
    }

    private func configureChrome(_ window: NSWindow, borderless: Bool,
                                 standardStyleMask: NSWindow.StyleMask?) {
        window.styleMask = borderless ? [.borderless, .resizable]
                                      : (standardStyleMask ?? [.titled, .closable, .miniaturizable])
                                          .union(.resizable)
        window.aspectRatio = borderless ? NSSize(width: 1, height: 1) : .zero
        window.minSize = borderless ? NSSize(width: 240, height: 240)
                                    : NSSize(width: 350, height: 490)
        window.maxSize = borderless ? NSSize(width: 850, height: 850)
                                    : NSSize(width: 850, height: 1000)
        window.titleVisibility = borderless ? .hidden : .visible
        window.titlebarAppearsTransparent = borderless
        window.titlebarSeparatorStyle = borderless ? .none : .automatic
        if borderless { window.styleMask.insert(.fullSizeContentView) }
        else { window.styleMask.remove(.fullSizeContentView) }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = borderless
        }
        window.isOpaque = !borderless
        window.backgroundColor = borderless ? .clear : .windowBackgroundColor
        window.hasShadow = !borderless
        window.isMovableByWindowBackground = false
    }

    private func restoredFrame(for window: NSWindow, borderless: Bool,
                               previousMode: Bool?) -> NSRect {
        let key = Self.frameKey(borderless: borderless)
        let saved = UserDefaults.standard.string(forKey: key).map(NSRectFromString)
        var frame: NSRect
        if let saved, saved.width > 0, saved.height > 0 {
            frame = saved
        } else if borderless {
            frame = NSRect(x: window.frame.midX - 160, y: window.frame.midY - 160,
                           width: 320, height: 320)
        } else if previousMode != nil {
            frame = NSRect(x: window.frame.midX - 210, y: window.frame.midY - 280,
                           width: 420, height: 560)
        } else {
            frame = window.frame
        }
        if borderless {
            return BorderlessWindowPosition.restoredFrame(
                frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        }
        let screen = NSScreen.screens.max {
            let a = NSIntersectionRect($0.visibleFrame, frame)
            let b = NSIntersectionRect($1.visibleFrame, frame)
            return a.width * a.height < b.width * b.height
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        frame.size.width = min(visible.width, 850, max(350, frame.width))
        frame.size.height = min(visible.height, 1000, max(490, frame.height))
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        return frame
    }
}

private struct WindowReference: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    final class ProbeView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onWindow?(self.window)
            }
        }
    }
    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: ProbeView, context: Context) {
        view.onWindow = onWindow
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

private struct BorderlessResizeGrip: NSViewRepresentable {
    let window: NSWindow?
    let accent: NSColor
    let settingsPresented: Bool

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.setAccessibilityLabel("Resize borderless window")
        view.setAccessibilityRole(.button)
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.resizeWindow = window
        view.ensureTrackingWindow()
        view.setSettingsPresented(settingsPresented)
        if view.accent != accent {
            view.accent = accent
            view.needsDisplay = true
        }
    }

    static func dismantleNSView(_ view: GripView, coordinator: ()) {
        view.stopTrackingControl()
    }

    final class GripView: NSView {
        weak var resizeWindow: NSWindow?
        var accent = NSColor.orange
        private var controlHeld = false
        private var hovered = false
        private var pointerStart: NSPoint?
        private var frameStart: NSRect?
        private var trackingArea: NSTrackingArea?
        private var modifierMonitor: Any?
        private var focusObservers: [NSObjectProtocol] = []
        private weak var trackedWindow: NSWindow?
        private var settingsPresented = false

        deinit { stopTrackingControl() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ensureTrackingWindow()
        }

        func ensureTrackingWindow() {
            guard let window else {
                if trackedWindow != nil || modifierMonitor != nil || !focusObservers.isEmpty {
                    stopTrackingControl()
                }
                return
            }
            guard trackedWindow !== window || modifierMonitor == nil else { return }
            stopTrackingControl()
            trackedWindow = window
            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) {
                [weak self, weak window] event in
                guard let self, let window,
                      !self.settingsPresented, NSApp.isActive, window.isVisible,
                      window.attachedSheet == nil,
                      (event.window === window || window.isKeyWindow || window.isMainWindow)
                else { return event }
                self.setControlHeld(event.modifierFlags.contains(.control))
                return event
            }
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.setControlHeld(false) })
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.refreshControlState() })
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification, object: window, queue: .main
            ) { [weak self] _ in self?.refreshControlState() })
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignMainNotification, object: window, queue: .main
            ) { [weak self] _ in self?.setControlHeld(false) })
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didEndSheetNotification, object: window, queue: .main
            ) { [weak self] _ in self?.refreshControlState(forceRedraw: true) })
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refreshControlState() })
            focusObservers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.setControlHeld(false) })
            refreshControlState()
        }

        func setSettingsPresented(_ presented: Bool) {
            guard settingsPresented != presented else { return }
            settingsPresented = presented
            if presented {
                setControlHeld(false, forceRedraw: true)
            } else {
                // The sheet may release key status after this SwiftUI update.
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.settingsPresented else { return }
                    self.ensureTrackingWindow()
                    self.refreshControlState(forceRedraw: true)
                }
            }
        }

        func stopTrackingControl() {
            if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
            modifierMonitor = nil
            focusObservers.forEach(NotificationCenter.default.removeObserver)
            focusObservers.removeAll()
            trackedWindow = nil
            setControlHeld(false)
        }

        private func refreshControlState(forceRedraw: Bool = false) {
            let active = !settingsPresented && NSApp.isActive && window?.isVisible == true &&
                window?.attachedSheet == nil &&
                (window?.isKeyWindow == true || window?.isMainWindow == true)
            setControlHeld(active && NSEvent.modifierFlags.contains(.control),
                           forceRedraw: forceRedraw)
        }

        private func setControlHeld(_ held: Bool, forceRedraw: Bool = false) {
            guard controlHeld != held || forceRedraw else { return }
            controlHeld = held
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let eventHasControl = NSApp.currentEvent?.modifierFlags.contains(.control) == true
            guard !settingsPresented || frameStart != nil,
                  controlHeld || eventHasControl || frameStart != nil else { return nil }
            return super.hitTest(point)
        }

        override func updateTrackingAreas() {
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways,
                                                .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
            super.updateTrackingAreas()
        }

        override func resetCursorRects() {
            if controlHeld && !settingsPresented {
                addCursorRect(bounds, cursor: .resizeLeftRight)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            hovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            hovered = false
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            beginResize(with: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            beginResize(with: event)
        }

        private func beginResize(with event: NSEvent) {
            guard !settingsPresented, event.modifierFlags.contains(.control),
                  let window = resizeWindow ?? self.window else { return }
            setControlHeld(true)
            pointerStart = window.convertPoint(toScreen: event.locationInWindow)
            frameStart = window.frame
        }

        override func mouseDragged(with event: NSEvent) {
            updateResize(with: event)
        }

        override func rightMouseDragged(with event: NSEvent) {
            updateResize(with: event)
        }

        private func updateResize(with event: NSEvent) {
            guard let window = resizeWindow ?? self.window,
                  let pointerStart, let frameStart else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            let dx = pointer.x - pointerStart.x
            let dy = pointerStart.y - pointer.y
            let delta = abs(dx) >= abs(dy) ? dx : dy
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let available = visible.map {
                min(850, $0.width, $0.height, $0.maxX - frameStart.minX,
                    frameStart.maxY - $0.minY)
            } ?? 850
            let side = min(max(240, available), max(240, frameStart.width + delta))
            window.setFrame(NSRect(x: frameStart.minX, y: frameStart.maxY - side,
                                   width: side, height: side), display: true)
        }

        override func mouseUp(with event: NSEvent) {
            finishResize()
        }

        override func rightMouseUp(with event: NSEvent) {
            finishResize()
        }

        private func finishResize() {
            if let window = resizeWindow ?? self.window, frameStart != nil {
                WindowConfigurator.saveFrame(window, borderless: true)
            }
            pointerStart = nil
            frameStart = nil
        }

        override func draw(_ dirtyRect: NSRect) {
            guard controlHeld && !settingsPresented else { return }
            NSColor.black.withAlphaComponent(hovered ? 0.48 : 0.27).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3),
                         xRadius: 8, yRadius: 8).fill()
            (hovered ? accent : NSColor.white.withAlphaComponent(0.85)).setStroke()
            let marks = NSBezierPath()
            marks.lineWidth = hovered ? 2 : 1.5
            marks.lineCapStyle = .round
            for offset in [9.0, 15.0, 21.0] {
                marks.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 6))
                marks.line(to: NSPoint(x: bounds.maxX - 6, y: bounds.minY + offset))
            }
            marks.stroke()
        }
    }
}

private struct UIColors {
    let background: Color
    let panel: Color
    let edge: Color
    let text: Color
    let secondary: Color

    init(_ appearance: CubeAppearance) {
        if appearance.body.luminance > 0.58 {
            background = Color(red: 0.84, green: 0.85, blue: 0.83)
            panel = Color.white.opacity(0.72)
            edge = Color.black.opacity(0.12)
            text = Color(red: 0.13, green: 0.17, blue: 0.19)
            secondary = Color(red: 0.40, green: 0.44, blue: 0.46)
        } else if appearance.body.blue > appearance.body.red * 1.35 &&
                    appearance.body.blue > appearance.body.green * 1.12 {
            background = Color(red: 0.045, green: 0.075, blue: 0.12)
            panel = Color(red: 0.085, green: 0.13, blue: 0.19)
            edge = Color.white.opacity(0.15)
            text = Color(red: 0.91, green: 0.95, blue: 1)
            secondary = Color(red: 0.56, green: 0.66, blue: 0.76)
        } else {
            background = Color(red: 0.055, green: 0.067, blue: 0.075)
            panel = Color(red: 0.102, green: 0.12, blue: 0.13)
            edge = Color.white.opacity(0.12)
            text = Color(red: 0.94, green: 0.96, blue: 0.95)
            secondary = Color(red: 0.56, green: 0.61, blue: 0.62)
        }
    }
}

private struct TimerView: View {
    @EnvironmentObject private var timer: TimerModel
    @EnvironmentObject private var appearance: AppearanceModel
    @Binding var showingSettings: Bool
    @State private var cubeSelectionTick = 0
    @State private var returnToDisplayTick = 0
    @State private var activeWindow: NSWindow?
    @State private var displayFaceReadable = true
    @State private var showBorderlessHint = false

    private var colors: UIColors { UIColors(appearance.value) }
    private var accent: Color { appearance.value.accent.swiftUIColor }
    private var accentInk: Color {
        appearance.value.accent.luminance > 0.48 ? .black : .white
    }
    private var countdownActionName: String {
        if timer.isRunning { return "Pause" }
        if timer.isPaused { return "Resume" }
        if timer.isComplete && timer.flowEnabled {
            return "Start \(timer.nextPhaseName?.lowercased() ?? "next phase")"
        }
        return "Start"
    }

    var body: some View {
        Group {
            if timer.borderlessWindow { borderlessContent }
            else { standardContent }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(timer)
                .environmentObject(appearance)
        }
        .preferredColorScheme(appearance.value.body.luminance > 0.58 ? .light : .dark)
        .task(id: timer.borderlessWindow) {
            guard timer.borderlessWindow else {
                showBorderlessHint = false
                return
            }
            showBorderlessHint = true
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { showBorderlessHint = false }
        }
    }

    private var standardContent: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 610 || geometry.size.width < 390
            let spacing: CGFloat = compact ? 6 : 12
            let verticalPadding: CGFloat = compact ? 12 : 20
            let fixedHeight: CGFloat = 30 + 13 + 20 + (compact ? 49 : 56)
                + (compact ? 47 : 52) + 12 + spacing * 8 + verticalPadding * 2
                + (timer.hasSuspendedPomodoro ? 15 : 0)
                + (timer.pendingFlowEnabled != nil ? 15 : 0)
                + (timer.canSkipBreak ? 15 : 0)
            let cubeHeight = min(510, max(160, geometry.size.height - fixedHeight))
            ZStack {
                colors.background.ignoresSafeArea()
                RadialGradient(colors: [accent.opacity(0.10), .clear],
                               center: .top, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()

                VStack(spacing: spacing) {
                    header
                    Spacer(minLength: 0)
                    status
                    cube(height: cubeHeight)
                    progress
                    Spacer(minLength: 0)
                    presetPicker(compact: compact)
                    controls(compact: compact)
                    footer
                }
                .frame(maxWidth: 610)
                .padding(.horizontal, compact ? 20 : 28)
                .padding(.top, verticalPadding)
                .padding(.bottom, verticalPadding)

                if let alert = timer.alertText {
                    VStack {
                        Spacer()
                        Label(alert, systemImage: "sparkle")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(accentInk)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(accent, in: Capsule())
                            .shadow(color: accent.opacity(0.4), radius: 16)
                            .padding(.bottom, compact ? 74 : 84)
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let label = timer.undoPresetLabel {
                    undoToast(label: label, borderless: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottom)
                        .padding(.bottom, compact ? 12 : 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: timer.alertText)
            .animation(.easeInOut(duration: 0.18), value: timer.undoPresetLabel)
        }
    }

    private var borderlessContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Ellipse()
                    .fill(Color.black.opacity(0.15 + appearance.value.lighting * 0.20))
                    .frame(width: geometry.size.width * 0.57,
                           height: geometry.size.height * 0.09)
                    .blur(radius: 12 + appearance.value.lighting * 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottom)
                    .padding(.bottom, geometry.size.height * 0.09)
                    .allowsHitTesting(false)
                cubeScene
                    .padding(geometry.size.width * 0.035)
                VStack(alignment: .leading, spacing: 4) {
                    if timer.isComplete || !displayFaceReadable {
                        borderlessReadout(size: geometry.size.width)
                            .transition(.opacity)
                    } else if timer.flowEnabled {
                        Text(timer.phase.displayLabel)
                            .font(.system(size: min(12, max(9, geometry.size.width * 0.032)),
                                          weight: .bold, design: .rounded))
                            .foregroundStyle(colors.text)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(colors.panel.opacity(0.92), in: Capsule())
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                    if let pending = timer.pendingFlowEnabled {
                        Text("POMO \(pending ? "ON" : "OFF") LATER")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.text)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(colors.panel.opacity(0.92), in: Capsule())
                            .help(timer.pendingModeDescription ?? "")
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                if timer.nextPhaseName != nil || timer.canSkipBreak {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let next = timer.nextPhaseName {
                            Button("Start \(next)") { timer.startNextPhase() }
                                .font(.system(size: min(10, max(8, geometry.size.width * 0.03)),
                                              weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(colors.panel.opacity(0.94), in: Capsule())
                                .buttonStyle(.plain)
                                .help("Start the next Pomodoro phase")
                                .accessibilityHidden(true)
                        }
                        if timer.canSkipBreak {
                            Button(timer.skipBreakName) { timer.skipBreak() }
                                .font(.system(size: min(10, max(8, geometry.size.width * 0.03)),
                                              weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(colors.panel.opacity(0.94), in: Capsule())
                                .buttonStyle(.plain)
                                .help("End the break and prepare Focus (Command-Shift-K)")
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
                    .padding(.top, (timer.isComplete || !displayFaceReadable)
                             ? (geometry.size.width < 320 ? 62 : 40) : 8)
                    .padding(.trailing, 8)
                } else if timer.hasSuspendedPomodoro {
                    Button("Resume Pomodoro") { timer.resumePomodoro() }
                        .font(.system(size: min(10, max(8, geometry.size.width * 0.03)),
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(colors.panel.opacity(0.94), in: Capsule())
                        .buttonStyle(.plain)
                        .help("Resume the paused Pomodoro phase (Command-Shift-P)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                        .padding(8)
                        .accessibilityHidden(true)
                }
                if let alert = timer.alertText {
                    Text(alert)
                        .font(.system(size: min(12, max(9, geometry.size.width * 0.035)),
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(colors.panel.opacity(0.92), in: Capsule())
                        .frame(maxWidth: geometry.size.width - 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 7)
                        .allowsHitTesting(false)
                }
                if let label = timer.undoPresetLabel {
                    undoToast(label: label, borderless: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                        .padding(.leading, 8)
                        .padding(.trailing, 44)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
                if showBorderlessHint && timer.alertText == nil &&
                    timer.undoPresetLabel == nil && !showingSettings {
                    Text("Control-drag cube to move\nControl-drag corner to resize")
                        .font(.system(size: min(11, max(9, geometry.size.width * 0.03)),
                                      weight: .medium, design: .rounded))
                        .foregroundStyle(colors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(colors.panel.opacity(0.90),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .frame(maxWidth: geometry.size.width - 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottom)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                BorderlessResizeGrip(window: activeWindow,
                                     accent: appearance.value.accent.nsColor,
                                     settingsPresented: showingSettings)
                    .frame(width: 36, height: 36)
                    .padding(4)
            }
            .animation(.easeInOut(duration: 0.18), value: displayFaceReadable)
            .animation(.easeInOut(duration: 0.18), value: showBorderlessHint)
            .animation(.easeInOut(duration: 0.18), value: timer.undoPresetLabel)
        }
        .background(Color.clear)
        .background(WindowReference { window in
            if activeWindow !== window { activeWindow = window }
        })
    }

    private func borderlessReadout(size: CGFloat) -> some View {
        let state = timer.isComplete ? "DONE" : timer.isRunning ? "RUNNING" :
            timer.isPaused ? "PAUSED" : "READY"
        let label = timer.flowEnabled
            ? "\(timer.phase.displayLabel) · \(timer.focusProgressLabel) · \(state)"
            : timer.hasSuspendedPomodoro ? "ONE-OFF · \(timer.focusProgressLabel) · \(state)"
            : state
        let compact = size < 320
        let visibleLabel = compact
            ? (timer.flowEnabled ? "\(timer.phase.displayLabel) · \(state)"
               : timer.hasSuspendedPomodoro ? "ONE-OFF · \(state)" : state)
            : label
        return HStack(spacing: 4) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 2) {
                        readoutTime(size: size)
                        readoutStatus(visibleLabel, size: size)
                    }
                } else {
                    HStack(spacing: 6) {
                        readoutTime(size: size)
                        readoutStatus(visibleLabel, size: size)
                    }
                }
            }
            .foregroundStyle(colors.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(colors.panel.opacity(0.92), in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            if !displayFaceReadable {
                returnToTimerFaceButton
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: size - 16, alignment: .leading)
    }

    private func readoutTime(size: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(timer.isComplete || timer.isRunning ? accent : colors.secondary)
                .frame(width: 5, height: 5)
            Text(timer.timeLabel)
                .font(.system(size: min(19, max(12, size * 0.045)),
                              weight: .heavy, design: .monospaced))
                .monospacedDigit()
        }
    }

    private func readoutStatus(_ label: String, size: CGFloat) -> some View {
        Text(label)
            .font(.system(size: min(11, max(8, size * 0.027)),
                          weight: .semibold, design: .rounded))
            .foregroundStyle(colors.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func returnToTimerFace() {
        returnToDisplayTick &+= 1
    }

    private var returnToTimerFaceButton: some View {
        Button(action: returnToTimerFace) {
            Image(systemName: "viewfinder")
                .font(.system(size: timer.borderlessWindow ? 14 : 12,
                              weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: timer.borderlessWindow ? 28 : 21,
                       height: timer.borderlessWindow ? 28 : 21)
                .background(colors.panel.opacity(0.96),
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Return to Timer Face · keeps countdown")
        .accessibilityLabel("Return to Timer Face")
        .accessibilityHint("Rotates the cube back without changing the countdown")
    }

    private func undoToast(label: String, borderless: Bool) -> some View {
        HStack(spacing: 7) {
            Text("Replaced \(label)")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Button("Undo") { timer.undoPresetChange() }
                .fontWeight(.bold)
                .foregroundStyle(accent)
                .buttonStyle(.plain)
                .accessibilityLabel("Undo timer change")
                .accessibilityHint("Restores the previous timer and Pomodoro state")
        }
        .font(.system(size: borderless ? 10 : 12, weight: .medium, design: .rounded))
        .foregroundStyle(colors.text)
        .padding(.horizontal, borderless ? 8 : 12)
        .padding(.vertical, borderless ? 6 : 8)
        .background(colors.panel.opacity(0.96), in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityHidden(borderless)
    }

    private var cubeAccessibilityControls: some View {
        VStack {
            Button {
                timer.startOrPause()
            } label: {
                Text("\(countdownActionName) countdown")
            }
            .accessibilityValue(timer.accessibilityValue)
            .accessibilityHint("Starts, pauses, or resumes without resetting paused time")

            ForEach(TimerModel.presetNames.indices, id: \.self) { index in
                Button("Start \(TimerModel.spokenPresetName(index))") {
                    cubeSelectionTick &+= 1
                    timer.selectAndStartPreset(index)
                }
                .accessibilityValue(TimerEngine.spokenDuration(
                    TimeInterval(timer.presetSeconds[index])))
                .accessibilityHint(timer.flowEnabled && timer.longBreakDue
                    ? "Starts a one-off timer while keeping the long break due. Resume Pomodoro to return."
                    : timer.isRunning || timer.isPaused
                        ? (timer.presetBecomesOneOff(index)
                            ? "Pauses Pomodoro, preserving its remaining time, and starts a one-off timer."
                            : "Replaces the current session and starts this preset from its full duration. Undo is available for six seconds.")
                        : "Selects this preset and starts a fresh countdown")
                .accessibilityAddTraits(timer.selectedPreset == index &&
                    !(timer.flowEnabled && timer.phase == .longBreak) ? .isSelected : [])
            }

            if timer.borderlessWindow && timer.undoPresetLabel != nil {
                Button("Undo timer change") { timer.undoPresetChange() }
                    .accessibilityHint("Restores the previous timer and Pomodoro state")
            }

            if timer.borderlessWindow && !displayFaceReadable {
                Button("Return to Timer Face") { returnToTimerFace() }
                    .accessibilityHint("Rotates the cube back without changing the countdown")
            }

            if timer.borderlessWindow && timer.hasSuspendedPomodoro {
                Button("Resume Pomodoro") { timer.resumePomodoro() }
                    .accessibilityHint("Replaces the one-off timer and restores the paused Pomodoro phase")
            }

            if timer.borderlessWindow, let next = timer.nextPhaseName {
                Button("Start \(next)") { timer.startNextPhase() }
                    .accessibilityHint("Starts the next Pomodoro phase when you are ready")
            }

            if timer.borderlessWindow && timer.canSkipBreak {
                Button(timer.skipBreakName) { timer.skipBreak() }
                    .accessibilityHint("Ends this break and leaves Focus ready to start")
            }

            if timer.borderlessWindow {
                Button("Reset timer") { timer.reset() }
                Button("Settings") { showingSettings = true }
                Button("Borderless Window") {
                    timer.setBorderlessWindow(false)
                }
                .accessibilityValue("On")
                Button("Always on Top") { timer.alwaysOnTop.toggle() }
                    .accessibilityValue(timer.alwaysOnTop ? "On" : "Off")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "cube.fill")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("CUBE")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3)
                Text("TIMER")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(colors.secondary)
            }
            Spacer()
            Button { timer.alwaysOnTop.toggle() } label: {
                Image(systemName: timer.alwaysOnTop ? "pin.fill" : "pin")
                    .frame(width: 31, height: 30)
            }
            .help(timer.alwaysOnTop ? "Turn off Always on Top" : "Turn on Always on Top")
            .accessibilityLabel("Always on Top")
            .accessibilityValue(timer.alwaysOnTop ? "On" : "Off")
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 31, height: 30)
            }
            .help("Timer, appearance, window, and sound settings")
            .accessibilityLabel("Settings")
        }
        .buttonStyle(IconButtonStyle(colors: colors, accent: accent))
        .foregroundStyle(colors.text)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
            Circle()
                .fill(timer.isRunning ? accent : colors.secondary)
                .frame(width: 6, height: 6)
            Text(timer.hasSuspendedPomodoro ? "ONE-OFF / POMODORO PAUSED · \(timer.focusProgressLabel)" : timer.flowEnabled
                 ? "POMODORO / \(timer.phase.displayLabel) · \(timer.focusProgressLabel)\(timer.isComplete ? " COMPLETE" : "")"
                 : "COUNTDOWN / \(timer.isRunning ? "RUNNING" : timer.isPaused ? "PAUSED" : timer.isComplete ? "COMPLETE" : "READY")")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text(timer.timeLabel)
                .foregroundStyle(colors.text)
                .monospacedDigit()
                .accessibilityLabel("Time remaining \(timer.timeLabel)")
            if !displayFaceReadable {
                returnToTimerFaceButton
            }
        }
        if timer.hasSuspendedPomodoro || timer.pendingFlowEnabled != nil {
            if let pending = timer.pendingModeDescription {
                Text(pending)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if timer.hasSuspendedPomodoro {
                Button("RESUME POMODORO") { timer.resumePomodoro() }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .buttonStyle(.plain)
                    .help("Restore the paused Pomodoro phase (Command-Shift-P)")
            }
        }
        if timer.canSkipBreak {
            Button(timer.skipBreakName.uppercased()) { timer.skipBreak() }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .buttonStyle(.plain)
                .help("End the break and prepare Focus (Command-Shift-K)")
        }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(1.35)
        .foregroundStyle(colors.secondary)
    }

    private func cube(height: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.18 + appearance.value.lighting * 0.23))
                .frame(width: height * 0.64, height: height * 0.13)
                .blur(radius: 18 + appearance.value.lighting * 17)
                .offset(y: height * 0.36)
            cubeScene
        }
        .frame(height: height)
    }

    private var cubeScene: some View {
        CubeSceneView(selectedPreset: timer.selectedPreset,
                      presetSeconds: timer.presetSeconds,
                      timeLabel: timer.timeLabel,
                      progress: timer.progress,
                      appearance: appearance.value,
                      automaticReadableDigits: appearance.automaticReadableDigits,
                      completed: timer.isComplete,
                      interactive: true,
                      selectionTick: cubeSelectionTick,
                      returnToDisplayTick: returnToDisplayTick,
                      borderless: timer.borderlessWindow,
                      alwaysOnTop: timer.alwaysOnTop,
                      replacingActiveSession: timer.isRunning || timer.isPaused,
                      willSuspendPomodoro: timer.flowEnabled,
                      suspendEveryFace: timer.longBreakDue || timer.phase == .longBreak,
                      longBreakDue: timer.longBreakDue,
                      pomodoroSuspended: timer.hasSuspendedPomodoro,
                      displayAction: countdownActionName,
                      onDisplayClick: { timer.startOrPause() },
                      onOpenSettings: { showingSettings = true },
                      onToggleBorderless: {
                          timer.setBorderlessWindow(!timer.borderlessWindow)
                      },
                      onToggleAlwaysOnTop: { timer.alwaysOnTop.toggle() },
                      onReset: { timer.reset() },
                      focusMarks: timer.pomodoroModeEnabled
                          ? CubeFocusProgress(completed: timer.focusesInCycle,
                                              target: timer.cycleTarget) : nil,
                      sessionLabel: timer.flowEnabled ? timer.phase.displayLabel : nil,
                      nextPhaseName: timer.nextPhaseName,
                      onStartNextPhase: timer.nextPhaseName != nil
                          ? { timer.startNextPhase() } : nil,
                      onSkipBreak: timer.canSkipBreak ? { timer.skipBreak() } : nil,
                      skipBreakName: timer.skipBreakName,
                      onResumePomodoro: timer.hasSuspendedPomodoro
                          ? { timer.resumePomodoro() } : nil,
                      onDisplayReadableChange: { displayFaceReadable = $0 }) { index in
            cubeSelectionTick &+= 1
            timer.selectAndStartCubeFace(index)
        }
        .accessibilityRepresentation {
            cubeAccessibilityControls
        }
    }

    private var progress: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.edge)
                    Capsule().fill(accent)
                        .frame(width: geometry.size.width * timer.progress)
                }
            }
            .frame(height: 4)
            HStack {
                Text("\(Int(timer.progress * 100))% ELAPSED")
                Spacer()
                Text("\(TimerEngine.display(timer.total)) TOTAL")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(colors.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Progress \(Int(timer.progress * 100)) percent")
    }

    private func presetPicker(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 10) {
            ForEach(TimerModel.defaultDurations.indices, id: \.self) { index in
                let selected = timer.selectedPreset == index &&
                    !(timer.flowEnabled && timer.phase == .longBreak)
                Button {
                    if !selected { timer.selectPreset(index) }
                } label: {
                    VStack(spacing: 3) {
                        Text(TimerModel.presetNames[index])
                            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                        Text(TimerEngine.display(TimeInterval(timer.presetSeconds[index])))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(selected ? accent : colors.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 49 : 56)
                    .background(selected ? accent.opacity(0.12) : colors.panel,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? accent.opacity(0.8) : colors.edge)
                    }
                    .foregroundStyle(selected ? accent : colors.text)
                }
                .buttonStyle(.plain)
                .help(selected
                    ? "Current preset. Clicking this button does not restart it."
                    : timer.flowEnabled && timer.longBreakDue
                        ? "Select without starting. Your long break stays due until resumed or skipped."
                    : timer.presetBecomesOneOff(index)
                        ? "Select without starting. Pauses Pomodoro and preserves its remaining time."
                    : timer.isRunning || timer.isPaused
                        ? "Select without starting. Replaces the current session; Undo is available for six seconds."
                        : "Select without starting. Press Start when ready.")
                .accessibilityLabel("\(TimerModel.presetNames[index]) preset, \(TimerEngine.display(TimeInterval(timer.presetSeconds[index])))")
                .accessibilityHint(selected
                    ? "Current preset. Clicking this button does not restart it."
                    : timer.flowEnabled && timer.longBreakDue
                        ? "Selects a one-off timer without starting. Your long break stays due until resumed or skipped."
                    : timer.presetBecomesOneOff(index)
                        ? "Pauses Pomodoro, preserving its remaining time, and selects a one-off timer without starting."
                    : timer.isRunning || timer.isPaused
                        ? "Selects without starting and replaces the current session. Undo is available for six seconds."
                        : "Selects this preset without starting its countdown. Press Start when ready.")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: 10) {
            Button { timer.startOrPause() } label: {
                Label(timer.isRunning ? "PAUSE" : timer.isPaused ? "RESUME" :
                      timer.isComplete && timer.flowEnabled
                          ? "START \(timer.nextPhaseName?.uppercased() ?? "NEXT")" : "START",
                      systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 47 : 52)
            }
            .buttonStyle(PrimaryButtonStyle(accent: accent, foreground: accentInk))
            Button { timer.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 53, height: compact ? 47 : 52)
            }
            .buttonStyle(SecondaryButtonStyle(colors: colors))
            .help("Reset")
            .accessibilityLabel("Reset timer")
        }
    }

    private var footer: some View {
        HStack {
            Text("DRAG TO ORBIT  ·  CLICK A FACE")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Image(systemName: timer.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .help(timer.muted ? "Sound muted" : "Sound on")
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(colors.secondary)
    }
}

private struct IconButtonStyle: ButtonStyle {
    let colors: UIColors
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? accent : colors.secondary)
            .background(colors.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let accent: Color
    let foreground: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(foreground)
            .background(accent.opacity(configuration.isPressed ? 0.78 : 1),
                        in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    let colors: UIColors
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(colors.text)
            .background(colors.panel, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(colors.edge) }
    }
}

private struct SettingsView: View {
    private enum Tab: String, CaseIterable {
        case timer = "Timer", appearance = "Appearance", window = "Window", sound = "Sound"
    }
    @EnvironmentObject private var timer: TimerModel
    @EnvironmentObject private var appearance: AppearanceModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .timer
    @State private var minutes = TimerModel.defaultDurations.map { $0 / 60 }
    @State private var seconds = TimerModel.defaultDurations.map { $0 % 60 }
    @State private var longBreakMinutes = 15
    @State private var longBreakSeconds = 0
    @State private var cycleTargetSelection = 4

    private var colors: UIColors { UIColors(appearance.value) }
    private var accent: Color { appearance.value.accent.swiftUIColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SETTINGS")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                    Text("Shape your time and your cube.")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.secondary)
                }
                Spacer()
                Button("Done") { savePresets(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Picker("Settings section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .timer: timerSettings
                    case .appearance: appearanceSettings
                    case .window: windowSettings
                    case .sound: soundSettings
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            }
            .id(tab)
        }
        .padding(23)
        .frame(width: 440, height: 640)
        .background(colors.background)
        .foregroundStyle(colors.text)
        .preferredColorScheme(appearance.value.body.luminance > 0.58 ? .light : .dark)
        .onAppear {
            minutes = timer.presetSeconds.map { $0 / 60 }
            seconds = timer.presetSeconds.map { $0 % 60 }
            longBreakMinutes = timer.longBreakSeconds / 60
            longBreakSeconds = timer.longBreakSeconds % 60
            cycleTargetSelection = timer.requestedCycleTarget
        }
    }

    private var timerSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TIMER & POMODORO")
            Toggle("Auto-cycle focus and break", isOn: Binding(
                get: { timer.requestedFlowEnabled }, set: { timer.setFlowEnabled($0) }
            ))
            .toggleStyle(.switch)
            helper(timer.pendingModeDescription ??
                   "Uses the focus and short-break presets. Mode changes wait for the current timer to finish.")
            Toggle("Automatically start next phase", isOn: $timer.autoStartNextPhase)
                .toggleStyle(.switch)
            helper("Starts the next phase on time; after a missed boundary, press Start. Skipping a break prepares Focus.")
            Stepper(value: $cycleTargetSelection, in: 2...8) {
                Text("Focuses before long break: \(cycleTargetSelection)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            helper(cycleTargetDescription)
            Text("\(timer.completedFocusTotal) completed focuses · \(timer.focusProgressLabel) toward long break")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.secondary)
            if timer.hasSuspendedPomodoro {
                helper("Pomodoro is paused behind a one-off timer. Resume it from the window or Command-Shift-P. Turning Pomodoro off after this timer ends will discard the paused phase; Undo is available for six seconds.")
            }
            Divider().padding(.vertical, 3)
            sectionTitle("PRESETS & LONG BREAK")
            ForEach(TimerModel.defaultDurations.indices, id: \.self) { index in
                durationRow(TimerModel.presetNames[index] + " preset",
                            minutes: $minutes[index], seconds: $seconds[index])
            }
            durationRow("Long break", minutes: $longBreakMinutes,
                        seconds: $longBreakSeconds)
            helper("Durations: 00:01–99:59. Press Done to save these edits and the cycle target.")
        }
    }

    private var soundSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("SOUND & ALERTS")
            Toggle("Mute sound", isOn: $timer.muted).toggleStyle(.switch)
            HStack {
                Text("In-app volume")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Slider(value: $timer.volume, in: 0...1)
                    .disabled(timer.muted)
                    .accessibilityLabel("In-app sound volume")
                    .accessibilityValue("\(Int(timer.volume * 100)) percent")
                Text("\(Int(timer.volume * 100))%")
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(colors.secondary)
            helper("Mute silences the alarm and cube face thud. This slider adjusts sounds played by the app. macOS controls notification sound when the app is hidden or closed. A visual alert always appears.")
        }
    }

    private var windowSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("WINDOW")
            Toggle("Borderless Window", isOn: Binding(
                get: { timer.borderlessWindow },
                set: { timer.setBorderlessWindow($0) }
            ))
                .toggleStyle(.switch)
            Toggle("Always on Top", isOn: $timer.alwaysOnTop)
                .toggleStyle(.switch)
            helper("Standard window: drag an edge or corner to resize. Borderless window: Control-drag the cube to move it; hold Control and drag the lower-right grip to resize. Control-click or right-click the cube for its menu. The time stays visible when its face turns away.")
        }
    }

    private var cycleTargetDescription: String {
        if cycleTargetSelection != timer.requestedCycleTarget {
            return "Current cycle: \(timer.cycleTarget). Selected target: \(cycleTargetSelection). Press Done to save; an active cycle keeps its current target."
        }
        if timer.cycleTargetChangePending {
            return "Current cycle: \(timer.cycleTarget). Next cycle: \(timer.requestedCycleTarget)."
        }
        return "Current cycle: \(timer.cycleTarget). Changes during a cycle apply after its long break ends or is skipped."
    }

    private func durationRow(_ name: String, minutes: Binding<Int>,
                             seconds: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 8)
            TextField("min", value: minutes, format: .number)
                .frame(width: 43)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(name) minutes")
            Text("m").accessibilityHidden(true)
            TextField("sec", value: seconds, format: .number)
                .frame(width: 43)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(name) seconds")
            Text("s").accessibilityHidden(true)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(colors.panel, in: RoundedRectangle(cornerRadius: 9))
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            CubeSceneView(selectedPreset: timer.selectedPreset,
                          presetSeconds: timer.presetSeconds,
                          timeLabel: timer.timeLabel,
                          progress: timer.progress,
                          appearance: appearance.value,
                          automaticReadableDigits: appearance.automaticReadableDigits,
                          completed: false, interactive: false,
                          selectionTick: 0, returnToDisplayTick: 0, borderless: false,
                          alwaysOnTop: timer.alwaysOnTop,
                          replacingActiveSession: false, displayAction: "Start",
                          onDisplayClick: {}, onOpenSettings: {},
                          onToggleBorderless: {}, onToggleAlwaysOnTop: {},
                          onReset: {},
                          onSelect: { _ in })
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(colors.panel, in: RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .accessibilityLabel("Live cube appearance preview")
            sectionTitle("COORDINATED STYLES")
            HStack(spacing: 8) {
                ForEach([CubeTheme.dark, .light, .midnight]) { theme in
                    let preset = CubeAppearance.preset(theme)
                    Button { appearance.setTheme(theme) } label: {
                        HStack(spacing: 7) {
                            Circle().fill(preset.body.swiftUIColor)
                                .frame(width: 15, height: 15)
                                .overlay { Circle().strokeBorder(preset.accent.swiftUIColor, lineWidth: 2) }
                            Text(theme.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 37)
                        .background(appearance.value.theme == theme ? accent.opacity(0.16) : colors.panel,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(appearance.value.theme == theme ? accent : colors.edge)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(appearance.value.theme == theme ? "Selected" : "Not selected")
                    .accessibilityHint("Applies this coordinated cube appearance")
                }
            }
            if appearance.value.theme == .custom {
                helper("Custom style — select a coordinated style to restore its colors.")
            }
            Divider().padding(.vertical, 1)
            sectionTitle("SURFACE FINISH")
            Picker("Finish", selection: Binding(
                get: { appearance.value.finish },
                set: { appearance.setFinish($0) }
            )) {
                ForEach(CubeFinish.allCases) { finish in
                    Text(finish.rawValue).tag(finish)
                }
            }
            .pickerStyle(.segmented)
            Divider().padding(.vertical, 1)
            sectionTitle("COLORS")
            ColorPicker("Cube body", selection: colorBinding(\.body, setter: appearance.setBody))
            ColorPicker("Progress accent", selection: colorBinding(\.accent, setter: appearance.setAccent))
            ColorPicker("Display digits", selection: colorBinding(\.display, setter: appearance.setDisplay))
            Toggle("Automatic readable digits", isOn: Binding(
                get: { appearance.automaticReadableDigits },
                set: { appearance.setAutomaticReadableDigits($0) }
            ))
                .toggleStyle(.switch)
                .accessibilityHint("Brightens low-contrast digits on the cube without changing the saved color")
            helper("Auto brightens only the rendered digits. Your chosen color stays saved.")
            if DisplayContrast.ratio(appearance.value.display) <
                DisplayContrast.minimumDigitRatio {
                if appearance.automaticReadableDigits {
                    helper("Digit color is being brightened for readability.")
                } else {
                    contrastWarning("Digit color may blend into the dark display.")
                }
            }
            if appearance.value.theme == .custom &&
                DisplayContrast.ratio(appearance.value.accent) <
                    DisplayContrast.minimumRingRatio {
                contrastWarning("Progress accent may be hard to see on the dark display.")
            }
            Divider().padding(.vertical, 1)
            sectionTitle("LIGHTING & SHADOW")
            HStack {
                Text("Intensity")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Slider(value: Binding(
                    get: { appearance.value.lighting },
                    set: { appearance.setLighting($0) }
                ), in: 0...1)
                .accessibilityLabel("Lighting and shadow intensity")
                .accessibilityValue("\(Int(appearance.value.lighting * 100)) percent")
                Text("\(Int(appearance.value.lighting * 100))%")
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(colors.secondary)
        }
    }

    private func colorBinding(_ keyPath: KeyPath<CubeAppearance, RGBColor>,
                              setter: @escaping (RGBColor) -> Void) -> Binding<Color> {
        Binding(get: { appearance.value[keyPath: keyPath].swiftUIColor },
                set: { setter(RGBColor(NSColor($0))) })
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(accent)
            .accessibilityAddTraits(.isHeader)
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func contrastWarning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func savePresets() {
        for index in TimerModel.defaultDurations.indices {
            let minute = min(99, max(0, minutes[index]))
            let second = min(59, max(0, seconds[index]))
            timer.setPreset(index, seconds: minute * 60 + second)
        }
        let minute = min(99, max(0, longBreakMinutes))
        let second = min(59, max(0, longBreakSeconds))
        timer.setLongBreak(seconds: minute * 60 + second)
        timer.setCycleTarget(cycleTargetSelection)
    }
}
