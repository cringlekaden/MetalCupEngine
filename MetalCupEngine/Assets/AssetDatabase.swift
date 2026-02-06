//
//  AssetDatabase.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import Foundation

public protocol AssetDatabase: AnyObject {
    var assetRootURL: URL { get }
    func metadata(for handle: AssetHandle) -> AssetMetadata?
    func metadata(forSourcePath sourcePath: String) -> AssetMetadata?
    func assetURL(for handle: AssetHandle) -> URL?
    func allMetadata() -> [AssetMetadata]
}
