//
//  EngineWindow.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import AppKit
import MetalKit

private final class EngineMTKView: MTKView {
    weak var eventHandler: EventHandler?
    private var trackingArea: NSTrackingArea?

    init(frame frameRect: NSRect, device: MTLDevice, eventHandler: EventHandler?) {
        self.eventHandler = eventHandler
        super.init(frame: frameRect, device: device)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let mouseEvent = MouseButtonPressedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        if mouseEvent.handled {
            Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
        } else {
            Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let mouseEvent = MouseButtonReleasedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        let mouseEvent = MouseButtonPressedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        if mouseEvent.handled {
            Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
        } else {
            Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let mouseEvent = MouseButtonReleasedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }

    override func otherMouseDown(with event: NSEvent) {
        let mouseEvent = MouseButtonPressedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        if mouseEvent.handled {
            Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
        } else {
            Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        let mouseEvent = MouseButtonReleasedEvent(button: Int(event.buttonNumber))
        eventHandler?.dispatch(mouseEvent)
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }

    override func mouseMoved(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let scrollEvent = MouseScrolledEvent(deltaY: Float(event.deltaY))
        eventHandler?.dispatch(scrollEvent)
        if !scrollEvent.handled {
            Mouse.ScrollMouse(deltaY: Float(event.deltaY))
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
            Mouse.SetMousePositionChange(overallPosition: overallLocation, deltaPosition: deltaChange)
        }
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
    public func create(with spec: ApplicationSpecification, device: MTLDevice) {
        let style: NSWindow.StyleMask = {
            var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            if spec.resizable { mask.insert(.resizable) }
            return mask
        }()

        let size = NSSize(width: spec.width, height: spec.height)
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = spec.title

        let view = EngineMTKView(frame: rect, device: device, eventHandler: self.eventHandler)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = spec.colorPixelFormat ?? Preferences.defaultColorPixelFormat
        view.depthStencilPixelFormat = spec.depthStencilPixelFormat ?? Preferences.defaultDepthPixelFormat
        view.sampleCount = spec.sampleCount
        view.preferredFramesPerSecond = spec.preferredFramesPerSecond
        view.clearColor = Preferences.clearColor
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        window.contentView = view
        window.acceptsMouseMovedEvents = true
        if spec.centered { window.center() }
        window.makeKeyAndOrderFront(nil)

        self.nsWindow = window
        self.mtkView = view
        installKeyEventMonitor()
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            let keyEvent = KeyPressedEvent(keyCode: event.keyCode, isRepeat: event.isARepeat)
            eventHandler?.dispatch(keyEvent)
            if keyEvent.handled {
                Keyboard.SetKeyPressed(event.keyCode, isOn: false)
            } else {
                Keyboard.SetKeyPressed(event.keyCode, isOn: true)
            }
        case .keyUp:
            let keyEvent = KeyReleasedEvent(keyCode: event.keyCode)
            eventHandler?.dispatch(keyEvent)
            Keyboard.SetKeyPressed(event.keyCode, isOn: false)
        case .flagsChanged:
            updateModifier(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        default:
            break
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
            if keyEvent.handled {
                Keyboard.SetKeyPressed(keyCode, isOn: false)
            } else {
                Keyboard.SetKeyPressed(keyCode, isOn: isOn)
            }
        case KeyCodes.command.rawValue:
            let isOn = modifierFlags.contains(.command)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            if keyEvent.handled {
                Keyboard.SetKeyPressed(keyCode, isOn: false)
            } else {
                Keyboard.SetKeyPressed(keyCode, isOn: isOn)
            }
        case KeyCodes.option.rawValue, KeyCodes.rightOption.rawValue:
            let isOn = modifierFlags.contains(.option)
            let keyEvent: Event = isOn
                ? KeyPressedEvent(keyCode: keyCode, isRepeat: false)
                : KeyReleasedEvent(keyCode: keyCode)
            eventHandler?.dispatch(keyEvent)
            if keyEvent.handled {
                Keyboard.SetKeyPressed(keyCode, isOn: false)
            } else {
                Keyboard.SetKeyPressed(keyCode, isOn: isOn)
            }
        default:
            break
        }
    }
}
