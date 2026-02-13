/// AssetDatabase.swift
/// Defines the AssetDatabase types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

public protocol AssetDatabase: AnyObject {
    var assetRootURL: URL { get }
    func metadata(for handle: AssetHandle) -> AssetMetadata?
    func metadata(forSourcePath sourcePath: String) -> AssetMetadata?
    func assetURL(for handle: AssetHandle) -> URL?
    func allMetadata() -> [AssetMetadata]
}
