/// PickResult.swift
/// Defines pick result data returned by the renderer.
/// Created by Kaden Cringle.

import Foundation

public struct PickResult {
    public var pickedId: UInt32
    public var mask: LayerMask

    public init(pickedId: UInt32, mask: LayerMask) {
        self.pickedId = pickedId
        self.mask = mask
    }
}
