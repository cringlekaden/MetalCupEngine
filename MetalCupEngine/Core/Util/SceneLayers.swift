/// SceneLayers.swift
/// Defines layer and mask helpers for filtering scene queries.
/// Created by Kaden Cringle.

import Foundation

public struct LayerMask: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let all = LayerMask(rawValue: 0xFFFF_FFFF)

    public static func mask(for index: Int32) -> LayerMask {
        guard index >= 0 && index < LayerCatalog.maxLayers else { return LayerMask(rawValue: 0) }
        return LayerMask(rawValue: 1 << UInt32(index))
    }

    public func contains(layerIndex: Int32) -> Bool {
        return self.contains(LayerMask.mask(for: layerIndex))
    }
}

public final class LayerCatalog {
    public static let maxLayers: Int32 = 32
    public static let defaultLayerIndex: Int32 = 0

    public private(set) var names: [String] = LayerCatalog.defaultNames()

    public init() {}

    public func setNames(_ names: [String]) {
        self.names = LayerCatalog.normalizedNames(names)
    }

    public static func defaultNames() -> [String] {
        var names: [String] = ["Default"]
        for i in 1..<Int(maxLayers) {
            names.append("Layer \(i)")
        }
        return names
    }

    public static func normalizedNames(_ names: [String]) -> [String] {
        var result = names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if result.isEmpty {
            result = defaultNames()
        }
        if result.count > Int(maxLayers) {
            result = Array(result.prefix(Int(maxLayers)))
        }
        while result.count < Int(maxLayers) {
            result.append("Layer \(result.count)")
        }
        if result[0].isEmpty {
            result[0] = "Default"
        }
        return result
    }
}
