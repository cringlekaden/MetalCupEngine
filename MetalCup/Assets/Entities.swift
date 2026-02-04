//
//  Assets.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

public final class Assets {
    
    private static var _meshLibrary: MeshLibrary!
    private static var _textureLibrary: TextureLibrary!
    
    public static var Meshes: MeshLibrary { _meshLibrary }
    public static var Textures: TextureLibrary { _textureLibrary }
    
    public static func initialize() {
        _meshLibrary = MeshLibrary()
        _textureLibrary = TextureLibrary()
    }
}
