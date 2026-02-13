/// Events.swift
/// Defines the Events types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

// Base event type with handled flag for early-out propagation.
public class Event {
    public var handled: Bool = false
    public var name: String { String(describing: type(of: self)) }
    public init() {}
}

// MARK: - Keyboard Events

public final class KeyPressedEvent: Event {
    public let keyCode: UInt16
    public let isRepeat: Bool
    public init(keyCode: UInt16, isRepeat: Bool) {
        self.keyCode = keyCode
        self.isRepeat = isRepeat
        super.init()
    }
}

public final class KeyReleasedEvent: Event {
    public let keyCode: UInt16
    public init(keyCode: UInt16) {
        self.keyCode = keyCode
        super.init()
    }
}

// MARK: - Mouse Events

public final class MouseMovedEvent: Event {
    public let position: SIMD2<Float>
    public let delta: SIMD2<Float>
    public init(position: SIMD2<Float>, delta: SIMD2<Float>) {
        self.position = position
        self.delta = delta
        super.init()
    }
}

public final class MouseScrolledEvent: Event {
    public let deltaY: Float
    public init(deltaY: Float) {
        self.deltaY = deltaY
        super.init()
    }
}

public final class MouseButtonPressedEvent: Event {
    public let button: Int
    public init(button: Int) {
        self.button = button
        super.init()
    }
}

public final class MouseButtonReleasedEvent: Event {
    public let button: Int
    public init(button: Int) {
        self.button = button
        super.init()
    }
}

// MARK: - Event Handler Protocol

public protocol EventHandler: AnyObject {
    func dispatch(_ event: Event)
}
