//
//  EngineWindow.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import AppKit
import MetalKit

// Internal MTKView subclass that captures input and forwards to engine input systems
private final class EngineMTKView: MTKView {
    weak var eventHandler: EventHandler?

    init(frame frameRect: NSRect, device: MTLDevice, eventHandler: EventHandler?) {
        self.eventHandler = eventHandler
        super.init(frame: frameRect, device: device)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        Keyboard.SetKeyPressed(event.keyCode, isOn: true)
        eventHandler?.dispatch(KeyPressedEvent(keyCode: event.keyCode, isRepeat: event.isARepeat))
    }

    override func keyUp(with event: NSEvent) {
        Keyboard.SetKeyPressed(event.keyCode, isOn: false)
        eventHandler?.dispatch(KeyReleasedEvent(keyCode: event.keyCode))
    }

    override func mouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        eventHandler?.dispatch(MouseButtonPressedEvent(button: Int(event.buttonNumber)))
    }

    override func mouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
        eventHandler?.dispatch(MouseButtonReleasedEvent(button: Int(event.buttonNumber)))
    }

    override func rightMouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        eventHandler?.dispatch(MouseButtonPressedEvent(button: Int(event.buttonNumber)))
    }

    override func rightMouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
        eventHandler?.dispatch(MouseButtonReleasedEvent(button: Int(event.buttonNumber)))
    }

    override func otherMouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
        eventHandler?.dispatch(MouseButtonPressedEvent(button: Int(event.buttonNumber)))
    }

    override func otherMouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
        eventHandler?.dispatch(MouseButtonReleasedEvent(button: Int(event.buttonNumber)))
    }

    override func mouseMoved(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        Mouse.ScrollMouse(deltaY: Float(event.deltaY))
        eventHandler?.dispatch(MouseScrolledEvent(deltaY: Float(event.deltaY)))
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
        Mouse.SetMousePositionChange(overallPosition: overallLocation, deltaPosition: deltaChange)
        eventHandler?.dispatch(MouseMovedEvent(position: overallLocation, delta: deltaChange))
    }

    override func updateTrackingAreas() {
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
    }
}

/// Engine-owned window that hosts an MTKView. The editor/app constructs this through Application.
public final class EngineWindow: NSObject {
    public private(set) var nsWindow: NSWindow!
    public private(set) var mtkView: MTKView!
    public weak var eventHandler: EventHandler?

    public override init() {
        super.init()
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

        window.contentView = view
        if spec.centered { window.center() }
        window.makeFirstResponder(view)
        window.makeKeyAndOrderFront(nil)

        self.nsWindow = window
        self.mtkView = view
    }
}

