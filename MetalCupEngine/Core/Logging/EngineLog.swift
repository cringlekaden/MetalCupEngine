/// EngineLog.swift
/// Centralized engine logging and assertions.
/// Created by Kaden Cringle.

import Foundation

public enum MCLogLevel: Int32 {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
}

public enum MCLogCategory: Int32 {
    case core = 0
    case editor = 1
    case project = 2
    case scene = 3
    case assets = 4
    case renderer = 5
    case serialization = 6
    case input = 7
}

public struct MCLogEntry {
    public let timestamp: TimeInterval
    public let level: MCLogLevel
    public let category: MCLogCategory
    public let message: String
}

public final class EngineLog {
    public static let shared = EngineLog()

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [MCLogEntry?]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var revision: UInt64 = 0

    public init(capacity: Int = 4096) {
        self.capacity = max(128, capacity)
        self.entries = Array(repeating: nil, count: self.capacity)
    }

    public func log(_ message: String, level: MCLogLevel, category: MCLogCategory) {
        let entry = MCLogEntry(timestamp: Date().timeIntervalSince1970,
                               level: level,
                               category: category,
                               message: message)
        lock.lock()
        entries[writeIndex] = entry
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
        revision &+= 1
        lock.unlock()
    }

    public func logDebug(_ message: String, category: MCLogCategory) {
        log(message, level: .debug, category: category)
    }

    public func logInfo(_ message: String, category: MCLogCategory) {
        log(message, level: .info, category: category)
    }

    public func logWarning(_ message: String, category: MCLogCategory) {
        log(message, level: .warning, category: category)
    }

    public func logError(_ message: String, category: MCLogCategory) {
        log(message, level: .error, category: category)
    }

    public func entryCount() -> Int {
        lock.lock()
        let value = count
        lock.unlock()
        return value
    }

    public func entry(at index: Int) -> MCLogEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < count else { return nil }
        let start = (writeIndex - count + capacity) % capacity
        let slot = (start + index) % capacity
        return entries[slot]
    }

    public func clear() {
        lock.lock()
        entries = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
        revision &+= 1
        lock.unlock()
    }

    public func revisionToken() -> UInt64 {
        lock.lock()
        let value = revision
        lock.unlock()
        return value
    }
}

@inline(__always)
public func MC_ASSERT(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") {
#if DEBUG
    if !condition() {
        let text = message()
        if !text.isEmpty {
            EngineLog.shared.logError("Assert failed: \(text)", category: .core)
        } else {
            EngineLog.shared.logError("Assert failed.", category: .core)
        }
        raise(SIGTRAP)
    }
#endif
}

@inline(__always)
public func MC_CORE_ASSERT(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") {
#if DEBUG
    if !condition() {
        let text = message()
        if !text.isEmpty {
            EngineLog.shared.logError("Core assert failed: \(text)", category: .core)
        } else {
            EngineLog.shared.logError("Core assert failed.", category: .core)
        }
        raise(SIGTRAP)
    }
#endif
}
