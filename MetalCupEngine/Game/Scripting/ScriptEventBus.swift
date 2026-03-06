/// ScriptEventBus.swift
/// Deterministic script event queueing for frame and fixed-step domains.
/// Created by Kaden Cringle.

import Foundation

public enum ScriptExecutionGroup: CaseIterable {
    case update
    case fixedPrePhysics
}

public final class ScriptEventBus {
    public enum Domain {
        case fixedStep
    }

    public enum Payload {
        case physics(PhysicsScriptEvent)
    }

    public struct Event {
        public let sequence: UInt64
        public let payload: Payload
    }

    private var nextSequence: UInt64 = 1
    private var fixedEvents: [Event] = []

    public init() {}

    public func clear() {
        fixedEvents.removeAll(keepingCapacity: true)
    }

    public func enqueue(_ payload: Payload, domain: Domain) {
        let event = Event(sequence: nextSequence, payload: payload)
        nextSequence &+= 1
        switch domain {
        case .fixedStep:
            fixedEvents.append(event)
        }
    }

    public func enqueuePhysicsEvents(_ events: [PhysicsScriptEvent], domain: Domain = .fixedStep) {
        guard !events.isEmpty else { return }
        for event in events {
            enqueue(.physics(event), domain: domain)
        }
    }

    public func drain(domain: Domain) -> [Event] {
        switch domain {
        case .fixedStep:
            guard !fixedEvents.isEmpty else { return [] }
            let drained = fixedEvents
            fixedEvents.removeAll(keepingCapacity: true)
            return drained
        }
    }
}
