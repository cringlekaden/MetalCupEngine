import Foundation
import simd

@_silgen_name("MCELuaExtractScriptSchema")
private func MCELuaExtractScriptSchema(_ scriptPath: UnsafePointer<CChar>?,
                                       _ typeName: UnsafePointer<CChar>?,
                                       _ jsonBuffer: UnsafeMutablePointer<CChar>?,
                                       _ jsonBufferSize: Int32,
                                       _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                       _ errorBufferSize: Int32) -> UInt32

public struct ScriptFieldDescriptor: Equatable {
    public var name: String
    public var type: ScriptFieldType
    public var defaultValue: ScriptFieldValue
    public var minValue: Float?
    public var maxValue: Float?
    public var step: Float?
    public var tooltip: String

    public init(name: String,
                type: ScriptFieldType,
                defaultValue: ScriptFieldValue,
                minValue: Float? = nil,
                maxValue: Float? = nil,
                step: Float? = nil,
                tooltip: String = "") {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.tooltip = tooltip
    }

    public var metadata: ScriptFieldMetadata {
        ScriptFieldMetadata(name: name,
                            type: type,
                            defaultValue: defaultValue,
                            minValue: minValue,
                            maxValue: maxValue,
                            step: step,
                            tooltip: tooltip)
    }
}

public enum ScriptFieldBlobCodec {
    private static let version: UInt32 = 1

    public static func decodeFieldBlobV1(_ data: Data) -> [String: ScriptFieldValue] {
        guard !data.isEmpty else { return [:] }
        var cursor = DataCursor(data: data)
        guard let blobVersion = cursor.readUInt32(), blobVersion == version,
              let entryCount = cursor.readUInt32() else {
            return [:]
        }

        var values: [String: ScriptFieldValue] = [:]
        values.reserveCapacity(Int(entryCount))
        for _ in 0..<entryCount {
            guard let nameLength = cursor.readUInt16(),
                  let name = cursor.readString(byteCount: Int(nameLength)),
                  let tag = cursor.readUInt8() else {
                break
            }
            guard let value = readValue(tag: tag, cursor: &cursor) else {
                break
            }
            values[name] = value
        }
        return values
    }

    public static func encodeFieldBlobV1(_ values: [String: ScriptFieldValue],
                                         schemaDescriptors: [ScriptFieldDescriptor]) -> Data {
        var payload = Data()
        payload.appendUInt32(version)

        let filtered = schemaDescriptors.compactMap { descriptor -> (String, ScriptFieldValue)? in
            let raw = values[descriptor.name] ?? descriptor.defaultValue
            guard let normalized = normalize(raw, to: descriptor.type) else { return nil }
            return (descriptor.name, normalized)
        }

        payload.appendUInt32(UInt32(filtered.count))
        for (name, value) in filtered {
            let nameData = name.data(using: .utf8) ?? Data()
            if nameData.count > Int(UInt16.max) { continue }
            payload.appendUInt16(UInt16(nameData.count))
            payload.append(nameData)
            writeValue(value, into: &payload)
        }
        return payload
    }

    public static func mergedValues(from blob: Data,
                                    schemaDescriptors: [ScriptFieldDescriptor]) -> [String: ScriptFieldValue] {
        let decoded = decodeFieldBlobV1(blob)
        var merged: [String: ScriptFieldValue] = [:]
        merged.reserveCapacity(schemaDescriptors.count)
        for descriptor in schemaDescriptors {
            let value = decoded[descriptor.name] ?? descriptor.defaultValue
            merged[descriptor.name] = coerce(value, to: descriptor.type) ?? descriptor.defaultValue
        }
        return merged
    }

    public static func coerce(_ value: ScriptFieldValue, to type: ScriptFieldType) -> ScriptFieldValue? {
        normalize(value, to: type)
    }

