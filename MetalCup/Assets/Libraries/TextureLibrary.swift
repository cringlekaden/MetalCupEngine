//
//  TextureLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

enum TextureType {
    case None
    case BaseColorRender
    case BloomPing
    case BloomPong
    case BaseDepthRender
    case EnvironmentCubemap
    case IrradianceCubemap
    case PrefilteredCubemap
    case BRDF_LUT
    case VeniceSunset
    case Studio
    case Cruise
    case Night
    case Rocks
    case NeonCity
}

class TextureLibrary: Library<TextureType, MTLTexture> {
    
    private var _library: [TextureType : Texture] = [:]
    private let _environmentSize = 2048
    private let _irradianceSize = 64
    private let _prefilteredSize = 1024
    private let _brdfLutSize = 512
    
    override func fillLibrary() {
        _library[.VeniceSunset] = Texture("venice_sunset", ext: "hdr", srgb: false, generateMipmaps: false)
        _library[.Studio] = Texture("studio", ext: "exr", srgb: false, generateMipmaps: false)
        _library[.Cruise] = Texture("cruise", ext: "exr", srgb: false, generateMipmaps: false)
        _library[.Night] = Texture("night", ext: "exr", srgb: false, generateMipmaps: false)
        _library[.Rocks] = Texture("rocks", ext: "exr", srgb: false, generateMipmaps: false)
        _library[.NeonCity] = Texture("neonCity", ext: "exr", srgb: false, generateMipmaps: false)
        createIBLTextures()
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
    
    func setTexture(textureType: TextureType, texture: MTLTexture) {
        _library.updateValue(Texture(texture: texture), forKey: textureType)
    }
    
    func createIBLTextures() {
        let environmentDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: Preferences.HDRPixelFormat, size: _environmentSize, mipmapped: true)
        environmentDescriptor.usage = [.renderTarget, .shaderRead]
        environmentDescriptor.storageMode = .private
        _library[.EnvironmentCubemap] = Texture(texture: Engine.Device.makeTexture(descriptor: environmentDescriptor)!)
        let irradianceDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: Preferences.HDRPixelFormat, size: _irradianceSize, mipmapped: false)
        irradianceDescriptor.usage = [.renderTarget, .shaderRead]
        irradianceDescriptor.storageMode = .private
        _library[.IrradianceCubemap] = Texture(texture: Engine.Device.makeTexture(descriptor: irradianceDescriptor)!)
        let prefilteredDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: Preferences.HDRPixelFormat, size: _prefilteredSize, mipmapped: true)
        prefilteredDescriptor.usage = [.renderTarget, .shaderRead]
        prefilteredDescriptor.storageMode = .private
        _library[.PrefilteredCubemap] = Texture(texture: Engine.Device.makeTexture(descriptor: prefilteredDescriptor)!)
        let brdfLUTDescriptor = MTLTextureDescriptor()
        brdfLUTDescriptor.textureType = .type2D
        brdfLUTDescriptor.pixelFormat = .rg16Float
        brdfLUTDescriptor.width = _brdfLutSize
        brdfLUTDescriptor.height = _brdfLutSize
        brdfLUTDescriptor.mipmapLevelCount = 1
        brdfLUTDescriptor.usage = [.renderTarget, .shaderRead]
        brdfLUTDescriptor.storageMode = .private
        _library[.BRDF_LUT] = Texture(texture: Engine.Device.makeTexture(descriptor: brdfLUTDescriptor)!)
    }
}

private class Texture {
    
    var texture: MTLTexture!
    
    init(texture: MTLTexture) {
        setTexture(texture)
    }
    
    init(_ textureName: String, ext: String = "png", origin: MTKTextureLoader.Origin = .topLeft, srgb: Bool = true, generateMipmaps: Bool = true) {
        let textureLoader = TextureLoader(textureName: textureName, textureExtension: ext, origin: origin, srgb: srgb, generateMipmaps: generateMipmaps)
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
    private var _srgb: Bool!
    private var _generateMipmaps: Bool!
    
    init(textureName: String, textureExtension: String = "png", origin: MTKTextureLoader.Origin = .topLeft, srgb: Bool, generateMipmaps: Bool) {
        self._textureName = textureName
        self._textureExtension = textureExtension
        self._origin = origin
        self._srgb = srgb
        self._generateMipmaps = generateMipmaps
    }
    
    public func loadTextureFromBundle() -> MTLTexture? {
        var result: MTLTexture?
        if let url = Bundle.main.url(forResource: _textureName, withExtension: _textureExtension) {
            let textureLoader = MTKTextureLoader(device: Engine.Device)
            let options: [MTKTextureLoader.Option: Any] = [.origin : _origin as Any, .generateMipmaps: _generateMipmaps as Any, .SRGB: _srgb as Any]
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

