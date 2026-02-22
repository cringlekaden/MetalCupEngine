/// EngineWindow.swift
/// Defines the EngineWindow types and helpers for the engine.
/// Created by Kaden Cringle.

import AppKit
import MetalKit
import Darwin

private final class EngineMTKView: MTKView {
    weak var eventHandler: EventHandler?
    private var trackingArea: NSTrackingArea?
    private let inputAccumulator: InputAccumulator
    private let imguiHandleEvent: (@convention(c) (AnyObject, AnyObject) -> Bool)?
    private let imguiWantsKeyboard: (@convention(c) () -> Bool)?

    init(frame frameRect: NSRect, device: MTLDevice, eventHandler: EventHandler?, inputAccumulator: InputAccumulator) {
        self.eventHandler = eventHandler
        self.inputAccumulator = inputAccumulator
        self.imguiHandleEvent = EngineMTKView.resolveImGuiHandleEvent()
        self.imguiWantsKeyboard = EngineMTKView.resolveImGuiWantsKeyboard()
        super.init(frame: frameRect, device: device)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        _ = imguiHandleEvent?(event, self)
        let keyEvent = KeyPressedEvent(keyCode: event.keyCode, isRepeat: event.isARepeat)
        eventHandler?.dispatch(keyEvent)
        if !keyEvent.handled {
            appendTextInput(from: event)
        }
        inputAccumulator.setKeyPressed(event.keyCode, isOn: !keyEvent.handled)
        if shouldPropagateToSystem(event: event) {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = imguiHandleEvent?(event, self)
        let keyEvent = KeyReleasedEvent(keyCode: event.keyCode)
        eventHandler?.dispatch(keyEvent)
        inputAccumulator.setKeyPressed(event.keyCode, isOn: false)
        if shouldPropagateToSystem(event: event) {
            super.keyUp(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        _ = imguiHandleEvent?(event, self)
        updateModifier(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        if shouldPropagateToSystem(event: event) {
            super.flagsChanged(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let mouseEvent = MouseButtonPressedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        if mouseEvent.handled {
            inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: false)
        } else {
            inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let mouseEvent = MouseButtonReleasedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        let mouseEvent = MouseButtonPressedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        if mouseEvent.handled {
            inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: false)
        } else {
            inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: true)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let mouseEvent = MouseButtonReleasedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: false)
    }

    override func otherMouseDown(with event: NSEvent) {
        let mouseEvent = MouseButtonPressedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        if mouseEvent.handled {
            inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: false)
        } else {
            inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: true)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        let mouseEvent = MouseButtonReleasedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        inputAccumulator.setMouseButton(button: Int(event.buttonNumber), isOn: false)
    }

    override func mouseMoved(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let scrollEvent = MouseScrolledEvent(deltaY: Float(event.deltaY))
        eventHandler?.dispatch(scrollEvent)
        if !scrollEvent.handled {
            inputAccumulator.scroll(deltaY: Float(event.deltaY))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }

    private func setMousePositionChanged(event: NSEvent){
        let overallLocation = SIMD2<Float>(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        let deltaChange = SIMD2<Float>(Float(event.deltaX), Float(event.deltaY))
        let moveEvent = MouseMovedEvent(position: overallLocation, delta: deltaChange)
        eventHandler?.dispatch(moveEvent)
        if !moveEvent.handled {
            inputAccumulator.setMousePositionChange(overallPosition: overallLocation, deltaPosition: deltaChange)
        }
    }

    private func updateModifier(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        switch keyCode {
        case KeyCodes.shift.rawValue:
            let isOn = modifierFlags.contains(.shift)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            inputAccumulator.setKeyPressed(keyCode, isOn: !keyEvent.handled && isOn)
        case KeyCodes.command.rawValue:
            let isOn = modifierFlags.contains(.command)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            inputAccumulator.setKeyPressed(keyCode, isOn: !keyEvent.handled && isOn)
        case KeyCodes.option.rawValue, KeyCodes.rightOption.rawValue:
            let isOn = modifierFlags.contains(.option)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            inputAccumulator.setKeyPressed(keyCode, isOn: !keyEvent.handled && isOn)
        default:
            break
        }
    }

    private func appendTextInput(from event: NSEvent) {
        guard let characters = event.characters, !characters.isEmpty else { return }
        if shouldAppendCharacters(characters) {
            inputAccumulator.appendText(characters)
        }
    }

    private func shouldAppendCharacters(_ characters: String) -> Bool {
        for scalar in characters.unicodeScalars {
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return false
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                return false
            }
        }
        return true
    }

    private func shouldPropagateToSystem(event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            return !(imguiWantsKeyboard?() ?? false)
        }
        return false
    }

    private static func resolveImGuiHandleEvent() -> (@convention(c) (AnyObject, AnyObject) -> Bool)? {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "MCEImGuiHandleEvent") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AnyObject, AnyObject) -> Bool).self)
    }

    private static func resolveImGuiWantsKeyboard() -> (@convention(c) () -> Bool)? {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "MCEImGuiWantsCaptureKeyboard") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
}