    private static func readValue(tag: UInt8, cursor: inout DataCursor) -> ScriptFieldValue? {
        switch tag {
        case 0:
            guard let byte = cursor.readUInt8() else { return nil }
            return .bool(byte != 0)
        case 1:
            guard let value = cursor.readInt32() else { return nil }
            return .int(value)
        case 2:
            guard let value = cursor.readFloat() else { return nil }
            return .float(value)
        case 3:
            guard let x = cursor.readFloat(), let y = cursor.readFloat() else { return nil }
            return .vec2(SIMD2<Float>(x, y))
        case 4:
            guard let x = cursor.readFloat(), let y = cursor.readFloat(), let z = cursor.readFloat() else { return nil }
            return .vec3(SIMD3<Float>(x, y, z))
        case 5:
            guard let x = cursor.readFloat(), let y = cursor.readFloat(), let z = cursor.readFloat() else { return nil }
            return .color3(SIMD3<Float>(x, y, z))
        case 6:
            guard let length = cursor.readUInt32(), let value = cursor.readString(byteCount: Int(length)) else { return nil }
            return .string(value)
        case 7:
            return .entity(cursor.readUUID())
        case 8:
            return .prefab(cursor.readUUID().map { AssetHandle(rawValue: $0) })
        default:
            return nil
        }
    }

    private static func writeValue(_ value: ScriptFieldValue, into data: inout Data) {
        switch value {
        case let .bool(flag):
            data.appendUInt8(0)
            data.appendUInt8(flag ? 1 : 0)
        case let .int(number):
            data.appendUInt8(1)
            data.appendInt32(number)
        case let .float(number):
            data.appendUInt8(2)
            data.appendFloat(number)
        case let .vec2(value):
            data.appendUInt8(3)
            data.appendFloat(value.x)
            data.appendFloat(value.y)
        case let .vec3(value):
            data.appendUInt8(4)
            data.appendFloat(value.x)
            data.appendFloat(value.y)
            data.appendFloat(value.z)
        case let .color3(value):
            data.appendUInt8(5)
            data.appendFloat(value.x)
            data.appendFloat(value.y)
            data.appendFloat(value.z)
        case let .string(text):
            let stringData = text.data(using: .utf8) ?? Data()
            data.appendUInt8(6)
            data.appendUInt32(UInt32(stringData.count))
            data.append(stringData)
        case let .entity(entityId):
            data.appendUInt8(7)
            data.appendUUID(entityId)
        case let .prefab(handle):
            data.appendUInt8(8)
            data.appendUUID(handle?.rawValue)
        }
    }

    private static func normalize(_ value: ScriptFieldValue, to type: ScriptFieldType) -> ScriptFieldValue? {
        switch type {
        case .bool, .boolean:
            switch value {
            case let .bool(flag): return .bool(flag)
            case let .int(number): return .bool(number != 0)
            case let .float(number): return .bool(number != 0)
            default: return nil
            }
        case .int:
            switch value {
            case let .int(number): return .int(number)
            case let .float(number): return .int(Int32(number.rounded()))
            case let .bool(flag): return .int(flag ? 1 : 0)
            default: return nil
            }
        case .float, .number:
            switch value {
            case let .float(number): return .float(number)
            case let .int(number): return .float(Float(number))
            case let .bool(flag): return .float(flag ? 1 : 0)
            default: return nil
            }
        case .vec2:
            switch value {
            case let .vec2(vec): return .vec2(vec)
            case let .vec3(vec): return .vec2(SIMD2<Float>(vec.x, vec.y))
            case let .color3(vec): return .vec2(SIMD2<Float>(vec.x, vec.y))
            default: return nil
            }
        case .vec3:
            switch value {
            case let .vec3(vec): return .vec3(vec)
            case let .color3(vec): return .vec3(vec)
            case let .vec2(vec): return .vec3(SIMD3<Float>(vec.x, vec.y, 0))
            default: return nil
            }
        case .color3:
            switch value {
            case let .color3(color): return .color3(color)
            case let .vec3(vec): return .color3(vec)
            default: return nil
            }
        case .string:
            if case let .string(text) = value { return .string(text) }
            return nil
        case .entity:
            switch value {
            case let .entity(id):
                return .entity(id)
            case let .string(text):
                return .entity(UUID(uuidString: text))
            default:
                return nil
            }
        case .prefab:
            switch value {
            case let .prefab(handle):
                return .prefab(handle)
            case let .string(text):
                guard let uuid = UUID(uuidString: text) else { return .prefab(nil) }
                return .prefab(AssetHandle(rawValue: uuid))
            default:
                return nil
            }
        }
    }
}

