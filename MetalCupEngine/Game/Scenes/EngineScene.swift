//
//  Scene.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit
import simd

public class EngineScene {
    public let ecs: SceneECS

    private let name: String
    private var _cameraManager = CameraManager()
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()

    public var environmentMapHandle: AssetHandle?

    init(name: String, environmentMapHandle: AssetHandle?) {
        self.name = name
        self.environmentMapHandle = environmentMapHandle
        self.ecs = SceneECS()
        buildScene()
    }

    public func onUpdate() {
        _cameraManager.update()
        _sceneConstants.viewMatrix = _cameraManager.currentCamera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0
        _sceneConstants.skyViewMatrix[3][1] = 0
        _sceneConstants.skyViewMatrix[3][2] = 0
        _sceneConstants.projectionMatrix = _cameraManager.currentCamera.projectionMatrix
        _sceneConstants.totalGameTime = GameTime.TotalGameTime
        let cameraPosition = _cameraManager.currentCamera.getPosition()
        let hasEnvironment: Bool = {
            guard let (_, sky) = ecs.activeSkyLight(), sky.enabled else { return false }
            switch sky.mode {
            case .hdri:
                return sky.hdriHandle.flatMap { AssetManager.texture(handle: $0) } != nil
            case .procedural:
                return true
            }
        }()
        let settings = Renderer.settings
        let skyIntensity = ecs.activeSkyLight()?.1.intensity ?? 1.0
        let iblIntensity = (hasEnvironment && settings.iblEnabled != 0) ? settings.iblIntensity * skyIntensity : 0.0
        _sceneConstants.cameraPositionAndIBL = SIMD4<Float>(
            cameraPosition.x,
            cameraPosition.y,
            cameraPosition.z,
            iblIntensity
        )
        SkySystem.update(scene: ecs)
        doUpdate()
        syncLights()
    }

    public func onRender(encoder: MTLRenderCommandEncoder) {
        encoder.pushDebugGroup("Rendering Scene \(name)...")
        encoder.setVertexBytes(&_sceneConstants, length: SceneConstants.stride, index: 1)
        var settings = Renderer.settings
        encoder.setFragmentBytes(&settings, length: RendererSettings.stride, index: 2)
        _lightManager.setLightData(encoder)
        renderSky(encoder)
        renderMeshes(encoder)
        encoder.popDebugGroup()
    }

    func updateCameras() {
        _cameraManager.update()
    }

    func updateAspectRatio() {
        _cameraManager.currentCamera.setProjectionMatrix()
    }

    func addCamera(_ camera: Camera, _ setCurrent: Bool = true) {
        _cameraManager.registerCamera(camera: camera)
        if setCurrent {
            _cameraManager.setCamera(camera.cameraType)
        }
    }

    func buildScene() {}

    func doUpdate() {}

    public func onEvent(_ event: Event) {
        _cameraManager.onEvent(event)
    }

    private func syncLights() {
        var lightData: [LightData] = []
        ecs.viewLights { _, transform, light in
            var data = light.data
            switch light.type {
            case .point:
                data.type = 0
            case .spot:
                data.type = 1
            case .directional:
                data.type = 2
            }
            if let transform {
                data.position = transform.position
            }
            data.direction = light.direction
            data.range = light.range
            data.innerConeCos = light.innerConeCos
            data.outerConeCos = light.outerConeCos
            lightData.append(data)
        }
        _lightManager.setLights(lightData)
    }

    private func renderSky(_ encoder: MTLRenderCommandEncoder) {
        var renderedSky = false
        ecs.viewSkyLights { _, sky in
            if renderedSky { return }
            if !sky.enabled { return }
            renderedSky = true
            guard let mesh = AssetManager.mesh(handle: BuiltinAssets.skyboxMesh) else { return }
            encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            encoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var modelConstants = ModelConstants()
            modelConstants.modelMatrix = matrix_identity_float4x4
            encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: 2)
            encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.environmentCubemap), index: 10)
            mesh.drawPrimitives(encoder)
        }
    }

    private func renderMeshes(_ encoder: MTLRenderCommandEncoder) {
        ecs.viewTransformMeshRenderer { entity, transform, meshRenderer in
            guard let meshHandle = meshRenderer.meshHandle,
                  let mesh = AssetManager.mesh(handle: meshHandle) else { return }
            encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRBasic])
            encoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.counterClockwise)

            var materialOverride = meshRenderer.material
            if let name = ecs.get(NameComponent.self, for: entity), name.name == "Ground" {
                encoder.setCullMode(.none)
            }
            if let normalHandle = meshRenderer.normalMapHandle,
               let metadata = Engine.assetDatabase?.metadata(for: normalHandle) {
                if AssetManager.shouldFlipNormalY(path: metadata.sourcePath) {
                    var material = materialOverride ?? MetalCupMaterial()
                    material.flags |= MetalCupMaterialFlags.normalFlipY.rawValue
                    materialOverride = material
                }
            }

            var modelConstants = ModelConstants()
            modelConstants.modelMatrix = modelMatrix(for: transform)
            encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: 2)
            mesh.drawPrimitives(
                encoder,
                material: materialOverride,
                albedoMapHandle: meshRenderer.albedoMapHandle,
                normalMapHandle: meshRenderer.normalMapHandle,
                metallicMapHandle: meshRenderer.metallicMapHandle,
                roughnessMapHandle: meshRenderer.roughnessMapHandle,
                mrMapHandle: meshRenderer.mrMapHandle,
                aoMapHandle: meshRenderer.aoMapHandle,
                emissiveMapHandle: meshRenderer.emissiveMapHandle
            )
        }
    }

    private func modelMatrix(for transform: TransformComponent) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.translate(direction: transform.position)
        matrix.rotate(angle: transform.rotation.x, axis: xAxis)
        matrix.rotate(angle: transform.rotation.y, axis: yAxis)
        matrix.rotate(angle: transform.rotation.z, axis: zAxis)
        matrix.scale(axis: transform.scale)
        return matrix
    }
}
