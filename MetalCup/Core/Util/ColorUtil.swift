//
//  Color.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import simd

public class ColorUtil {
    
    public static var randomColor: SIMD4<Float> {
        return SIMD4<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1), 1.0)
    }
}
