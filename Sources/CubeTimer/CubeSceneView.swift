import AppKit
import SceneKit
import SwiftUI
import simd

struct CubeFocusProgress: Equatable {
    let completed: Int
    let target: Int
}

/// Six physical faces; the break preset repeats on the remaining extra face.
private enum CubeFace: Int, CaseIterable {
    case front, right, back, left, top, bottom

    var preset: Int {
        switch self {
        case .front, .left: 0
        case .right: 1
        case .back: 2
        case .top: 3
        case .bottom: 4
        }
    }

    static func primary(for preset: Int) -> CubeFace {
        switch preset {
        case 0: .front
        case 1: .right
        case 2: .back
        case 3: .top
        default: .bottom
        }
    }

    var position: SCNVector3 {
        switch self {
        case .front: SCNVector3(0, 0, 1.008)
        case .right: SCNVector3(1.008, 0, 0)
        case .back: SCNVector3(0, 0, -1.008)
        case .left: SCNVector3(-1.008, 0, 0)
        case .top: SCNVector3(0, 1.008, 0)
        case .bottom: SCNVector3(0, -1.008, 0)
        }
    }

    var eulerAngles: SCNVector3 {
        switch self {
        case .front: SCNVector3Zero
        case .right: SCNVector3(0, Float.pi / 2, 0)
        case .back: SCNVector3(0, Float.pi, 0)
        case .left: SCNVector3(0, -Float.pi / 2, 0)
        case .top: SCNVector3(-Float.pi / 2, 0, 0)
        case .bottom: SCNVector3(Float.pi / 2, 0, 0)
        }
    }

    var normal: SIMD3<Float> {
        switch self {
        case .front: SIMD3(0, 0, 1)
        case .right: SIMD3(1, 0, 0)
        case .back: SIMD3(0, 0, -1)
        case .left: SIMD3(-1, 0, 0)
        case .top: SIMD3(0, 1, 0)
        case .bottom: SIMD3(0, -1, 0)
        }
    }

    var frontOrientation: simd_quatf {
        switch self {
        case .front: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        case .right: simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        case .back: simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        case .left: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        case .top: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        case .bottom: simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        }
    }

    var presentationOrientation: simd_quatf {
        let pitch = simd_quatf(angle: 0.48, axis: SIMD3<Float>(1, 0, 0))
        let yaw = simd_quatf(angle: -0.55, axis: SIMD3<Float>(0, 1, 0))
        return simd_mul(simd_mul(pitch, yaw), frontOrientation)
    }
}

enum CubeDisplayReadability {
    static func readable(facing: Float, previouslyReadable: Bool?) -> Bool {
        facing >= (previouslyReadable == false ? 0.70 : 0.62)
    }
}

enum DisplayStrokeSizing {
    static func emphasis(for viewport: NSSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 0 }
        // The 240–320 point borderless window gives SceneKit about 223–298 points
        // after padding. Ten steps avoid regenerating a 1024px texture on every pixel.
        let amount = min(1, max(0, (300 - min(viewport.width, viewport.height)) / 77))
        return (amount * 10).rounded() / 10
    }
}

fileprivate enum CubeHoverTarget: Equatable {
    case preset(Int)
    case display(Int)

    var faceIndex: Int {
        switch self {
        case .preset(let index), .display(let index): index
        }
    }
}

struct CubeSceneView: NSViewRepresentable {
    let selectedPreset: Int
    let presetSeconds: [Int]
    let timeLabel: String
    let progress: Double
    let appearance: CubeAppearance
    let automaticReadableDigits: Bool
    let completed: Bool
    let interactive: Bool
    let selectionTick: Int
    let returnToDisplayTick: Int
    let borderless: Bool
    let alwaysOnTop: Bool
    let replacingActiveSession: Bool
    var willSuspendPomodoro: Bool = false
    var suspendEveryFace: Bool = false
    var longBreakDue: Bool = false
    var pomodoroSuspended: Bool = false
    let displayAction: String
    let onDisplayClick: () -> Void
    let onOpenSettings: () -> Void
    let onToggleBorderless: () -> Void
    let onToggleAlwaysOnTop: () -> Void
    let onReset: () -> Void
    var focusMarks: CubeFocusProgress? = nil
    var sessionLabel: String? = nil
    var nextPhaseName: String? = nil
    var onStartNextPhase: (() -> Void)? = nil
    var onSkipBreak: (() -> Void)? = nil
    var skipBreakName: String = "Skip Short Break"
    var onResumePomodoro: (() -> Void)? = nil
    var onDisplayReadableChange: ((Bool) -> Void)? = nil
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CubeSCNView {
        let view = CubeSCNView()
        view.backgroundColor = .clear
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = false
        configureInteraction(view, coordinator: context.coordinator)
        context.coordinator.render(view: view, selectedPreset: selectedPreset,
                                   presetSeconds: presetSeconds, timeLabel: timeLabel,
                                   progress: progress, appearance: appearance,
                                   automaticReadableDigits: automaticReadableDigits,
                                   completed: completed, focusMarks: focusMarks,
                                   sessionLabel: sessionLabel)
        context.coordinator.handleReturnRequest(returnToDisplayTick)
        return view
    }

