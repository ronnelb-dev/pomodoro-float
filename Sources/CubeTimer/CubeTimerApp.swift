import AppKit
import SwiftUI

@main
struct CubeTimerApp: App {
    @NSApplicationDelegateAdaptor(TimerApplicationDelegate.self) private var appDelegate
    @StateObject private var timer = TimerModel()
    @StateObject private var appearance = AppearanceModel()
    @State private var showingSettings = false
    @State private var showingCustomCountdown = false

    var body: some Scene {
        WindowGroup("Pomodoro Float", id: TimerApplicationDelegate.timerWindowSceneID) {
            TimerView(showingSettings: $showingSettings,
                      showingCustomCountdown: $showingCustomCountdown)
                .environmentObject(timer)
                .environmentObject(appearance)
                .background(WindowConfigurator(alwaysOnTop: timer.alwaysOnTop,
                                               borderless: timer.borderlessWindow,
                                               fullscreenTransitionActive:
                                                   timer.isPreparingDisplayFullscreen ||
                                                   timer.isDisplayFullscreen))
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
                if timer.isDisplayFullscreen {
                    Button("Exit \(timer.displayStyle.fullscreenTitle)") {
                        NotificationCenter.default.post(
                            name: .cubeTimerDisplayFullscreenExitRequested, object: nil)
                    }
                    .keyboardShortcut(.cancelAction)
                } else if timer.isPreparingDisplayFullscreen {
                    Button("Entering Full Screen…") {}
                        .disabled(true)
                } else if timer.displayStyle.supportsFullscreen {
                    Button(timer.displayStyle.fullscreenTitle) {
                        NotificationCenter.default.post(
                            name: .cubeTimerDisplayFullscreenEntryRequested, object: nil)
                    }
                }
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
                ForEach(timer.presetNames.indices, id: \.self) { index in
                    Button("Start \(timer.presetNames[index]) Preset") {
                        timer.selectAndStartPreset(index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                      modifiers: .command)
                }
                Divider()
                Button("Countdown…") { showingCustomCountdown = true }
                Button("Start Stopwatch") { timer.startStopwatch() }
                Divider()
                Button("Settings…") { showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Borderless Window") {
                    timer.setBorderlessWindow(!timer.borderlessWindow)
                }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(timer.isDisplayFullscreen || timer.isPreparingDisplayFullscreen)
                Button("Always on Top") { timer.alwaysOnTop.toggle() }
            }
            TimerHelpCommands()
        }

        Window("Pomodoro Float Help", id: TimerApplicationDelegate.helpWindowSceneID) {
            TimerHelpView()
        }
        .defaultSize(width: 540, height: 620)

        MenuBarExtra(isInserted: Binding(
            get: { timer.showMenuBarTimer },
            set: { timer.setShowMenuBarTimer($0) }
        )) {
            MenuBarTimerMenu()
                .environmentObject(timer)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: MenuBarTimerIndicator.systemImage(
                    isRunning: timer.isRunning, isPaused: timer.isPaused,
                    isComplete: timer.isComplete))
                Text(timer.timeLabel).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pomodoro Float, \(timer.accessibilityValue)")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let alwaysOnTop: Bool
    let borderless: Bool
    let fullscreenTransitionActive: Bool
    private struct FrameSnapshot {
        let frame: NSRect
        let borderless: Bool
    }

    final class Coordinator: NSObject {
        weak var configuredWindow: NSWindow?
        var observers: [NSObjectProtocol] = []
        var appliedBorderless: Bool?
        var isSwitchingMode = false
        var standardStyleMask: NSWindow.StyleMask?
        private var frameBeforeZoom: NSRect?
        private var zoomedFrame: NSRect?
        private lazy var frameSaveScheduler = WindowFrameSaveScheduler<FrameSnapshot> { snapshot in
            WindowConfigurator.saveFrame(snapshot.frame, borderless: snapshot.borderless)
        }

        func scheduleFrameSave(_ frame: NSRect, borderless: Bool) {
            frameSaveScheduler.schedule(FrameSnapshot(frame: frame, borderless: borderless))
        }

        func flushFrameSave() {
            frameSaveScheduler.flush()
        }

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
                coordinator.flushFrameSave()
                coordinator.observers.forEach(NotificationCenter.default.removeObserver)
                coordinator.observers.removeAll()
                coordinator.configuredWindow = window
                window.identifier = TimerApplicationDelegate.timerWindowIdentifier
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
                                   : !StandardWindowPosition.isBelowMinimum(frame) else { return }
                        if mode {
                            Self.saveFrame(window, borderless: true)
                        } else {
                            coordinator.scheduleFrameSave(frame, borderless: false)
                        }
                    })
                }
                coordinator.observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main
                ) { [weak coordinator] _ in
                    coordinator?.flushFrameSave()
                })
                coordinator.observers.append(NotificationCenter.default.addObserver(
                    forName: .cubeTimerWillChangeWindowMode, object: nil, queue: nil
                ) { [weak window, weak coordinator] _ in
                    guard let window, let coordinator,
                          let mode = coordinator.appliedBorderless else { return }
                    coordinator.flushFrameSave()
                    coordinator.isSwitchingMode = true
                    Self.saveFrame(window, borderless: mode)
                })
            }
            let modeDidChange = coordinator.appliedBorderless != borderless
            if modeDidChange {
                coordinator.flushFrameSave()
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
            if !borderless && !window.styleMask.contains(.fullScreen) &&
                StandardWindowPosition.isBelowMinimum(window.frame) {
                let frame = StandardWindowPosition.restoredFrame(
                    window.frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
                window.setFrame(frame, display: true)
                Self.saveFrame(frame, borderless: false)
            }
            if !borderless, let zoom = window.standardWindowButton(.zoomButton) {
                zoom.target = coordinator
                zoom.action = #selector(Coordinator.toggleZoom(_:))
            }
            window.level = TimerWindowLevelPolicy.shouldFloat(
                alwaysOnTop: alwaysOnTop,
                isFullscreen: window.styleMask.contains(.fullScreen),
                fullscreenTransitionActive: fullscreenTransitionActive) ? .floating : .normal
            if borderless {
                window.collectionBehavior.remove(.fullScreenPrimary)
                if alwaysOnTop && !fullscreenTransitionActive {
                    window.collectionBehavior.insert(.canJoinAllSpaces)
                    window.collectionBehavior.insert(.fullScreenAuxiliary)
                } else {
                    window.collectionBehavior.remove(.canJoinAllSpaces)
                    window.collectionBehavior.remove(.fullScreenAuxiliary)
                }
            } else {
                window.collectionBehavior.remove(.fullScreenAuxiliary)
                window.collectionBehavior.remove(.fullScreenNone)
                window.collectionBehavior.insert(.fullScreenPrimary)
                if alwaysOnTop && !fullscreenTransitionActive {
                    window.collectionBehavior.insert(.canJoinAllSpaces)
                } else {
                    window.collectionBehavior.remove(.canJoinAllSpaces)
                }
            }
            if modeDidChange {
                NotificationCenter.default.post(name: .cubeTimerWindowModeDidChange,
                                                object: window)
            }
        }
    }

    fileprivate static func saveFrame(_ window: NSWindow, borderless: Bool) {
        saveFrame(window.frame, borderless: borderless)
    }

    fileprivate static func saveFrame(_ frame: NSRect, borderless: Bool) {
        UserDefaults.standard.set(NSStringFromRect(frame),
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
        if borderless {
            window.aspectRatio = NSSize(width: 1, height: 1)
        } else {
            // AppKit 27 can produce a NaN frame during native edge tiling if the
            // aspect ratio is cleared with .zero. A 1×1 resize increment clears
            // the previous ratio and leaves standard resizing unconstrained.
            window.resizeIncrements = NSSize(width: 1, height: 1)
        }
        window.minSize = borderless
            ? NSSize(width: BorderlessWindowPosition.minimumSide,
                     height: BorderlessWindowPosition.minimumSide)
            : TimerWindowLayout.standardMinimumSize
        window.maxSize = borderless
            ? NSSize(width: BorderlessWindowPosition.maximumSide,
                     height: BorderlessWindowPosition.maximumSide)
            : TimerWindowLayout.standardMaximumSize
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
        return StandardWindowPosition.restoredFrame(
            frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
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
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let frame = BorderlessWindowPosition.resizedFrame(
                start: frameStart, horizontalDelta: dx, verticalDelta: dy,
                visibleFrame: visible)
            window.setFrame(frame, display: true)
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

struct UIColors {
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

private struct BorderlessWindowMoveMonitor: NSViewRepresentable {
    let window: NSWindow?
    let enabled: Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.moveWindow = window
        view.setEnabled(enabled)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.moveWindow = window
        view.setEnabled(enabled)
        view.ensureEventMonitor()
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stopEventMonitor()
    }

    final class MonitorView: NSView {
        weak var moveWindow: NSWindow?
        private weak var monitoredWindow: NSWindow?
        private var eventMonitor: Any?
        private var gesture = BorderlessWindowMoveGesture()
        private var isEnabled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ensureEventMonitor()
        }

        func setEnabled(_ enabled: Bool) {
            guard isEnabled != enabled else { return }
            isEnabled = enabled
            if enabled {
                ensureEventMonitor()
            } else {
                stopEventMonitor()
            }
        }

        func ensureEventMonitor() {
            guard isEnabled, let window = moveWindow ?? self.window else {
                stopEventMonitor()
                return
            }
            guard eventMonitor == nil || monitoredWindow !== window else { return }
            stopEventMonitor()
            moveWindow = window
            monitoredWindow = window
            let events: NSEvent.EventTypeMask = [
                .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                .rightMouseDown, .rightMouseDragged, .rightMouseUp
            ]
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
                [weak self, weak window] event in
                guard let self, let window, self.isEnabled,
                      NSApp.isActive, window.isVisible, window.attachedSheet == nil else {
                    return event
                }
                let isMouseDown = event.type == .leftMouseDown ||
                    event.type == .rightMouseDown
                guard event.window === window || (!isMouseDown && self.gesture.isTracking)
                else { return event }
                return self.handle(event, in: window)
            }
        }

        func stopEventMonitor() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            monitoredWindow = nil
            gesture.reset()
        }

        private func handle(_ event: NSEvent, in window: NSWindow) -> NSEvent? {
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                let isResizeGrip = window.contentView.map {
                    BorderlessWindowMoveGesture.hitsResizeGrip(
                        event.locationInWindow, contentBounds: $0.bounds)
                } ?? false
                let controlHeld = BorderlessWindowMoveGesture.shouldBegin(
                    controlInEvent: event.modifierFlags.contains(.control),
                    controlCurrentlyHeld: NSEvent.modifierFlags.contains(.control))
                guard controlHeld && !isResizeGrip else {
                    gesture.reset()
                    return event
                }
                gesture.begin(pointer: NSEvent.mouseLocation,
                              frame: window.frame,
                              moveIntent: true)
                // Keep AppKit/SwiftUI from treating Control-click as a context-menu request.
                return nil
            case .leftMouseDragged, .rightMouseDragged:
                guard gesture.isTracking else { return event }
                guard let origin = gesture.proposedOrigin(
                    pointer: NSEvent.mouseLocation,
                    size: window.frame.size,
                    visibleFrames: NSScreen.screens.map(\.visibleFrame)) else { return nil }
                window.setFrameOrigin(origin)
                return nil
            case .leftMouseUp, .rightMouseUp:
                guard gesture.isTracking else { return event }
                gesture.reset()
                return nil
            default:
                return event
            }
        }

        deinit { stopEventMonitor() }
    }
}

