/// ColorUtil.swift
/// Defines the ColorUtil types and helpers for the engine.
/// Created by Kaden Cringle.

import simd

public class ColorUtil {
    
    public static var randomColor: SIMD4<Float> {
        return SIMD4<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1), 1.0)
    }
}