/// Engine-owned window that hosts an MTKView. The editor/app constructs this through Application.
public final class EngineWindow: NSObject {
    public private(set) var nsWindow: NSWindow!
    public private(set) var mtkView: MTKView!
    public let inputAccumulator = InputAccumulator()
    public weak var eventHandler: EventHandler?
    private var keyEventMonitor: Any?

    public override init() {
        super.init()
    }

    deinit {
        if let keyEventMonitor = keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    /// Creates an NSWindow and an MTKView configured per the provided spec.
    /// - Parameters:
    ///   - spec: Window and surface configuration.
    ///   - device: Metal device used by the MTKView.
    public func create(with spec: ApplicationSpecification, device: MTLDevice, preferences: Preferences) {
        let style: NSWindow.StyleMask = {
            var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            if spec.resizable { mask.insert(.resizable) }
            return mask
        }()

        let size = NSSize(width: spec.width, height: spec.height)
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = spec.title

        let view = EngineMTKView(frame: rect, device: device, eventHandler: self.eventHandler, inputAccumulator: inputAccumulator)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = spec.colorPixelFormat ?? preferences.defaultColorPixelFormat
        view.depthStencilPixelFormat = spec.depthStencilPixelFormat ?? preferences.defaultDepthPixelFormat
        view.sampleCount = spec.sampleCount
        view.preferredFramesPerSecond = spec.preferredFramesPerSecond
        view.clearColor = preferences.clearColor
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        window.contentView = view
        window.acceptsMouseMovedEvents = true
        if let screen = window.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            window.setFrame(visibleFrame, display: true)
            window.center()
        } else if spec.centered {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)

        self.nsWindow = window
        self.mtkView = view
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            _ = self.handleKeyEvent(event)
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            let keyEvent = KeyPressedEvent(keyCode: event.keyCode, isRepeat: event.isARepeat)
            eventHandler?.dispatch(keyEvent)
            if !keyEvent.handled {
                appendTextInput(from: event)
            }
            if keyEvent.handled {
                inputAccumulator.setKeyPressed(event.keyCode, isOn: false)
            } else {
                inputAccumulator.setKeyPressed(event.keyCode, isOn: true)
            }
            return true
        case .keyUp:
            let keyEvent = KeyReleasedEvent(keyCode: event.keyCode)
            eventHandler?.dispatch(keyEvent)
            inputAccumulator.setKeyPressed(event.keyCode, isOn: false)
            return true
        case .flagsChanged:
            updateModifier(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            return true
        default:
            return false
        }
    }

    private func appendTextInput(from event: NSEvent) {
        guard let characters = event.characters, !characters.isEmpty else { return }
        if shouldAppendCharacters(characters) {
            inputAccumulator.appendText(characters)
        }
    }

    private func shouldAppendCharacters(_ characters: String) -> Bool {
        for scalar in characters.unicodeScalars {
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return false
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                return false
            }
        }
        return true
    }

    private func updateModifier(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        switch keyCode {
        case KeyCodes.shift.rawValue:
            let isOn = modifierFlags.contains(.shift)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            if keyEvent.handled {
                inputAccumulator.setKeyPressed(keyCode, isOn: false)
            } else {
                inputAccumulator.setKeyPressed(keyCode, isOn: isOn)
            }
        case KeyCodes.command.rawValue:
            let isOn = modifierFlags.contains(.command)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            if keyEvent.handled {
                inputAccumulator.setKeyPressed(keyCode, isOn: false)
            } else {
                inputAccumulator.setKeyPressed(keyCode, isOn: isOn)
            }
        case KeyCodes.option.rawValue, KeyCodes.rightOption.rawValue:
            let isOn = modifierFlags.contains(.option)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            if keyEvent.handled {
                inputAccumulator.setKeyPressed(keyCode, isOn: false)
            } else {
                inputAccumulator.setKeyPressed(keyCode, isOn: isOn)
            }
        default:
            break
        }
    }
}
