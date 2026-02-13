/// Engine.swift
/// Defines the Engine types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public class Engine {
    
    public static var Device: MTLDevice!
    public static var CommandQueue: MTLCommandQueue!
    public static var DefaultLibrary: MTLLibrary!
    public static weak var assetDatabase: AssetDatabase?
    
    public static func initialize(device: MTLDevice) {
        self.Device = device
        self.CommandQueue = device.makeCommandQueue()
        self.DefaultLibrary = device.makeDefaultLibrary()
    }
}