private struct TimerView: View {
    @EnvironmentObject private var timer: TimerModel
    @EnvironmentObject private var appearance: AppearanceModel
    @Binding var showingSettings: Bool
    @Binding var showingCustomCountdown: Bool
    @State private var cubeSelectionTick = 0
    @State private var returnToDisplayTick = 0
    @State private var activeWindow: NSWindow?
    @State private var pendingDisplayFullscreenEntry = false
    @State private var displayFullscreenEntryToggleRequested = false
    @State private var displayFullscreenToggleScheduled = false
    @State private var fullscreenPromotionAttempts = 0
    @State private var isInNativeFullscreen = false
    @State private var showFullscreenExitHint = false
    @State private var displayFaceReadable = true
    @State private var showBorderlessHint = false
    @State private var isHoveringFloatingAction = false
    @AppStorage("hasSeenFloatingCubeHint") private var hasSeenFloatingCubeHint = false

    private var colors: UIColors { UIColors(appearance.value) }
    private var accent: Color { appearance.value.accent.swiftUIColor }
    private var accentInk: Color {
        appearance.value.accent.luminance > 0.48 ? .black : .white
    }
    private var displayWindow: NSWindow? {
        activeWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ??
            NSApp.windows.first { $0.identifier == TimerApplicationDelegate.timerWindowIdentifier }
    }
    private var displayFullscreenPhase: DisplayFullscreenTransition.Phase {
        if isInNativeFullscreen || timer.isDisplayFullscreen { return .fullscreen }
        if timer.isPreparingDisplayFullscreen { return .preparing }
        return .windowed
    }
    private var countdownActionName: String {
        if timer.isRunning { return "Pause" }
        if timer.isPaused { return "Resume" }
        if timer.sessionKind == .stopwatch { return timer.isComplete ? "Restart" : "Start" }
        if timer.isComplete && timer.flowEnabled {
            return "Start \(timer.nextPhaseName?.lowercased() ?? "next phase")"
        }
        return "Start"
    }