    func updateNSView(_ view: CubeSCNView, context: Context) {
        configureInteraction(view, coordinator: context.coordinator)
        context.coordinator.render(view: view, selectedPreset: selectedPreset,
                                   presetSeconds: presetSeconds, timeLabel: timeLabel,
                                   progress: progress, appearance: appearance,
                                   automaticReadableDigits: automaticReadableDigits,
                                   completed: completed, focusMarks: focusMarks,
                                   sessionLabel: sessionLabel)
        context.coordinator.handleReturnRequest(returnToDisplayTick)
    }

    private func configureInteraction(_ view: CubeSCNView, coordinator: Coordinator) {
        view.clickHandler = { faceIndex in
            guard interactive, let face = CubeFace(rawValue: faceIndex) else { return }
            coordinator.select(face)
            onSelect(face.preset)
        }
        view.dragHandler = { dx, dy in
            guard interactive else { return }
            coordinator.orbit(dx: dx, dy: dy)
        }
        view.displayClickHandler = interactive ? onDisplayClick : nil
        view.openSettingsHandler = interactive ? onOpenSettings : nil
        view.toggleBorderlessHandler = interactive ? onToggleBorderless : nil
        view.toggleAlwaysOnTopHandler = interactive ? onToggleAlwaysOnTop : nil
        view.resetHandler = interactive ? onReset : nil
        view.nextPhaseName = interactive ? nextPhaseName : nil
        view.startNextPhaseHandler = interactive ? onStartNextPhase : nil
        view.skipBreakHandler = interactive ? onSkipBreak : nil
        view.skipBreakName = skipBreakName
        view.resumePomodoroHandler = interactive ? onResumePomodoro : nil
        view.willSuspendPomodoro = willSuspendPomodoro
        view.suspendEveryFace = suspendEveryFace
        view.longBreakDue = longBreakDue
        view.pomodoroSuspended = pomodoroSuspended
        view.hoverHandler = interactive ? { [weak view] target in
            coordinator.setHover(target, view: view)
        } : nil
        view.resizeHandler = { [weak view] size in
            coordinator.updateViewport(size, view: view)
        }
        view.displayReadabilityHandler = { readable in
            DispatchQueue.main.async { onDisplayReadableChange?(readable) }
        }
        coordinator.updateViewport(view.bounds.size, view: view)
        view.interactive = interactive
        view.borderless = borderless
        view.alwaysOnTop = alwaysOnTop
        let wasReplacingSession = view.replacingActiveSession
        view.replacingActiveSession = replacingActiveSession
        view.displayAction = displayAction
        if wasReplacingSession != replacingActiveSession { view.refreshHover() }
    }

    final class Coordinator {
        let scene = SCNScene()
        let camera = SCNNode()
        private let cube = SCNNode()
        private var lastReturnRequest: Int?
        private let body: SCNBox
        private let ambient = SCNLight()
        private let key = SCNLight()
        private var faces: [CubeFace: SCNNode] = [:]
        private var bezels: [CubeFace: SCNNode] = [:]
        private var hoverOutlines: [CubeFace: SCNNode] = [:]
        private var hoveredFace: CubeFace?
        private weak var activeView: CubeSCNView?
        private var selectedFace: CubeFace = .front
        private var lastPreset: Int?
        private var lastAppearance: CubeAppearance?
        private var lastAutomaticReadableDigits = true
        private var lastRenderedEmphasis: CGFloat = -1
        private var lastTimes: [Int] = []
        private var lastDisplay = ""
        private var lastSegments = -1
        private var lastCompleted = false
        private var lastFocusMarks: CubeFocusProgress?
        private var lastSessionLabel: String?
        private var lastRenderedFace: CubeFace?
        private var lastReadability: Bool?
        private var labelCache: [CubeFace: NSImage] = [:]
        private var lastViewportSize: NSSize = .zero

        func updateViewport(_ size: NSSize, view: CubeSCNView?) {
            guard size.width > 0, size.height > 0,
                  size != lastViewportSize else { return }
            lastViewportSize = size
            let emphasis = DisplayStrokeSizing.emphasis(for: size)
            if emphasis != lastRenderedEmphasis, let appearance = lastAppearance,
               lastSegments >= 0 {
                updateActiveDisplayTexture(
                    appearance: appearance, timeLabel: lastDisplay,
                    litSegments: lastSegments, completed: lastCompleted,
                    focusMarks: lastFocusMarks, sessionLabel: lastSessionLabel,
                    automaticReadableDigits: lastAutomaticReadableDigits,
                    emphasis: emphasis)
                lastRenderedEmphasis = emphasis
            }
            let aspect = size.width / size.height
            let distance = 5.4 * max(1, 1 / aspect)
            if abs(camera.position.z - distance) > 0.001 {
                camera.position.z = distance
            }
            view?.setNeedsDisplay(view?.bounds ?? .zero)
            publishDisplayReadability()
        }

