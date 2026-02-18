/// EngineLogger.swift
/// Sink-based engine logging and assertions.
/// Created by Kaden Cringle.

import Foundation

public enum MCLogLevel: Int32 {
    case trace = -1
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

public protocol EngineLogSink: AnyObject {
    func receive(_ entry: MCLogEntry)
}

public final class EngineLogger {
    private let lock = NSLock()
    private let capacity: Int
    private var entries: [MCLogEntry?]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var revision: UInt64 = 0
    private var sinks: [EngineLogSink] = []

    public init(capacity: Int = 4096) {
        self.capacity = max(128, capacity)
        self.entries = Array(repeating: nil, count: self.capacity)
    }

    public func addSink(_ sink: EngineLogSink) {
        lock.lock()
        if !sinks.contains(where: { ObjectIdentifier($0) == ObjectIdentifier(sink) }) {
            sinks.append(sink)
        }
        lock.unlock()
    }

    public func removeSink(_ sink: EngineLogSink) {
        let id = ObjectIdentifier(sink)
        lock.lock()
        sinks.removeAll { ObjectIdentifier($0) == id }
        lock.unlock()
    }

    public func log(_ message: String, level: MCLogLevel, category: MCLogCategory) {
        let entry = MCLogEntry(
            timestamp: Date().timeIntervalSince1970,
            level: level,
            category: category,
            message: message
        )
        lock.lock()
        entries[writeIndex] = entry
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
        revision &+= 1
        let sinksSnapshot = sinks
        lock.unlock()
        for sink in sinksSnapshot {
            sink.receive(entry)
        }
    }

    public func logTrace(_ message: String, category: MCLogCategory) {
        log(message, level: .trace, category: category)
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

public enum EngineLoggerContext {
    private static let lock = NSLock()
    private static weak var logger: EngineLogger?

    public static func install(_ logger: EngineLogger) {
        lock.lock()
        self.logger = logger
        lock.unlock()
    }

    public static func currentLogger() -> EngineLogger? {
        lock.lock()
        let value = logger
        lock.unlock()
        return value
    }

    public static func log(_ message: String, level: MCLogLevel, category: MCLogCategory) {
        currentLogger()?.log(message, level: level, category: category)
    }
}

@inline(__always)
public func MCE_ASSERT(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") {
    if !condition() {
        let text = message()
        if text.isEmpty {
            EngineLoggerContext.log("Assert failed.", level: .error, category: .core)
        } else {
            EngineLoggerContext.log("Assert failed: \(text)", level: .error, category: .core)
        }
        #if DEBUG
        raise(SIGTRAP)
        #endif
    }
}

@inline(__always)
@discardableResult
public func MCE_VERIFY(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") -> Bool {
    if condition() {
        return true
    }
    let text = message()
    if text.isEmpty {
        EngineLoggerContext.log("Verify failed.", level: .warning, category: .core)
    } else {
        EngineLoggerContext.log("Verify failed: \(text)", level: .warning, category: .core)
    }
    return false
}

@inline(__always)
public func MC_ASSERT(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") {
    MCE_ASSERT(condition(), message())
}

@inline(__always)
public func MC_CORE_ASSERT(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") {
    MCE_ASSERT(condition(), message())
}