public final class ScriptMetadataCache {
    public static let shared = ScriptMetadataCache()

    private struct CacheKey: Hashable {
        var handle: AssetHandle
        var typeName: String
        var timestamp: Int64
    }

    private var entries: [CacheKey: [ScriptFieldDescriptor]] = [:]
    private let lock = NSLock()

    public func descriptors(scriptAssetHandle: AssetHandle,
                            typeName: String,
                            assetDatabase: AssetDatabase?) -> [ScriptFieldDescriptor] {
        guard let scriptURL = assetDatabase?.assetURL(for: scriptAssetHandle) else { return [] }
        let timestamp = ScriptMetadataCache.timestampForURL(scriptURL)
        let key = CacheKey(handle: scriptAssetHandle,
                           typeName: typeName,
                           timestamp: timestamp)

        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let descriptors = extractSchema(scriptURL: scriptURL, typeName: typeName)

        lock.lock()
        entries[key] = descriptors
        lock.unlock()
        return descriptors
    }

    public func invalidate(handle: AssetHandle) {
        lock.lock()
        entries = entries.filter { $0.key.handle != handle }
        lock.unlock()
    }

    private static func timestampForURL(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let time = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return Int64(time * 1000.0)
    }

    private func extractSchema(scriptURL: URL, typeName: String) -> [ScriptFieldDescriptor] {
        var jsonBuffer = [CChar](repeating: 0, count: 16 * 1024)
        var errorBuffer = [CChar](repeating: 0, count: 1024)
        let ok: UInt32 = scriptURL.path.withCString { pathCString in
            typeName.withCString { typeCString in
                MCELuaExtractScriptSchema(pathCString,
                                          typeCString,
                                          &jsonBuffer,
                                          Int32(jsonBuffer.count),
                                          &errorBuffer,
                                          Int32(errorBuffer.count))
            }
        }
        if ok == 0 {
            let message = String(cString: errorBuffer)
            if !message.isEmpty {
                EngineLoggerContext.log("Lua schema extract failed: \(message)", level: .warning, category: .scene)
            }
            return []
        }

        let jsonText = String(cString: jsonBuffer)
        guard let data = jsonText.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var descriptors: [ScriptFieldDescriptor] = []
        descriptors.reserveCapacity(rawArray.count)
        for raw in rawArray {
            guard let descriptor = parseDescriptor(raw) else { continue }
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func parseDescriptor(_ raw: [String: Any]) -> ScriptFieldDescriptor? {
        guard let name = raw["name"] as? String,
              let typeRaw = raw["type"] as? String,
              let type = parseFieldType(typeRaw) else { return nil }

        let defaultValue = parseDefaultValue(type: type, raw: raw["default"])
        let minValue = number(raw["min"])
        let maxValue = number(raw["max"])
        let step = number(raw["step"])
        let tooltip = raw["tooltip"] as? String ?? ""

        return ScriptFieldDescriptor(name: name,
                                     type: type,
                                     defaultValue: defaultValue,
                                     minValue: minValue,
                                     maxValue: maxValue,
                                     step: step,
                                     tooltip: tooltip)
    }

    private func parseFieldType(_ raw: String) -> ScriptFieldType? {
        switch raw.lowercased() {
        case "bool", "boolean": return .bool
        case "int", "integer": return .int
        case "float", "number": return .float
        case "vec2": return .vec2
        case "vec3": return .vec3
        case "color3", "rgb": return .color3
        case "string": return .string
        case "entity": return .entity
        case "prefab": return .prefab
        default:
            EngineLoggerContext.log("Unsupported Lua field schema type: \(raw)", level: .warning, category: .scene)
            return nil
        }
    }

    private func parseDefaultValue(type: ScriptFieldType, raw: Any?) -> ScriptFieldValue {
        switch type {
        case .bool, .boolean:
            return .bool((raw as? Bool) ?? false)
        case .int:
            if let value = raw as? NSNumber { return .int(value.int32Value) }
            return .int(0)
        case .float, .number:
            if let value = raw as? NSNumber { return .float(value.floatValue) }
            return .float(0)
        case .vec2:
            if let arr = raw as? [NSNumber], arr.count >= 2 {
                return .vec2(SIMD2<Float>(arr[0].floatValue, arr[1].floatValue))
            }
            return .vec2(SIMD2<Float>(0, 0))
        case .vec3:
            if let arr = raw as? [NSNumber], arr.count >= 3 {
                return .vec3(SIMD3<Float>(arr[0].floatValue, arr[1].floatValue, arr[2].floatValue))
            }
            return .vec3(SIMD3<Float>(0, 0, 0))
        case .color3:
            if let arr = raw as? [NSNumber], arr.count >= 3 {
                return .color3(SIMD3<Float>(arr[0].floatValue, arr[1].floatValue, arr[2].floatValue))
            }
            return .color3(SIMD3<Float>(1, 1, 1))
        case .string:
            return .string((raw as? String) ?? "")
        case .entity:
            guard let string = raw as? String, let uuid = UUID(uuidString: string) else { return .entity(nil) }
            return .entity(uuid)
        case .prefab:
            guard let string = raw as? String, let uuid = UUID(uuidString: string) else { return .prefab(nil) }
            return .prefab(AssetHandle(rawValue: uuid))
        }
    }

    private func number(_ any: Any?) -> Float? {
        guard let value = any as? NSNumber else { return nil }
        return value.floatValue
    }
}

private struct DataCursor {
    var data: Data
    var offset: Int = 0

    mutating func readUInt8() -> UInt8? {
        guard offset + 1 <= data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        defer { offset += 2 }
        return data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        defer { offset += 4 }
        return data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    mutating func readInt32() -> Int32? {
        guard let unsigned = readUInt32() else { return nil }
        return Int32(bitPattern: unsigned)
    }

    mutating func readFloat() -> Float? {
        guard offset + 4 <= data.count else { return nil }
        defer { offset += 4 }
        let bits: UInt32 = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
        return Float(bitPattern: bits)
    }

    mutating func readString(byteCount: Int) -> String? {
        guard byteCount >= 0, offset + byteCount <= data.count else { return nil }
        defer { offset += byteCount }
        let sub = data.subdata(in: offset..<(offset + byteCount))
        return String(data: sub, encoding: .utf8)
    }

    mutating func readUUID() -> UUID? {
        guard offset + 16 <= data.count else { return nil }
        var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        _ = withUnsafeMutableBytes(of: &bytes) { destination in
            data.copyBytes(to: destination, from: offset..<(offset + 16))
        }
        offset += 16
        let uuid = UUID(uuid: bytes)
        return uuid == UUID(uuidString: "00000000-0000-0000-0000-000000000000") ? nil : uuid
    }
}

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendFloat(_ value: Float) {
        appendUInt32(value.bitPattern)
    }

    mutating func appendUUID(_ value: UUID?) {
        let uuid = value?.uuid ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!.uuid
        var bytes = uuid
        Swift.withUnsafeBytes(of: &bytes) { append(contentsOf: $0) }
    }
}