        init() {
            scene.background.contents = NSColor.clear
            body = SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0.18)
            body.chamferSegmentCount = 10
            let bodyNode = SCNNode(geometry: body)
            bodyNode.name = "body"
            cube.addChildNode(bodyNode)
            scene.rootNode.addChildNode(cube)

            for face in CubeFace.allCases {
                let surface = SCNNode()
                surface.name = "face-\(face.rawValue)"
                surface.position = face.position
                surface.eulerAngles = face.eulerAngles

                let plane = SCNPlane(width: 1.84, height: 1.84)
                let faceMaterial = SCNMaterial()
                faceMaterial.lightingModel = .constant
                faceMaterial.isDoubleSided = false
                faceMaterial.transparencyMode = .aOne
                faceMaterial.writesToDepthBuffer = false
                plane.materials = [faceMaterial]
                let planeNode = SCNNode(geometry: plane)
                planeNode.name = surface.name
                surface.addChildNode(planeNode)

                let rim = SCNTorus(ringRadius: 0.746, pipeRadius: 0.035)
                rim.ringSegmentCount = 96
                rim.pipeSegmentCount = 12
                let rimNode = SCNNode(geometry: rim)
                rimNode.eulerAngles.x = .pi / 2
                rimNode.position.z = 0.033
                rimNode.name = surface.name
                rimNode.isHidden = true
                surface.addChildNode(rimNode)

                let outline = SCNPlane(width: 1.84, height: 1.84)
                let outlineMaterial = SCNMaterial()
                outlineMaterial.lightingModel = .constant
                outlineMaterial.isDoubleSided = false
                outlineMaterial.writesToDepthBuffer = false
                outline.materials = [outlineMaterial]
                let outlineNode = SCNNode(geometry: outline)
                outlineNode.position.z = 0.075
                outlineNode.opacity = 0
                outlineNode.categoryBitMask = 2
                surface.addChildNode(outlineNode)

                cube.addChildNode(surface)
                faces[face] = planeNode
                bezels[face] = rimNode
                hoverOutlines[face] = outlineNode
            }

            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 34
            camera.camera?.categoryBitMask = 3
            camera.position = SCNVector3(0, 0, 5.4)
            scene.rootNode.addChildNode(camera)

            ambient.type = .ambient
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            key.type = .omni
            key.castsShadow = true
            key.shadowRadius = 12
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.position = SCNVector3(-3.5, 4.5, 5)
            scene.rootNode.addChildNode(keyNode)

            let fill = SCNLight()
            fill.type = .omni
            fill.intensity = 95
            let fillNode = SCNNode()
            fillNode.light = fill
            fillNode.position = SCNVector3(4, -1.5, 3)
            scene.rootNode.addChildNode(fillNode)
        }

        func render(view: CubeSCNView, selectedPreset: Int, presetSeconds: [Int],
                    timeLabel: String, progress: Double, appearance: CubeAppearance,
                    automaticReadableDigits: Bool, completed: Bool,
                    focusMarks: CubeFocusProgress?, sessionLabel: String?) {
            activeView = view
            if lastPreset == nil {
                selectedFace = CubeFace.primary(for: selectedPreset)
                cube.simdOrientation = selectedFace.presentationOrientation
            } else if lastPreset != selectedPreset && selectedFace.preset != selectedPreset {
                select(CubeFace.primary(for: selectedPreset))
            }
            lastPreset = selectedPreset
            view.activeDisplayFaceIndex = selectedFace.rawValue

            let styleChanged = lastAppearance != appearance
            let timesChanged = lastTimes != presetSeconds
            let emphasis = DisplayStrokeSizing.emphasis(for: view.bounds.size)
            let segments = Int(ceil((1 - min(1, max(0, progress))) * 60))
            let displayChanged = lastDisplay != timeLabel || lastSegments != segments ||
                lastCompleted != completed ||
                lastFocusMarks != focusMarks || lastSessionLabel != sessionLabel ||
                lastAutomaticReadableDigits != automaticReadableDigits ||
                lastRenderedEmphasis != emphasis
            let faceChanged = lastRenderedFace != selectedFace

            if styleChanged {
                updateMaterials(appearance)
                lastAppearance = appearance
            }
            if styleChanged || timesChanged || displayChanged || faceChanged {
                if styleChanged || faceChanged {
                    updateHoverOutlines(accent: appearance.accent)
                }
                updateFaces(appearance: appearance, durations: presetSeconds,
                            timeLabel: timeLabel, litSegments: segments, completed: completed,
                            focusMarks: focusMarks, sessionLabel: sessionLabel,
                            automaticReadableDigits: automaticReadableDigits,
                            emphasis: emphasis,
                            rebuildLabels: styleChanged || timesChanged,
                            faceChanged: faceChanged)
                lastTimes = presetSeconds
                lastDisplay = timeLabel
                lastSegments = segments
                lastCompleted = completed
                lastFocusMarks = focusMarks
                lastSessionLabel = sessionLabel
                lastAutomaticReadableDigits = automaticReadableDigits
                lastRenderedEmphasis = emphasis
                lastRenderedFace = selectedFace
                view.setNeedsDisplay(view.bounds)
            }
            publishDisplayReadability()
        }

