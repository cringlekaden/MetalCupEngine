//
//  Keyboard.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

public final class Keyboard {
    
    private static let keyCount: Int = 256
    private static var keys = [Bool](repeating: false, count: keyCount)
    
    public static func SetKeyPressed(_ keyCode: UInt16, isOn: Bool) {
        let index = Int(keyCode)
        guard index >= 0 && index < keys.count else { return }
        keys[index] = isOn
    }
    
    public static func IsKeyPressed(_ keyCode: KeyCodes) -> Bool {
        let index = Int(keyCode.rawValue)
        guard index >= 0 && index < keys.count else { return false }
        return keys[index]
    }
}