    private var digitalPhaseLabel: String {
        if timer.sessionKind == .stopwatch { return "Stopwatch" }
        if timer.sessionKind == .customCountdown { return "Countdown" }
        if timer.flowEnabled { return timer.phase.displayName }
        return timer.hasSuspendedPomodoro ? "Pomodoro Paused" : "Countdown"
    }

    private var digitalStatusLabel: String {
        timer.isComplete ? (timer.sessionKind == .stopwatch ? "STOPPED" : "DONE") : timer.isRunning ? "RUNNING" :
            timer.isPaused ? "PAUSED" : "READY"
    }

    private var digitalFocusProgress: String? {
        timer.pomodoroModeEnabled || timer.hasSuspendedPomodoro
            ? timer.focusProgressLabel : nil
    }

    private var floatingHintText: String {
        if timer.displayStyle == .cube {
            return "Click timer: start or pause · Drag: rotate\nControl-drag to move · Corner grip to resize\nRight-click for timer controls"
        }
        if timer.displayStyle == .clock {
            return "Control-drag to move · Corner grip to resize\nRight-click for clock and timer controls"
        }
        return "Click timer: start or pause\nControl-drag to move · Corner grip to resize\nRight-click for presets and controls"
    }

    var body: some View {
        Group {
            if timer.borderlessWindow { borderlessContent }
            else { standardContent }
        }
        .task(id: showFullscreenExitHint) {
            guard showFullscreenExitHint else { return }
            do {
                try await Task.sleep(for: .seconds(DisplayFullscreenHint.durationSeconds))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                showFullscreenExitHint = false
            }
        }
        .background(WindowReference { window in
            guard let window, activeWindow !== window else { return }
            activeWindow = window
            isInNativeFullscreen = window.styleMask.contains(.fullScreen)
            attemptPendingDisplayFullscreenEntry()
            if isInNativeFullscreen {
                timer.didEnterDisplayFullscreen()
            }
        })
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(timer)
                .environmentObject(appearance)
        }
        .popover(isPresented: $showingCustomCountdown, arrowEdge: .bottom) {
            CustomCountdownPopover(initialSeconds: timer.sessionKind == .stopwatch
                ? timer.presetSeconds[timer.selectedPreset] : Int(timer.total),
                presetNames: timer.presetNames,
                initialPresetIndex: timer.selectedPreset,
                onStart: { seconds in
                    showingCustomCountdown = false
                    timer.startCustomCountdown(seconds: seconds)
                },
                onSavePreset: { index, seconds, name in
                    timer.savePreset(index, seconds: seconds, name: name)
                    showingCustomCountdown = false
                },
                onCancel: { showingCustomCountdown = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .cubeTimerWindowModeDidChange),
                   perform: handleWindowModeDidChange)
        .onChange(of: timer.borderlessWindow) { _, _ in
            // The window-mode controller updates the NSWindow after SwiftUI
            // observes this value. Wait for its did-change notification before
            // trying fullscreen so AppKit sees the restored standard style mask.
            schedulePendingDisplayFullscreenEntry()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .cubeTimerDisplayFullscreenExitRequested)) { _ in
                exitDisplayFullscreen()
            }
        .onReceive(NotificationCenter.default.publisher(
            for: .cubeTimerDisplayFullscreenEntryRequested)) { _ in
                toggleDisplayFullscreen()
            }
        .onChange(of: isInNativeFullscreen) { _, isFullscreen in
            withAnimation(.easeOut(duration: 0.2)) {
                showFullscreenExitHint = DisplayFullscreenHint.shouldShow(
                    displayStyle: timer.displayStyle, isFullscreen: isFullscreen)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification),
                   perform: handleWindowDidEnterFullscreen)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification),
                   perform: handleWindowDidExitFullscreen)
        .preferredColorScheme(appearance.value.body.luminance > 0.58 ? .light : .dark)
        .task(id: timer.borderlessWindow) {
            guard timer.borderlessWindow else {
                showBorderlessHint = false
                return
            }
            guard !hasSeenFloatingCubeHint else { return }
            showFloatingHelp()
        }
    }

    private var standardContent: some View {
        GeometryReader { geometry in
            let transientRows = (timer.hasSuspendedPomodoro ? 1 : 0)
                + (timer.pendingFlowEnabled != nil ? 1 : 0)
                + (timer.canSkipBreak ? 1 : 0)
            let horizontalPadding: CGFloat = geometry.size.height < 610 || geometry.size.width < 390
                ? 20 : 28
            let metrics = TimerWindowLayout.standardMetrics(
                size: geometry.size, transientRowCount: transientRows,
                expandsDigitalDisplay: timer.displayStyle == .digital)
            let immersiveCubeFullscreen = timer.displayStyle == .cube && isInNativeFullscreen
            let immersiveReadoutHeight = displayFaceReadable
                ? 0 : TimerWindowLayout.immersiveCubeReadoutHeight
            let immersiveReadoutSpacing = displayFaceReadable
                ? 0 : TimerWindowLayout.immersiveCubeReadoutSpacing
            let immersiveReservedHeight = metrics.verticalPadding * 2
                + TimerWindowLayout.immersiveCubeHeaderHeight
                + immersiveReadoutHeight + immersiveReadoutSpacing
            let immersiveCubeSide = TimerWindowLayout.immersiveCubeSide(
                availableSize: NSSize(width: geometry.size.width - horizontalPadding * 2,
                                      height: geometry.size.height),
                reservedHeight: immersiveReservedHeight)
            let availablePanelWidth = geometry.size.width - horizontalPadding * 2
            let digitalPanelWidth = TimerWindowLayout.digitalPanelWidth(
                availableWidth: availablePanelWidth)
            let contentMaxWidth = timer.displayStyle == .digital
                ? max(TimerWindowLayout.standardContentWidth, digitalPanelWidth)
                : TimerWindowLayout.standardContentWidth
            ZStack {
                colors.background.ignoresSafeArea()
                RadialGradient(colors: [accent.opacity(0.10), .clear],
                               center: .top, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()

                if immersiveCubeFullscreen {
                    VStack(spacing: 0) {
                        header(narrow: geometry.size.width < 390,
                               availableWidth: geometry.size.width - horizontalPadding * 2)
                            .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                            .frame(maxWidth: .infinity)
                            .frame(height: TimerWindowLayout.immersiveCubeHeaderHeight)
                        if !displayFaceReadable {
                            borderlessReadout(size: geometry.size.width)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: immersiveReadoutHeight,
                                       alignment: .topLeading)
                                .padding(.top, immersiveReadoutSpacing)
                        }
                        Spacer(minLength: 0)
                        cube(height: immersiveCubeSide)
                            .frame(width: immersiveCubeSide, height: immersiveCubeSide)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, metrics.verticalPadding)
                    .padding(.bottom, metrics.verticalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: metrics.spacing) {
                        header(narrow: geometry.size.width < 390,
                               availableWidth: availablePanelWidth)
                            .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                        if timer.displayStyle == .clock {
                            Spacer(minLength: 0)
                            deskClockPanel(compact: metrics.compact)
                                .frame(width: isInNativeFullscreen
                                       ? DeskClockLayout.fullscreenPanelWidth(
                                           availableWidth: geometry.size.width - horizontalPadding * 2)
                                       : TimerWindowLayout.standardClockPanelWidth(
                                           availableWidth: availablePanelWidth))
                                .frame(height: metrics.displayHeight)
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                            status
                                .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                            if timer.displayStyle == .cube {
                                cube(height: metrics.displayHeight)
                            } else {
                                digitalPanel(compact: metrics.compact)
                                    .frame(width: digitalPanelWidth,
                                           height: metrics.displayHeight)
                            }
                            if timer.sessionKind != .stopwatch {
                                progress
                                    .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                            }
                            Spacer(minLength: 0)
                            presetPicker(compact: metrics.compact)
                                .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                            timingModeButtons(compact: metrics.compact)
                                .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                            controls(compact: metrics.compact)
                                .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                            footer
                                .frame(maxWidth: TimerWindowLayout.standardContentWidth)
                        }
                    }
                    .frame(maxWidth: contentMaxWidth)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, metrics.verticalPadding)
                    .padding(.bottom, metrics.verticalPadding)
                }

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
                            .padding(.bottom, metrics.compact ? 74 : 84)
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let label = timer.undoPresetLabel {
                    undoToast(label: label, borderless: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottom)
                        .padding(.bottom, metrics.compact ? 12 : 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: timer.alertText)
            .animation(.easeInOut(duration: 0.18), value: timer.undoPresetLabel)
        }
        .overlay(alignment: .top) {
            if showFullscreenExitHint,
               DisplayFullscreenHint.shouldShow(displayStyle: timer.displayStyle,
                                                isFullscreen: isInNativeFullscreen) {
                fullscreenExitHint
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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
                if timer.displayStyle == .cube {
                    cubeScene
                        .padding(geometry.size.width * 0.035)
                    VStack(alignment: .leading, spacing: 4) {
                        if timer.isComplete || !displayFaceReadable {
                            borderlessReadout(size: geometry.size.width)
                                .transition(.opacity)
                        }
                        HStack(spacing: 4) {
                            if timer.flowEnabled {
                                floatingBadge(timer.phase.displayLabel, size: geometry.size.width)
                            }
                            if timer.pomodoroModeEnabled {
                                floatingBadge(timer.focusProgressLabel, size: geometry.size.width)
                                    .accessibilityLabel("Focus progress \(timer.focusProgressLabel)")
                            }
                        }
                        if let pending = timer.pendingFlowEnabled {
                            floatingBadge("POMO \(pending ? "ON" : "OFF") LATER",
                                          size: geometry.size.width)
                                .help(timer.pendingModeDescription ?? "")
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                } else if timer.displayStyle == .digital {
                    Button(action: timer.startOrPause) {
                        digitalPanel(compact: true)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(countdownActionName) \(timer.sessionKind == .stopwatch ? "stopwatch" : "countdown")")
                    .accessibilityValue(timer.accessibilityValue)
                    .help("Click to \(countdownActionName.lowercased()) timer")
                    .contextMenu { floatingContextMenu }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    deskClockPanel(compact: true)
                        .padding(12)
                        .contextMenu { floatingContextMenu }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if timer.displayStyle != .clock {
                    Button(action: timer.startOrPause) {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accentInk)
                            .frame(width: 30, height: 30)
                            .background(accent, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHoveringFloatingAction ? 1 : 0)
                    .allowsHitTesting(isHoveringFloatingAction)
                    .accessibilityLabel("\(countdownActionName) \(timer.sessionKind == .stopwatch ? "stopwatch" : "countdown")")
                    .accessibilityValue(timer.accessibilityValue)
                    .help("\(countdownActionName) countdown")
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
                    .padding(8)
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
                    Text(floatingHintText)
                        .font(.system(size: min(11, max(9, geometry.size.width * 0.03)),
                                      weight: .medium, design: .rounded))
                        .foregroundStyle(colors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
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
                if timer.displayStyle != .cube {
                    BorderlessWindowMoveMonitor(window: activeWindow,
                                                enabled: !showingSettings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: displayFaceReadable)
            .animation(.easeInOut(duration: 0.18), value: showBorderlessHint)
            .animation(.easeInOut(duration: 0.18), value: timer.undoPresetLabel)
            .onHover { isHoveringFloatingAction = $0 }
        }
        .background(Color.clear)
    }

    private func floatingBadge(_ label: String, size: CGFloat) -> some View {
        Text(label)
            .font(.system(size: min(10, max(8, size * 0.03)),
                          weight: .bold, design: .rounded))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(colors.panel.opacity(0.92), in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func digitalPanel(compact: Bool) -> some View {
        DigitalTimerPanel(timeLabel: timer.timeLabel,
                          phaseLabel: digitalPhaseLabel,
                          statusLabel: digitalStatusLabel,
                          focusProgress: digitalFocusProgress,
                          sessionNotice: compact ? timer.pendingModeDescription : nil,
                          progress: timer.progress,
                          showsProgress: timer.sessionKind != .stopwatch,
                          accent: accent,
                          colors: colors,
                          compact: compact)
    }

    private func deskClockPanel(compact: Bool) -> some View {
        DeskClockPanel(colors: colors, accent: accent, compact: compact,
                       use24HourTime: timer.use24HourTime)
    }

    private var fullscreenExitHint: some View {
        Text("Press Esc to exit full screen")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(colors.edge.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .accessibilityIdentifier("displayFullscreenExitHint")
            .allowsHitTesting(false)
    }

    private func exitDisplayFullscreen() {
        guard let window = displayWindow,
              DisplayFullscreenExitPolicy.shouldExit(
                  nativeFullscreen: window.styleMask.contains(.fullScreen),
                  modelFullscreen: timer.isDisplayFullscreen || isInNativeFullscreen) else { return }
        pendingDisplayFullscreenEntry = false
        displayFullscreenEntryToggleRequested = false
        fullscreenPromotionAttempts = 0
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.toggleFullScreen(nil)
        }
    }

    private func toggleDisplayFullscreen() {
        guard !timer.isPreparingDisplayFullscreen,
              !pendingDisplayFullscreenEntry,
              !displayFullscreenEntryToggleRequested,
              timer.displayStyle.supportsFullscreen,
              let window = displayWindow else { return }
        let entryAction = DisplayFullscreenTransition.toggleAction(
            supportsFullscreen: timer.displayStyle.supportsFullscreen,
            isNativeFullscreen: window.styleMask.contains(.fullScreen),
            isBorderless: timer.borderlessWindow)
        switch entryAction {
        case .reject:
            return
        case .exitFullscreen:
            exitDisplayFullscreen()
        case .toggleNow, .waitForStandardWindow:
            pendingDisplayFullscreenEntry = true
            displayFullscreenEntryToggleRequested = false
            fullscreenPromotionAttempts = 0
            guard timer.prepareForDisplayFullscreen() else {
                pendingDisplayFullscreenEntry = false
                return
            }
            window.level = .normal
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            if entryAction == .toggleNow {
                attemptPendingDisplayFullscreenEntry()
            }
            schedulePendingDisplayFullscreenEntry()
        }
    }

    private func handleWindowModeDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        attemptPendingDisplayFullscreenEntry(for: window)
        schedulePendingDisplayFullscreenEntry()
    }

    private func attemptPendingDisplayFullscreenEntry(for notifiedWindow: NSWindow? = nil) {
        guard pendingDisplayFullscreenEntry,
              !displayFullscreenEntryToggleRequested,
              let window = displayWindow,
              notifiedWindow == nil || notifiedWindow === window else { return }
        switch DisplayFullscreenTransition.modeChangeAction(
            pendingEntry: pendingDisplayFullscreenEntry,
            windowMatches: notifiedWindow == nil || notifiedWindow === window,
            isBorderless: timer.borderlessWindow) {
        case .ignore, .waitForStandardWindow:
            return
        case .toggleNow:
            guard !displayFullscreenToggleScheduled else { return }
            displayFullscreenToggleScheduled = true
            DispatchQueue.main.async { [weak window] in
                displayFullscreenToggleScheduled = false
                guard let window,
                      pendingDisplayFullscreenEntry,
                      !displayFullscreenEntryToggleRequested,
                      displayWindow === window,
                      !window.styleMask.contains(.fullScreen) else { return }
                guard !timer.borderlessWindow, window.styleMask.contains(.titled) else {
                    schedulePendingDisplayFullscreenEntry()
                    return
                }
                displayFullscreenEntryToggleRequested = true
                window.toggleFullScreen(nil)
            }
        }
    }

    private func schedulePendingDisplayFullscreenEntry() {
        guard pendingDisplayFullscreenEntry, !displayFullscreenEntryToggleRequested,
              !displayFullscreenToggleScheduled,
              fullscreenPromotionAttempts < 8 else { return }
        displayFullscreenToggleScheduled = true
        fullscreenPromotionAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            displayFullscreenToggleScheduled = false
            guard pendingDisplayFullscreenEntry,
                  !displayFullscreenEntryToggleRequested else { return }
            attemptPendingDisplayFullscreenEntry()
            if pendingDisplayFullscreenEntry {
                schedulePendingDisplayFullscreenEntry()
            }
        }
    }

    private func handleWindowDidEnterFullscreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === activeWindow,
              timer.displayStyle.supportsFullscreen else { return }
        pendingDisplayFullscreenEntry = false
        displayFullscreenEntryToggleRequested = false
        isInNativeFullscreen = true
        timer.didEnterDisplayFullscreen()
    }

    private func handleWindowDidExitFullscreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === activeWindow else { return }
        pendingDisplayFullscreenEntry = false
        displayFullscreenEntryToggleRequested = false
        isInNativeFullscreen = false
        timer.finishDisplayFullscreen()
    }

    @ViewBuilder
    private var floatingContextMenu: some View {
        Button("Cube Timer") { timer.displayStyle = .cube }
        Button("Digital Timer") { timer.displayStyle = .digital }
        Button("Desk Clock") { timer.displayStyle = .clock }
        Divider()
        if timer.displayStyle.supportsFullscreen {
            Button(timer.isPreparingDisplayFullscreen ? "Entering Full Screen…" :
                   (isInNativeFullscreen ? "Exit Full Screen" :
                    timer.displayStyle.fullscreenTitle)) { toggleDisplayFullscreen() }
                .disabled(timer.isPreparingDisplayFullscreen)
        }
        Menu("Start Preset") {
            ForEach(timer.presetNames.indices, id: \.self) { index in
                Button("Start \(timer.presetNames[index])") {
                    timer.selectAndStartPreset(index)
                }
            }
        }
        Button("Countdown…") { showingCustomCountdown = true }
        Button("Start Stopwatch") { timer.startStopwatch() }
        if let next = timer.nextPhaseName {
            Button("Start \(next)") { timer.startNextPhase() }
        } else {
            Button(countdownActionName) { timer.startOrPause() }
        }
        Button("Reset Timer") { timer.reset() }
        if timer.hasSuspendedPomodoro {
            Button("Resume Pomodoro") { timer.resumePomodoro() }
        }
        if timer.canSkipBreak {
            Button(timer.skipBreakName) { timer.skipBreak() }
        }
        Divider()
        Button("Settings…") { showingSettings = true }
        Button(timer.alwaysOnTop ? "Turn Off Always on Top" : "Always on Top") {
            timer.alwaysOnTop.toggle()
        }
        Button("Standard Window") { timer.setBorderlessWindow(false) }
        Button("Floating Digital Timer Help") { showFloatingHelp() }
    }

    private func showFloatingHelp() {
        hasSeenFloatingCubeHint = true
        showBorderlessHint = true
        Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            showBorderlessHint = false
        }
    }

    private func borderlessReadout(size: CGFloat) -> some View {
        let state = timer.isComplete ? (timer.sessionKind == .stopwatch ? "STOPPED" : "DONE") : timer.isRunning ? "RUNNING" :
            timer.isPaused ? "PAUSED" : "READY"
        let label = timer.flowEnabled
            ? "\(timer.phase.displayLabel) · \(timer.focusProgressLabel) · \(state)"
            : "\(timer.sessionKind == .stopwatch ? "STOPWATCH" : timer.sessionKind == .customCountdown ? "COUNTDOWN" : timer.hasSuspendedPomodoro ? "ONE-OFF" : "TIMER") · \(state)"
        let compact = size < 320
        let visibleLabel = compact
            ? (timer.flowEnabled ? "\(timer.phase.displayLabel) · \(state)"
               : timer.sessionKind == .stopwatch ? "STOPWATCH · \(state)" :
                 timer.sessionKind == .customCountdown ? "COUNTDOWN · \(state)" :
                 timer.hasSuspendedPomodoro ? "ONE-OFF · \(state)" : state)
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
        .help("Return to Timer Face · keeps current session")
        .accessibilityLabel("Return to Timer Face")
        .accessibilityHint("Rotates the cube back without changing the current session")
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
                Text("\(countdownActionName) \(timer.sessionKind == .stopwatch ? "stopwatch" : "countdown")")
            }
            .accessibilityValue(timer.accessibilityValue)
            .accessibilityHint("Starts, pauses, or resumes without resetting paused time")

            ForEach(timer.presetNames.indices, id: \.self) { index in
                Button("Start \(timer.presetNames[index])") {
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

            if (timer.borderlessWindow || isInNativeFullscreen) && !displayFaceReadable {
                Button("Return to Timer Face") { returnToTimerFace() }
                    .accessibilityHint("Rotates the cube back without changing the current session")
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

    private func header(narrow: Bool, availableWidth: CGFloat) -> some View {
        let fullscreenPhase = displayFullscreenPhase
        return ZStack {
            HStack(spacing: 9) {
                Image(systemName: timer.displayStyle == .cube ? "cube.fill" :
                      timer.displayStyle == .digital ? "timer" : "clock")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(accent)
                if !narrow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.displayStyle == .cube ? "CUBE" :
                             timer.displayStyle == .digital ? "DIGITAL" : "DESK")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(3)
                        Text(timer.displayStyle == .clock ? "CLOCK" : "TIMER")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(3.5)
                            .foregroundStyle(colors.secondary)
                    }
                }
                Spacer(minLength: 0)
                if timer.displayStyle.supportsFullscreen {
                    Button(action: toggleDisplayFullscreen) {
                        Image(systemName: isInNativeFullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 31, height: 30)
                    }
                    .help(fullscreenPhase == .preparing ? "Entering Full Screen" :
                          (fullscreenPhase == .fullscreen ? "Exit Full Screen" :
                           timer.displayStyle.fullscreenTitle))
                    .accessibilityLabel(fullscreenPhase == .preparing ? "Entering Full Screen" :
                                        (fullscreenPhase == .fullscreen ? "Exit Full Screen" :
                                         timer.displayStyle.fullscreenTitle))
                    .disabled(!DisplayFullscreenTransition.shouldEnableFullscreenToggle(
                        phase: fullscreenPhase))
                }
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
            if DisplayFullscreenTransition.shouldShowDisplayPicker(phase: fullscreenPhase) {
                HStack(spacing: 2) {
                    ForEach(TimerDisplayStyle.allCases) { style in
                        let selected = timer.displayStyle == style
                        Button { timer.displayStyle = style } label: {
                            Text(style.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .foregroundStyle(selected ? colors.text : colors.secondary)
                                .background(selected ? colors.background : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(style.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(colors.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(colors.edge, lineWidth: 1)
                }
                .frame(width: TimerWindowLayout.headerPickerWidth(
                    availableWidth: availableWidth, compact: narrow))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timer design")
            }
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
            Text(timer.sessionKind == .stopwatch ? "STOPWATCH / \(digitalStatusLabel)" :
                 timer.sessionKind == .customCountdown ? "COUNTDOWN / \(digitalStatusLabel)" :
                 timer.hasSuspendedPomodoro ? "ONE-OFF / POMODORO PAUSED · \(timer.focusProgressLabel)" : timer.flowEnabled
                 ? "POMODORO / \(timer.phase.displayLabel) · \(timer.focusProgressLabel)\(timer.isComplete ? " COMPLETE" : "")"
                 : "COUNTDOWN / \(timer.isRunning ? "RUNNING" : timer.isPaused ? "PAUSED" : timer.isComplete ? "COMPLETE" : "READY")")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if timer.displayStyle == .cube {
                Text(timer.timeLabel)
                    .foregroundStyle(colors.text)
                    .monospacedDigit()
                    .accessibilityLabel("\(timer.sessionKind == .stopwatch ? "Time elapsed" : "Time remaining") \(timer.timeLabel)")
            }
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
                      activePresetSeconds: timer.sessionKind == .presetCountdown &&
                          !(timer.flowEnabled && timer.phase == .longBreak)
                          ? Int(timer.total) : nil,
                      timeLabel: timer.timeLabel,
                      progress: timer.progress,
                      showsCountdownProgress: timer.sessionKind != .stopwatch,
                      appearance: appearance.value,
                      automaticReadableDigits: appearance.automaticReadableDigits,
                      completed: timer.sessionKind != .stopwatch && timer.isComplete,
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
                      displayStyle: timer.displayStyle,
                      isFullscreen: isInNativeFullscreen,
                      isPreparingFullscreen: timer.isPreparingDisplayFullscreen,
                      onToggleFullscreen: toggleDisplayFullscreen,
                      onDisplayClick: { timer.startOrPause() },
                      onOpenSettings: { showingSettings = true },
                      onOpenCustomCountdown: { showingCustomCountdown = true },
                      onStartStopwatch: { timer.startStopwatch() },
                      onShowFloatingHelp: showFloatingHelp,
                      onToggleBorderless: {
                          timer.setBorderlessWindow(!timer.borderlessWindow)
                      },
                      onToggleAlwaysOnTop: { timer.alwaysOnTop.toggle() },
                      onReset: { timer.reset() },
                      onSelectDisplayStyle: { timer.displayStyle = $0 },
                      focusMarks: timer.sessionKind != .stopwatch && timer.pomodoroModeEnabled
                          ? CubeFocusProgress(completed: timer.focusesInCycle,
                                              target: timer.cycleTarget) : nil,
                      sessionLabel: timer.sessionKind == .stopwatch ? "STOPWATCH" :
                          timer.sessionKind == .customCountdown ? "COUNTDOWN" :
                          timer.flowEnabled ? timer.phase.displayLabel : nil,
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
                let selected = timer.sessionKind == .presetCountdown &&
                    timer.selectedPreset == index &&
                    !(timer.flowEnabled && timer.phase == .longBreak)
                Button {
                    if timer.displayStyle.presetTilesStartImmediately {
                        timer.selectAndStartCubeFace(index)
                    } else if !selected {
                        timer.selectPreset(index)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(timer.presetNames[index])
                            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .truncationMode(.tail)
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
                .accessibilityLabel("\(timer.presetNames[index]) preset, \(TimerEngine.display(TimeInterval(timer.presetSeconds[index])))")
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

    private func timingModeButtons(compact: Bool) -> some View {
        HStack(spacing: 10) {
            timingModeButton("COUNTDOWN", systemImage: "timer",
                             selected: timer.sessionKind == .customCountdown,
                             compact: compact,
                             hint: "Opens time entry without interrupting the current timer") {
                showingCustomCountdown = true
            }
            timingModeButton("STOPWATCH", systemImage: "stopwatch",
                             selected: timer.sessionKind == .stopwatch,
                             compact: compact,
                             hint: "Starts the stopwatch immediately; Undo can restore an active timer") {
                timer.startStopwatch()
            }
        }
    }

    private func timingModeButton(_ title: String, systemImage: String,
                                  selected: Bool, compact: Bool, hint: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 36 : 44)
                .foregroundStyle(selected ? accent : colors.text)
                .background(selected ? accent.opacity(0.12) : colors.panel,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? accent.opacity(0.8) : colors.edge)
                }
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            Text(timer.displayStyle == .cube
                 ? "DRAG TO ORBIT  ·  CLICK A FACE"
                 : "SELECT A PRESET  ·  SPACE TO START")
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

enum CustomCountdownInput {
    static func duration(minutes: String, seconds: String) -> Int? {
        guard !minutes.isEmpty, !seconds.isEmpty,
              minutes.allSatisfy({ $0.isASCII && $0.isNumber }),
              seconds.allSatisfy({ $0.isASCII && $0.isNumber }),
              let minuteValue = Int(minutes), let secondValue = Int(seconds),
              (0...99).contains(minuteValue), (0...59).contains(secondValue) else {
            return nil
        }
        let total = minuteValue * 60 + secondValue
        return (TimerEngine.minimumDuration...TimerEngine.maximumDuration).contains(total)
            ? total : nil
    }
}

private struct CustomCountdownPopover: View {
    let initialSeconds: Int
    let presetNames: [String]
    let initialPresetIndex: Int
    let onStart: (Int) -> Void
    let onSavePreset: (Int, Int, String) -> Void
    let onCancel: () -> Void
    @State private var minutes = ""
    @State private var seconds = ""
    @State private var savingPreset = false
    @State private var selectedPresetIndex = 0
    @State private var presetName = ""

    private var duration: Int? { CustomCountdownInput.duration(minutes: minutes, seconds: seconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COUNTDOWN")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            HStack(spacing: 10) {
                TextField("Minutes", text: $minutes)
                    .accessibilityLabel("Minutes")
                Text(":")
                TextField("Seconds", text: $seconds)
                    .accessibilityLabel("Seconds")
            }
            .font(.system(size: 22, weight: .semibold, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            Text("Enter 00:01–99:59. Start without changing presets, or save this duration to a slot.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if savingPreset {
                Divider()
                Text("SAVE AS PRESET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Picker("Preset slot", selection: $selectedPresetIndex) {
                    ForEach(presetNames.indices, id: \.self) { index in
                        Text(presetNames[index]).tag(index)
                    }
                }
                TextField("Preset name", text: $presetName)
                    .accessibilityLabel("Preset name")
                Button("Save Preset") {
                    guard let duration,
                          !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSavePreset(selectedPresetIndex, duration,
                                 presetName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .disabled(duration == nil || presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                if !savingPreset {
                    Button("Save as Preset") {
                        savingPreset = true
                        selectedPresetIndex = min(initialPresetIndex, max(0, presetNames.count - 1))
                        presetName = presetNames.indices.contains(selectedPresetIndex)
                            ? presetNames[selectedPresetIndex] : "Preset"
                    }
                }
                Button("Start") {
                    if let duration { onStart(duration) }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(duration == nil)
            }
        }
        .padding(18)
        .frame(width: 280)
        .onAppear {
            selectedPresetIndex = min(initialPresetIndex, max(0, presetNames.count - 1))
            let initial = TimerEngine.clampedDuration(initialSeconds)
            minutes = String(format: "%02d", initial / 60)
            seconds = String(format: "%02d", initial % 60)
        }
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
    @State private var presetNamesDraft = TimerModel.defaultPresetNames
    @State private var presetRolesDraft = TimerModel.defaultDurations.indices.map { index in
        index == 0 ? PresetRole.shortBreak : index == 2 ? PresetRole.focus : PresetRole.general
    }
    @State private var longBreakMinutes = 15
    @State private var longBreakSeconds = 0
    @State private var cycleTargetSelection = 4
    @State private var showingPresetResetConfirmation = false

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
                Button("Done") { timer.setCycleTarget(cycleTargetSelection); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 3) {
                ForEach(Tab.allCases, id: \.self) { section in
                    let selected = tab == section
                    Button { tab = section } label: {
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .foregroundStyle(selected ? colors.text : colors.secondary)
                            .background(selected ? colors.background : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(colors.panel, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(colors.edge, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings section")

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
            presetNamesDraft = timer.presetNames
            presetRolesDraft = timer.presetRoles
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
                presetDurationRow(index)
            }
            durationRow("Long Break", setting: .longBreak,
                        minutes: $longBreakMinutes, seconds: $longBreakSeconds,
                        savedSeconds: timer.longBreakSeconds)
            helper("Durations: 00:01–99:59. Edit each name and role, then save the row. Focus and Short Break roles drive Pomodoro; only one slot can have each role.")
            Button("Reset Preset Settings to Defaults") {
                showingPresetResetConfirmation = true
            }
            .confirmationDialog("Reset preset settings and focus-cycle target to defaults?",
                                isPresented: $showingPresetResetConfirmation,
                                titleVisibility: .visible) {
                Button("Reset Preset Settings", role: .destructive) {
                    timer.resetPresetSettings()
                    minutes = timer.presetSeconds.map { $0 / 60 }
                    seconds = timer.presetSeconds.map { $0 % 60 }
                    presetNamesDraft = timer.presetNames
                    presetRolesDraft = timer.presetRoles
                    longBreakMinutes = timer.longBreakSeconds / 60
                    longBreakSeconds = timer.longBreakSeconds % 60
                    cycleTargetSelection = 4
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Preset settings and the focus-cycle target will be restored. The active timer will not be reset.")
            }
        }
    }

    private func presetDurationRow(_ index: Int) -> some View {
        let name = presetNamesDraft[index]
        let proposed = TimerEngine.clampedDuration(
            min(99, max(0, minutes[index])) * 60 + min(59, max(0, seconds[index])))
        let durationChanged = proposed != timer.presetSeconds[index]
        let metadataChanged = name != timer.presetNames[index] ||
            presetRolesDraft[index] != timer.presetRoles[index]
        let immediate = durationChanged
            ? timer.immediateDurationAction(for: .preset(index), seconds: proposed) : nil
        let rowActions = PresetEditorRowPolicy.state(
            durationChanged: durationChanged,
            metadataChanged: metadataChanged,
            canAffectActiveSession: immediate != nil)
        let duplicateNames = PresetEditorRowPolicy.duplicateNames(
            for: proposed,
            editingIndex: index,
            presetSeconds: minutes.indices.map {
                TimerEngine.clampedDuration(
                    min(99, max(0, minutes[$0])) * 60 + min(59, max(0, seconds[$0])))
            },
            presetNames: presetNamesDraft)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                TextField("Preset name", text: $presetNamesDraft[index])
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 155)
                    .accessibilityLabel("Preset \(index + 1) name")
                Picker("Preset role", selection: $presetRolesDraft[index]) {
                    ForEach(PresetRole.allCases, id: \.self) { role in
                        Text(role.title).tag(role)
                    }
                }
                .labelsHidden()
                Spacer(minLength: 4)
                TextField("min", value: $minutes[index], format: .number)
                    .frame(width: 43)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("\(name) minutes")
                Text("m").accessibilityHidden(true)
                TextField("sec", value: $seconds[index], format: .number)
                    .frame(width: 43)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("\(name) seconds")
                Text("s").accessibilityHidden(true)
            }
            .font(.system(size: 12, design: .monospaced))
            Text(presetRolesDraft[index].pomodoroDescription)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colors.secondary)
            if !duplicateNames.isEmpty {
                Label("Same duration as \(duplicateNames.joined(separator: ", "))",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(colors.secondary)
                    .accessibilityLabel("Duplicate duration. Matches \(duplicateNames.joined(separator: ", ")). Duplicates are allowed.")
            }
            if rowActions.showsImmediateAction, let immediate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT SESSION")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(colors.secondary)
                    Button(immediate == .applyNow ? "Apply Now" : "Restart This Phase") {
                        commitDuration(.preset(index), proposed: proposed,
                                       action: immediate == .applyNow ? .applyNow : .restartThisPhase,
                                       minutes: $minutes[index], seconds: $seconds[index])
                    }
                }
            }
            HStack(spacing: 12) {
                Button("Save Preset") {
                    if durationChanged {
                        _ = timer.editDuration(.preset(index), seconds: proposed, action: .useNextTime)
                        minutes[index] = proposed / 60
                        seconds[index] = proposed % 60
                    }
                    timer.setPresetName(index, name: name)
                    timer.setPresetRole(index, role: presetRolesDraft[index])
                    presetNamesDraft[index] = timer.presetNames[index]
                    presetRolesDraft = timer.presetRoles
                }
                .disabled(!rowActions.isSaveEnabled || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use Next Time") {
                    commitDuration(.preset(index), proposed: proposed, action: .useNextTime,
                                   minutes: $minutes[index], seconds: $seconds[index])
                }
                .disabled(!rowActions.isUseNextTimeEnabled)
                Spacer(minLength: 0)
                Button("Reset") {
                    timer.resetPreset(index)
                    minutes[index] = timer.presetSeconds[index] / 60
                    seconds[index] = timer.presetSeconds[index] % 60
                    presetNamesDraft[index] = timer.presetNames[index]
                    presetRolesDraft = timer.presetRoles
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(colors.panel, in: RoundedRectangle(cornerRadius: 9))
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
                .disabled(timer.isDisplayFullscreen || timer.isPreparingDisplayFullscreen)
            Toggle("Always on Top", isOn: $timer.alwaysOnTop)
                .toggleStyle(.switch)
            Toggle("Show Timer in Menu Bar", isOn: Binding(
                get: { timer.showMenuBarTimer },
                set: { timer.setShowMenuBarTimer($0) }
            ))
                .toggleStyle(.switch)
                .accessibilityHint("Shows the timer and quick controls in the menu bar. Hiding it does not stop the timer.")
            helper("The menu bar timer shows the current time and state, lets you pause or resume, and starts saved presets. Remove it here or from the menu bar at any time.")
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

    private func durationRow(_ name: String, setting: DurationSetting,
                             minutes: Binding<Int>, seconds: Binding<Int>,
                             savedSeconds: Int) -> some View {
        let proposed = TimerEngine.clampedDuration(
            min(99, max(0, minutes.wrappedValue)) * 60 +
                min(59, max(0, seconds.wrappedValue)))
        let changed = proposed != savedSeconds
        let immediate = changed
            ? timer.immediateDurationAction(for: setting, seconds: proposed) : nil
        return VStack(alignment: .leading, spacing: 7) {
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
            if changed {
                HStack(spacing: 12) {
                    if let immediate {
                        Button(immediate == .applyNow ? "Apply Now" : "Restart This Phase") {
                            let action: DurationEditAction = immediate == .applyNow
                                ? .applyNow : .restartThisPhase
                            commitDuration(setting, proposed: proposed, action: action,
                                           minutes: minutes, seconds: seconds)
                        }
                        .accessibilityLabel("\(immediate == .applyNow ? "Apply now" : "Restart this phase") with \(name) duration")
                        .accessibilityHint(immediate == .applyNow
                            ? "Preserves elapsed time and the current running or paused state"
                            : "Starts this phase at its full new duration without changing its running or paused state")
                    }
                    Button("Use Next Time") {
                        commitDuration(setting, proposed: proposed, action: .useNextTime,
                                       minutes: minutes, seconds: seconds)
                    }
                    .accessibilityLabel("Use \(name) duration next time")
                    .accessibilityHint("Saves the duration without changing the current running or paused timer")
                }
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(colors.panel, in: RoundedRectangle(cornerRadius: 9))
    }

    private func commitDuration(_ setting: DurationSetting, proposed: Int,
                                action: DurationEditAction, minutes: Binding<Int>,
                                seconds: Binding<Int>) {
        guard timer.editDuration(setting, seconds: proposed, action: action) else { return }
        minutes.wrappedValue = proposed / 60
        seconds.wrappedValue = proposed % 60
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            CubeSceneView(selectedPreset: timer.selectedPreset,
                          presetSeconds: timer.presetSeconds,
                          timeLabel: timer.timeLabel,
                          progress: timer.progress,
                          showsCountdownProgress: timer.sessionKind != .stopwatch,
                          appearance: appearance.value,
                          automaticReadableDigits: appearance.automaticReadableDigits,
                          completed: false, interactive: false,
                          selectionTick: 0, returnToDisplayTick: 0, borderless: false,
                          alwaysOnTop: timer.alwaysOnTop,
                          replacingActiveSession: false, displayAction: "Start",
                          onDisplayClick: {}, onOpenSettings: {}, onShowFloatingHelp: {},
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
            Divider().padding(.vertical, 1)
            sectionTitle("DESK CLOCK")
            Toggle("Use 24-hour time", isOn: Binding(
                get: { timer.use24HourTime },
                set: { timer.setUse24HourTime($0) }
            ))
                .toggleStyle(.switch)
                .accessibilityHint("Shows Desk Clock in a locale-aware 24-hour format")
            helper("When off, Desk Clock follows your Mac’s time format preference. This affects Desk Clock only.")
            Divider().padding(.vertical, 1)
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

}