        fileprivate func select(_ face: CubeFace) {
            guard selectedFace != face else { return }
            selectedFace = face
            animateToSelectedFace()
            // The next SwiftUI update swaps the display texture to the selected face.
        }

        func handleReturnRequest(_ request: Int) {
            let previous = lastReturnRequest
            lastReturnRequest = request
            guard let previous, previous != request else { return }
            animateToSelectedFace()
        }

        private func animateToSelectedFace() {
            setHover(nil, view: activeView)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.55
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = { [weak self, weak activeView] in
                self?.publishDisplayReadability()
                activeView?.refreshHover()
            }
            cube.simdOrientation = selectedFace.presentationOrientation
            SCNTransaction.commit()
            publishDisplayReadability()
            // Sample SceneKit's animated presentation orientation so the compact
            // readout follows the face while it turns, including when idle.
            for step in 1...4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.11) {
                    [weak self] in
                    self?.publishDisplayReadability()
                }
            }
        }

        func orbit(dx: CGFloat, dy: CGFloat) {
            let yaw = simd_quatf(angle: Float(dx) * 0.008, axis: SIMD3<Float>(0, 1, 0))
            let pitch = simd_quatf(angle: -Float(dy) * 0.008, axis: SIMD3<Float>(1, 0, 0))
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            cube.simdOrientation = simd_mul(simd_mul(yaw, pitch), cube.simdOrientation)
            SCNTransaction.commit()
            publishDisplayReadability(using: cube.simdOrientation)
        }

        private func publishDisplayReadability(using orientation: simd_quatf? = nil) {
            let direction = simd_act(orientation ?? cube.presentation.simdOrientation,
                                     selectedFace.normal)
            let readable = CubeDisplayReadability.readable(
                facing: direction.z, previouslyReadable: lastReadability)
            guard readable != lastReadability else { return }
            lastReadability = readable
            activeView?.displayReadabilityHandler?(readable)
        }

        fileprivate func setHover(_ target: CubeHoverTarget?, view: CubeSCNView?) {
            let face = target.flatMap { CubeFace(rawValue: $0.faceIndex) }
            guard hoveredFace != face else { return }
            hoveredFace = face
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.14
            for (candidate, outline) in hoverOutlines {
                outline.opacity = candidate == face ? 1 : 0
            }
            SCNTransaction.commit()
            view?.setNeedsDisplay(view?.bounds ?? .zero)
        }

        private func updateHoverOutlines(accent: RGBColor) {
            for face in CubeFace.allCases {
                hoverOutlines[face]?.geometry?.firstMaterial?.diffuse.contents =
                    CubeFaceGraphics.hoverOutline(accent: accent, display: face == selectedFace)
            }
        }

        private func updateMaterials(_ appearance: CubeAppearance) {
            let shell = SCNMaterial()
            shell.lightingModel = .physicallyBased
            shell.diffuse.contents = appearance.body.nsColor
            shell.roughness.contents = appearance.finish.roughness
            shell.metalness.contents = appearance.finish == .gloss ? 0.12 : 0.02
            body.materials = [shell]

            if appearance.body.luminance > 0.58 {
                ambient.intensity = 75 + 125 * appearance.lighting
                key.intensity = 180 + 300 * appearance.lighting
            } else {
                ambient.intensity = 100 + 180 * appearance.lighting
                key.intensity = 270 + 410 * appearance.lighting
            }
            key.shadowColor = NSColor.black.withAlphaComponent(0.22 + 0.4 * appearance.lighting)
            key.shadowRadius = CGFloat(8 + 16 * appearance.lighting)

            for face in CubeFace.allCases {
                let rim = SCNMaterial()
                rim.lightingModel = .physicallyBased
                rim.diffuse.contents = appearance.body.luminance > 0.58
                    ? NSColor(calibratedWhite: 0.30, alpha: 1)
                    : NSColor(calibratedWhite: 0.055, alpha: 1)
                rim.roughness.contents = 0.42
                bezels[face]?.geometry?.materials = [rim]
            }
        }

        private func updateFaces(appearance: CubeAppearance, durations: [Int],
                                 timeLabel: String, litSegments: Int, completed: Bool,
                                 focusMarks: CubeFocusProgress?, sessionLabel: String?,
                                 automaticReadableDigits: Bool, emphasis: CGFloat,
                                 rebuildLabels: Bool, faceChanged: Bool) {
            if rebuildLabels {
                labelCache.removeAll()
                for face in CubeFace.allCases {
                    labelCache[face] = CubeFaceGraphics.label(
                        seconds: durations[face.preset], body: appearance.body)
                }
            }
            for face in CubeFace.allCases {
                if face == selectedFace {
                    updateActiveDisplayTexture(
                        appearance: appearance, timeLabel: timeLabel,
                        litSegments: litSegments, completed: completed,
                        focusMarks: focusMarks, sessionLabel: sessionLabel,
                        automaticReadableDigits: automaticReadableDigits,
                        emphasis: emphasis)
                    bezels[face]?.isHidden = false
                } else if rebuildLabels || faceChanged {
                    faces[face]?.geometry?.firstMaterial?.diffuse.contents = labelCache[face]
                    bezels[face]?.isHidden = true
                }
            }
        }

        private func updateActiveDisplayTexture(appearance: CubeAppearance,
                                                timeLabel: String, litSegments: Int,
                                                completed: Bool,
                                                focusMarks: CubeFocusProgress?, sessionLabel: String?,
                                                automaticReadableDigits: Bool,
                                                emphasis: CGFloat) {
            faces[selectedFace]?.geometry?.firstMaterial?.diffuse.contents =
                CubeFaceGraphics.display(
                    time: timeLabel, accent: appearance.accent,
                    digits: DisplayContrast.readableDigits(
                        appearance.display, automatic: automaticReadableDigits),
                    litSegments: litSegments, completed: completed,
                    focusMarks: focusMarks, sessionLabel: sessionLabel,
                    emphasis: emphasis)
        }
    }
}

