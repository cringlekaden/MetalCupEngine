//
//  TextureLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

enum TextureType {
    case None
    case PartyPirateParrot
    case Cruiser
}

class TextureLibrary: Library<TextureType, MTLTexture> {
    
    private var _library: [TextureType : Texture] = [:]
    
    override func fillLibrary() {
        _library[.PartyPirateParrot] = Texture("PartyPirateParrot", origin: .topLeft)
        _library[.Cruiser] = Texture("cruiser", ext: "bmp", origin: .bottomLeft)
    }
    
    override subscript(_ type: TextureType) -> MTLTexture? {
        let tex = _library[type]?.texture
        if let tex { return tex }
        // Fallback: create a 1x1 magenta texture so we never crash
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let fallback = Engine.Device.makeTexture(descriptor: desc) else {
            fatalError("Failed to create fallback texture")
        }
        let pixel: [UInt8] = [255, 0, 255, 255]
        pixel.withUnsafeBytes { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            fallback.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: 4)
        }
        return fallback
    }
}

class Texture {
    
    var texture: MTLTexture!
    
    init(_ textureName: String, ext: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
        let textureLoader = TextureLoader(textureName: textureName, textureExtension: ext, origin: origin)
        let texture = textureLoader.loadTextureFromBundle()
        if let texture {
            setTexture(texture)
        } else {
            print("ERROR::TEXTURE::\(textureName).\(ext) failed to load. Using nil placeholder.")
        }
    }
    
    func setTexture(_ texture: MTLTexture) {
        self.texture = texture
    }
}

class TextureLoader {
    
    private var _textureName: String!
    private var _textureExtension: String!
    private var _origin: MTKTextureLoader.Origin!
    
    init(textureName: String, textureExtension: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
        self._textureName = textureName
        self._textureExtension = textureExtension
        self._origin = origin
    }
    
    public func loadTextureFromBundle() -> MTLTexture? {
        var result: MTLTexture?
        if let url = Bundle.main.url(forResource: _textureName, withExtension: _textureExtension) {
            print(url)
            let textureLoader = MTKTextureLoader(device: Engine.Device)
            let options: [MTKTextureLoader.Option: Any] = [.origin : _origin!, .generateMipmaps: true, .SRGB: true]
            do {
                result = try textureLoader.newTexture(URL: url, options: options)
                result?.label = _textureName
            } catch let error as NSError {
                print("ERROR::CREATING::TEXTURE::__\(_textureName!)__::\(error)")
            }
        } else {
            print("ERROR::CREATING::TEXTURE::__\(_textureName!).\(_textureExtension!) does not exist in bundle...")
        }
        return result
    }
}