final class CubeSCNView: SCNView {
    var clickHandler: ((Int) -> Void)?
    var dragHandler: ((CGFloat, CGFloat) -> Void)?
    var resizeHandler: ((NSSize) -> Void)?
    var displayReadabilityHandler: ((Bool) -> Void)?
    var displayClickHandler: (() -> Void)?
    fileprivate var hoverHandler: ((CubeHoverTarget?) -> Void)?
    var openSettingsHandler: (() -> Void)?
    var toggleBorderlessHandler: (() -> Void)?
    var toggleAlwaysOnTopHandler: (() -> Void)?
    var resetHandler: (() -> Void)?
    var nextPhaseName: String?
    var startNextPhaseHandler: (() -> Void)?
    var skipBreakHandler: (() -> Void)?
    var skipBreakName = "Skip Short Break"
    var resumePomodoroHandler: (() -> Void)?
    var willSuspendPomodoro = false
    var suspendEveryFace = false
    var longBreakDue = false
    var pomodoroSuspended = false
    var activeDisplayFaceIndex = 0
    var borderless = false
    var alwaysOnTop = false
    var replacingActiveSession = false
    var displayAction = "Start"
    var interactive = false
    private var mouseStart: NSPoint?
    private var previousPoint: NSPoint?
    private var didDrag = false
    private var windowMoveStart: (pointer: NSPoint, origin: NSPoint)?
    private var movedWindow = false
    private var hoveredTarget: CubeHoverTarget?
    private var pointerTrackingArea: NSTrackingArea?
    private var pendingHoverRefresh: DispatchWorkItem?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed {
            resizeHandler?(bounds.size)
            setNeedsDisplay(bounds)
            scheduleHoverRefresh()
        }
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTrackingArea = area
        window?.acceptsMouseMovedEvents = true
        super.updateTrackingAreas()
        scheduleHoverRefresh()
    }

    private func scheduleHoverRefresh() {
        pendingHoverRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in self?.refreshHover() }
        pendingHoverRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: refresh)
    }

    override func mouseMoved(with event: NSEvent) {
        guard mouseStart == nil && windowMoveStart == nil else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    fileprivate func refreshHover() {
        guard mouseStart == nil && windowMoveStart == nil, let window else { return }
        updateHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func updateHover(at point: NSPoint) {
        let target = bounds.contains(point) ? interactiveTarget(at: point) : nil
        if hoveredTarget != target {
            hoveredTarget = target
            hoverHandler?(target)
        }
        switch target {
        case .display:
            toolTip = "Click to \(displayAction.lowercased()) timer"
        case .preset(let faceIndex):
            let preset = CubeFace(rawValue: faceIndex)?.preset
            if willSuspendPomodoro && longBreakDue {
                toolTip = "Click to start a one-off timer. Your long break stays due."
            } else if willSuspendPomodoro && (suspendEveryFace || preset != 0 && preset != 2) {
                toolTip = "Click to pause Pomodoro and start this one-off timer. Resume Pomodoro later."
            } else if pomodoroSuspended {
                toolTip = "Click to start this one-off timer. Your Pomodoro stays paused."
            } else {
                toolTip = replacingActiveSession
                    ? "Click to replace current timer and start this preset. Undo is available for six seconds."
                    : "Click to select and start this preset"
            }
        case nil:
            toolTip = nil
        }
        (target == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
    }

    private func clearHover() {
        hoveredTarget = nil
        hoverHandler?(nil)
        toolTip = nil
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        if borderless && event.modifierFlags.contains(.control) {
            beginWindowMove()
            return
        }
        mouseStart = convert(event.locationInWindow, from: nil)
        previousPoint = mouseStart
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        if windowMoveStart != nil {
            updateWindowMove()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let previousPoint, let mouseStart else { return }
        if !didDrag && hypot(point.x - mouseStart.x, point.y - mouseStart.y) > 5 {
            didDrag = true
            clearHover()
        }
        if didDrag {
            dragHandler?(point.x - previousPoint.x, point.y - previousPoint.y)
        }
        self.previousPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        if windowMoveStart != nil {
            finishWindowMove(with: event)
            return
        }
        let wasDragging = didDrag
        mouseStart = nil
        previousPoint = nil
        didDrag = false
        if wasDragging {
            updateHover(at: convert(event.locationInWindow, from: nil))
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if !borderless && event.modifierFlags.contains(.control) {
            showContextMenu(at: point)
            return
        }
        guard let target = interactiveTarget(at: point) else {
            updateHover(at: point)
            return
        }
        switch target {
        case .display:
            displayClickHandler?()
            updateHover(at: point)
        case .preset(let index):
            clearHover()
            clickHandler?(index)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if borderless && event.modifierFlags.contains(.control) {
            beginWindowMove()
            return
        }
        showContextMenu(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if windowMoveStart != nil { updateWindowMove() }
    }

    override func rightMouseUp(with event: NSEvent) {
        if windowMoveStart != nil { finishWindowMove(with: event) }
    }

    private func beginWindowMove() {
        guard let window else { return }
        clearHover()
        windowMoveStart = (NSEvent.mouseLocation, window.frame.origin)
        movedWindow = false
        mouseStart = nil
        previousPoint = nil
        didDrag = false
    }

    private func updateWindowMove() {
        guard let window, let start = windowMoveStart else { return }
        let pointer = NSEvent.mouseLocation
        let dx = pointer.x - start.pointer.x
        let dy = pointer.y - start.pointer.y
        guard movedWindow || hypot(dx, dy) > 5 else { return }
        movedWindow = true
        let proposed = NSPoint(x: start.origin.x + dx, y: start.origin.y + dy)
        let origin = BorderlessWindowPosition.clampedOrigin(
            proposed, size: window.frame.size,
            visibleFrames: NSScreen.screens.map(\.visibleFrame))
        window.setFrameOrigin(origin)
    }

    private func finishWindowMove(with event: NSEvent) {
        let shouldShowMenu = !movedWindow
        windowMoveStart = nil
        movedWindow = false
        if shouldShowMenu {
            showContextMenu(at: convert(event.locationInWindow, from: nil))
        }
    }

    private func showContextMenu(with event: NSEvent) {
        guard let menu = contextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func showContextMenu(at point: NSPoint) {
        contextMenu()?.popUp(positioning: nil, at: point, in: self)
    }

    private func contextMenu() -> NSMenu? {
        guard openSettingsHandler != nil else { return nil }
        let menu = NSMenu(title: "PomoFloat")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings),
                                  keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let mode = NSMenuItem(title: "Borderless Window", action: #selector(toggleBorderless),
                              keyEquivalent: "")
        mode.target = self
        mode.state = borderless ? .on : .off
        menu.addItem(mode)
        let floating = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop),
                                  keyEquivalent: "")
        floating.target = self
        floating.state = alwaysOnTop ? .on : .off
        menu.addItem(floating)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset Timer", action: #selector(resetTimer),
                               keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        if let nextPhaseName, startNextPhaseHandler != nil {
            let next = NSMenuItem(title: "Start \(nextPhaseName)", action: #selector(startNextPhase),
                                  keyEquivalent: "")
            next.target = self
            menu.addItem(next)
        }
        if skipBreakHandler != nil {
            let skip = NSMenuItem(title: skipBreakName, action: #selector(skipBreak),
                                  keyEquivalent: "")
            skip.target = self
            menu.addItem(skip)
        }
        if resumePomodoroHandler != nil {
            let resume = NSMenuItem(title: "Resume Pomodoro", action: #selector(resumePomodoro),
                                    keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide PomoFloat", action: #selector(hideApp),
                              keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    @objc private func openSettings() { openSettingsHandler?() }
    @objc private func toggleBorderless() { toggleBorderlessHandler?() }
    @objc private func toggleAlwaysOnTop() { toggleAlwaysOnTopHandler?() }
    @objc private func resetTimer() { resetHandler?() }
    @objc private func startNextPhase() { startNextPhaseHandler?() }
    @objc private func skipBreak() { skipBreakHandler?() }
    @objc private func resumePomodoro() { resumePomodoroHandler?() }
    @objc private func hideApp() { NSApp.hide(nil) }

    private func interactiveTarget(at point: NSPoint) -> CubeHoverTarget? {
        guard interactive, let hit = faceHit(at: point) else { return nil }
        if hit.isDisplay { return .display(hit.index) }
        return hit.index == activeDisplayFaceIndex ? nil : .preset(hit.index)
    }

    private func faceHit(at point: NSPoint) -> (index: Int, isDisplay: Bool)? {
        guard let hit = hitTest(point, options: [.firstFoundOnly: true,
                                                 .categoryBitMask: 1]).first else { return nil }
        var node: SCNNode? = hit.node
        while let current = node {
            if let name = current.name, name.hasPrefix("face-"),
               let index = Int(name.dropFirst(5)) {
                let surface = current.parent ?? current
                let local = surface.convertPosition(hit.worldCoordinates, from: nil)
                let inCircle = hypot(local.x, local.y) <= 0.76
                return (index, index == activeDisplayFaceIndex && inCircle)
            }
            node = current.parent
        }
        return nil
    }
}

private enum CubeFaceGraphics {
    private static let size = 1024

    static func hoverOutline(accent: RGBColor, display: Bool) -> NSImage {
        image { context in
            let path: CGPath
            if display {
                path = CGPath(ellipseIn: CGRect(x: 100, y: 100, width: 824, height: 824),
                              transform: nil)
            } else {
                path = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                              cornerWidth: 125, cornerHeight: 125, transform: nil)
            }
            context.addPath(path)
            context.setLineWidth(display ? 12 : 14)
            context.setStrokeColor(accent.nsColor.withAlphaComponent(0.64).cgColor)
            context.setShadow(offset: .zero, blur: 20,
                              color: accent.nsColor.withAlphaComponent(0.38).cgColor)
            context.strokePath()
        }
    }

    static func label(seconds: Int, body: RGBColor) -> NSImage {
        image { context in
            let ink = body.luminance > 0.58
                ? NSColor(calibratedWhite: 0.15, alpha: 0.87)
                : NSColor(calibratedWhite: 0.97, alpha: 0.94)
            let wholeMinutes = seconds % 60 == 0
            let number = wholeMinutes
                ? String(seconds / 60)
                : TimerEngine.display(TimeInterval(seconds))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(body.luminance > 0.58 ? 0.06 : 0.3)
            shadow.shadowBlurRadius = 16
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            number.draw(in: NSRect(x: 45, y: 335, width: 934, height: 410), withAttributes: [
                .font: NSFont.systemFont(ofSize: wholeMinutes ? 395 : 240, weight: .heavy),
                .foregroundColor: ink,
                .paragraphStyle: paragraph,
                .shadow: shadow
            ])
            (wholeMinutes ? "MIN" : "M : S").draw(
                in: NSRect(x: 95, y: 270, width: 834, height: 125), withAttributes: [
                .font: NSFont.systemFont(ofSize: 89, weight: .bold),
                .foregroundColor: ink.withAlphaComponent(0.75),
                .paragraphStyle: paragraph
            ])
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func display(time: String, accent: RGBColor, digits: RGBColor,
                        litSegments: Int, completed: Bool,
                        focusMarks: CubeFocusProgress?, sessionLabel: String?,
                        emphasis: CGFloat) -> NSImage {
        image { context in
            let center = CGPoint(x: 512, y: 512)
            let outer = CGRect(x: 102, y: 102, width: 820, height: 820)
            context.setShadow(offset: CGSize(width: 0, height: -15), blur: 32,
                              color: NSColor.black.withAlphaComponent(0.68).cgColor)
            context.setFillColor(NSColor(calibratedWhite: 0.025, alpha: 1).cgColor)
            context.fillEllipse(in: outer)
            context.setShadow(offset: .zero, blur: 0)

            context.setLineWidth(16)
            context.setStrokeColor(NSColor(calibratedWhite: 0.012, alpha: 1).cgColor)
            context.strokeEllipse(in: outer.insetBy(dx: 7, dy: 7))
            context.setLineWidth(7)
            context.setStrokeColor(NSColor(calibratedWhite: 0.19, alpha: 0.8).cgColor)
            context.strokeEllipse(in: outer.insetBy(dx: 24, dy: 24))

            for segment in 0..<60 {
                let angle = Double.pi / 2 - Double(segment) * 2 * Double.pi / 60
                let inner = CGFloat(301) - 6 * emphasis
                let outer = CGFloat(350) + 5 * emphasis
                context.move(to: CGPoint(x: center.x + cos(angle) * inner,
                                         y: center.y + sin(angle) * inner))
                context.addLine(to: CGPoint(x: center.x + cos(angle) * outer,
                                            y: center.y + sin(angle) * outer))
                context.setLineWidth(16 + 6 * emphasis)
                context.setLineCap(.round)
                let active = completed || segment < litSegments
                let alpha: CGFloat = active ? (completed ? 1 : 0.94) : 0.15
                context.setStrokeColor(accent.nsColor.withAlphaComponent(alpha).cgColor)
                if active {
                    context.setShadow(offset: .zero, blur: completed ? 20 : 10,
                                      color: accent.nsColor.withAlphaComponent(0.75).cgColor)
                }
                context.strokePath()
                context.setShadow(offset: .zero, blur: 0)
            }

            let digitColor = digits.nsColor
            let halo = digits.luminance < 0.35
                ? NSColor.white.withAlphaComponent(0.55)
                : digitColor.withAlphaComponent(0.78)
            context.setShadow(offset: .zero, blur: 14, color: halo.cgColor)
            let positions: [CGFloat] = [250, 370, 540, 660]
            let chars = Array(time.filter { $0.isNumber })
            for (index, x) in positions.enumerated() where index < chars.count {
                drawDigit(chars[index], x: x, y: 425, context: context,
                          color: digitColor, strokeWidth: 17 + 5 * emphasis)
            }
            context.setFillColor(digitColor.cgColor)
            let dotSize = 19 + 3 * emphasis
            context.fillEllipse(in: CGRect(x: 497, y: 466, width: dotSize, height: dotSize))
            context.fillEllipse(in: CGRect(x: 497, y: 541, width: dotSize, height: dotSize))
            context.setShadow(offset: .zero, blur: 0)
            if let focusMarks {
                let count = min(8, max(2, focusMarks.target))
                let filled = min(count, max(0, focusMarks.completed))
                let spacing = min(CGFloat(78), 360 / CGFloat(count - 1))
                let diameter: CGFloat = count <= 4 ? 42 : 36
                for index in 0..<count {
                    let centerX = 512 - spacing * CGFloat(count - 1) / 2 +
                        spacing * CGFloat(index)
                    let mark = CGRect(x: centerX - diameter / 2, y: 272,
                                      width: diameter, height: diameter)
                    if index < filled {
                        context.setFillColor(accent.nsColor.cgColor)
                        context.fillEllipse(in: mark)
                    }
                    context.setLineWidth(9 + 2 * emphasis)
                    context.setStrokeColor(digitColor.withAlphaComponent(0.78).cgColor)
                    context.strokeEllipse(in: mark.insetBy(dx: 4, dy: 4))
                }
            }
            if let sessionLabel {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                sessionLabel.draw(in: NSRect(x: 235, y: 678, width: 554, height: 66),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 52, weight: .heavy),
                                                   .foregroundColor: digitColor,
                                                   .paragraphStyle: paragraph])
                NSGraphicsContext.restoreGraphicsState()
            }
            if completed {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                "DONE".draw(in: NSRect(x: 360, y: 330, width: 304, height: 72),
                            withAttributes: [.font: NSFont.systemFont(ofSize: 57, weight: .heavy),
                                             .foregroundColor: accent.nsColor,
                                             .paragraphStyle: paragraph])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    private static func drawDigit(_ digit: Character, x: CGFloat, y: CGFloat,
                                  context: CGContext, color: NSColor,
                                  strokeWidth: CGFloat) {
        let bits: [Character: Set<Int>] = [
            "0": [0, 1, 2, 3, 4, 5], "1": [1, 2],
            "2": [0, 1, 6, 4, 3], "3": [0, 1, 6, 2, 3],
            "4": [5, 6, 1, 2], "5": [0, 5, 6, 2, 3],
            "6": [0, 5, 6, 4, 2, 3], "7": [0, 1, 2],
            "8": [0, 1, 2, 3, 4, 5, 6], "9": [0, 1, 2, 3, 5, 6]
        ]
        let segments: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (x + 15, y + 170, x + 85, y + 170),
            (x + 96, y + 160, x + 96, y + 98),
            (x + 96, y + 78, x + 96, y + 16),
            (x + 15, y + 6, x + 85, y + 6),
            (x + 4, y + 78, x + 4, y + 16),
            (x + 4, y + 160, x + 4, y + 98),
            (x + 15, y + 88, x + 85, y + 88)
        ]
        for (index, segment) in segments.enumerated() {
            context.move(to: CGPoint(x: segment.0, y: segment.1))
            context.addLine(to: CGPoint(x: segment.2, y: segment.3))
            context.setLineCap(.round)
            context.setLineWidth(strokeWidth)
            context.setStrokeColor(color.withAlphaComponent(bits[digit]?.contains(index) == true ? 1 : 0.075).cgColor)
            context.strokePath()
        }
    }

    private static func image(_ draw: (CGContext) -> Void) -> NSImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        draw(context)
        return NSImage(cgImage: context.makeImage()!,
                       size: NSSize(width: size, height: size))
    }
}
