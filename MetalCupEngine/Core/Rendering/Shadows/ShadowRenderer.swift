/// ShadowRenderer.swift
/// Renders cascaded directional shadow maps.
/// Created by Codex.

import MetalKit
import simd

final class ShadowRenderer {
    private let engineContext: EngineContext
    private let resources: ShadowResources
    private let cascadeEpsilon: Float = 0.001
    private let minOrthoExtent: Float = 0.5
    private let minNearFarSpan: Float = 0.5
    private let minLightDistance: Float = 1.0
    private let depthPadding: Float = 0.5
    private let minSphereRadius: Float = 0.05

    init(engineContext: EngineContext) {
        self.engineContext = engineContext
        self.resources = ShadowResources(device: engineContext.device, preferences: engineContext.preferences)
    }

    func render(frame: RenderGraphFrame) {
        guard let scene = frame.delegate?.activeScene() else {
            resetShadowState(frame: frame)
            return
        }
        render(scene: scene, frame: frame)
    }

    private func render(scene: EngineScene, frame: RenderGraphFrame) {
        let settings = frame.renderer.settings.shadows
        guard settings.enabled != 0, settings.directionalEnabled != 0 else {
            resetShadowState(frame: frame)
            return
        }
        guard let lightDirection = resolveDirectionalShadowLight(in: scene) else {
            resetShadowState(frame: frame)
            return
        }
        guard let cameraState = resolveShadowCamera(sceneView: frame.sceneView) else {
            resetShadowState(frame: frame)
            return
        }
        let cascadeCount = max(1, min(4, Int(settings.cascadeCount)))
        let resolution = Int(settings.shadowMapResolution)
        guard let shadowMap = resources.ensureShadowMap(resolution: resolution, cascadeCount: cascadeCount) else {
            resetShadowState(frame: frame)
            return
        }

        let maxDistance = max(0.0, settings.maxShadowDistance)
        let cameraNear = max(0.01, cameraState.nearPlane)
        let cameraFar = max(cameraNear + 0.01, cameraState.farPlane)
        let farDistance = (maxDistance > 0.0) ? min(cameraFar, maxDistance) : cameraFar
        let splits = computeCascadeSplits(near: cameraNear, far: farDistance, count: cascadeCount, lambda: settings.cascadeSplitLambda)
        let stabilizedSplits = enforceSplitEpsilon(splits: splits, near: cameraNear, far: farDistance)

        var constants = ShadowConstants()
        constants.shadowEnabled = 1.0
        constants.shadowCasterDirection = lightDirection
        constants.cascadeCount = UInt32(cascadeCount)
        constants.shadowMapInvSize = SIMD2<Float>(1.0 / Float(shadowMap.width), 1.0 / Float(shadowMap.height))
        constants.depthBias = settings.depthBias
        constants.normalBias = settings.normalBias
        constants.pcfRadius = settings.pcfRadius
        constants.filterMode = settings.filterMode
        constants.maxShadowDistance = farDistance
        constants.fadeOutDistance = max(0.0, settings.fadeOutDistance)
        constants.pcssParams0 = SIMD4<Float>(
            settings.pcssLightWorldSize,
            settings.pcssMinFilterRadiusTexels,
            settings.pcssMaxFilterRadiusTexels,
            settings.pcssBlockerSearchRadiusTexels
        )
        constants.pcssParams1 = SIMD4<Float>(
            Float(settings.pcssBlockerSamples),
            Float(settings.pcssPCFSamples),
            Float(settings.pcssNoiseEnabled),
            0.0
        )

        var lightViews: [matrix_float4x4] = Array(repeating: matrix_identity_float4x4, count: cascadeCount)
        var lightProjections: [matrix_float4x4] = Array(repeating: matrix_identity_float4x4, count: cascadeCount)
        var lightViewProjs: [matrix_float4x4] = Array(repeating: matrix_identity_float4x4, count: cascadeCount)
        var disableFrame = false
        for cascadeIndex in 0..<cascadeCount {
            let splitDistance = stabilizedSplits[cascadeIndex]
            let centerWS = cameraState.position
            let radius = stableCascadeRadius(splitFar: splitDistance, projection: cameraState.projection)
            let extent = max(radius, minOrthoExtent * 0.5)
            let lightView = lightViewMatrix(lightDirection: lightDirection, center: centerWS, radius: extent)
            let stabilizedView = stabilizeLightView(
                lightView: lightView,
                center: centerWS,
                radius: extent,
                resolution: resolution
            )
            let centerLS = stabilizedView * SIMD4<Float>(centerWS, 1.0)
            let (nearZ, farZ) = computeLightNearFar(centerZ: centerLS.z, radius: extent)
            let lightProj = lightProjectionMatrix(radius: extent, nearZ: nearZ, farZ: farZ)
            let lightViewProj = lightProj * stabilizedView
            if !isFinite(stabilizedView) || !isFinite(lightProj) || !isFinite(lightViewProj) {
                disableFrame = true
                break
            }

            lightViews[cascadeIndex] = stabilizedView
            lightProjections[cascadeIndex] = lightProj
            lightViewProjs[cascadeIndex] = lightViewProj
            constants.setLightViewProj(lightViewProj, index: cascadeIndex)
        }

        if disableFrame {
            resetShadowState(frame: frame)
            return
        }

        constants.cascadeSplits = SIMD4<Float>(
            stabilizedSplits.count > 0 ? stabilizedSplits[0] : farDistance,
            stabilizedSplits.count > 1 ? stabilizedSplits[1] : farDistance,
            stabilizedSplits.count > 2 ? stabilizedSplits[2] : farDistance,
            stabilizedSplits.count > 3 ? stabilizedSplits[3] : farDistance
        )

        for cascadeIndex in cascadeCount..<4 {
            constants.setLightViewProj(matrix_identity_float4x4, index: cascadeIndex)
        }

        frame.frameContext.setShadowConstants(constants)
        frame.frameContext.setShadowMapTexture(shadowMap)

        for cascadeIndex in 0..<cascadeCount {
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = shadowMap
            pass.depthAttachment.slice = cascadeIndex
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .store
            pass.depthAttachment.clearDepth = 1.0
            guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encoder.label = "Shadow Cascade \(cascadeIndex)"
            encoder.pushDebugGroup("Shadow Cascade \(cascadeIndex)")
            RenderPassHelpers.setViewport(encoder, SIMD2<Float>(Float(shadowMap.width), Float(shadowMap.height)))
            let constantsBuffer = frame.frameContext.makeSceneConstantsBuffer(
                shadowSceneConstants(
                    viewMatrix: lightViews[cascadeIndex],
                    projectionMatrix: lightProjections[cascadeIndex],
                    totalTime: scene.getSceneConstants().totalGameTime
                ),
                label: "SceneConstants.ShadowCascade\(cascadeIndex)"
            )
            RenderPassHelpers.withRenderPass(.shadow, renderer: frame.renderer, frameContext: frame.frameContext) {
                SceneRenderer.renderShadowCasters(
                    into: encoder,
                    scene: scene,
                    frameContext: frame.frameContext,
                    sceneConstantsBuffer: constantsBuffer
                )
            }
            encoder.popDebugGroup()
            encoder.endEncoding()
        }

    }

    private func resetShadowState(frame: RenderGraphFrame) {
        frame.frameContext.setShadowConstants(ShadowConstants())
        frame.frameContext.setShadowMapTexture(nil)
    }

    private func resolveDirectionalShadowLight(in scene: EngineScene) -> SIMD3<Float>? {
        var direction: SIMD3<Float>?
        scene.ecs.viewLights { _, _, light in
            if direction != nil { return }
            guard light.type == .directional, light.castsShadows else { return }
            let dir = simd_length_squared(light.direction) > 0 ? simd_normalize(light.direction) : SIMD3<Float>(0, -1, 0)
            direction = dir
        }
        return direction
    }

    private enum CameraProjection {
        case perspective(tanHalfFov: Float, aspect: Float)
        case orthographic(halfWidth: Float, halfHeight: Float)
    }

    private struct CameraState {
        let viewMatrix: matrix_float4x4
        let position: SIMD3<Float>
        let forward: SIMD3<Float>
        let nearPlane: Float
        let farPlane: Float
        let projection: CameraProjection
    }

    private struct ProjectionInfo {
        let near: Float
        let far: Float
        let projection: CameraProjection
    }

    private func resolveShadowCamera(sceneView: SceneView) -> CameraState? {
        let viewMatrix = sceneView.viewMatrix
        guard let projectionInfo = deriveProjection(from: sceneView.projectionMatrix) else {
            return nil
        }
        let forward = normalize(-SIMD3<Float>(viewMatrix.columns.2.x, viewMatrix.columns.2.y, viewMatrix.columns.2.z))
        return CameraState(
            viewMatrix: viewMatrix,
            position: sceneView.cameraPosition,
            forward: forward,
            nearPlane: projectionInfo.near,
            farPlane: projectionInfo.far,
            projection: projectionInfo.projection
        )
    }

    private func deriveProjection(from projection: matrix_float4x4) -> ProjectionInfo? {
        let m22 = projection.columns.2.z
        let m32 = projection.columns.3.z
        guard m22.isFinite, m32.isFinite else { return nil }

        let isPerspective = abs(projection.columns.2.w + 1.0) < 0.01 && abs(projection.columns.3.w) < 0.01
        if isPerspective {
            guard abs(m22) > 1e-6, abs(m22 + 1.0) > 1e-6 else { return nil }
            var near = m32 / m22
            var far = m32 / (m22 + 1.0)
            if near > far {
                swap(&near, &far)
            }
            near = max(0.01, near)
            far = max(near + 0.01, far)

            let m11 = projection.columns.1.y
            let m00 = projection.columns.0.x
            guard abs(m11) > 1e-6, abs(m00) > 1e-6 else { return nil }
            let tanHalfFov = 1.0 / m11
            let aspect = m11 / m00
            return ProjectionInfo(
                near: near,
                far: far,
                projection: .perspective(tanHalfFov: tanHalfFov, aspect: aspect)
            )
        }

        guard abs(m22) > 1e-6 else { return nil }
        var near = m32 / m22
        var far = near - 1.0 / m22
        if near > far {
            swap(&near, &far)
        }
        near = max(0.01, near)
        far = max(near + 0.01, far)

        let m11 = projection.columns.1.y
        let m00 = projection.columns.0.x
        guard abs(m11) > 1e-6, abs(m00) > 1e-6 else { return nil }
        let halfWidth = 1.0 / m00
        let halfHeight = 1.0 / m11
        return ProjectionInfo(
            near: near,
            far: far,
            projection: .orthographic(halfWidth: halfWidth, halfHeight: halfHeight)
        )
    }

    private func computeCascadeSplits(near: Float, far: Float, count: Int, lambda: Float) -> [Float] {
        var splits: [Float] = []
        splits.reserveCapacity(count)
        let range = far - near
        let ratio = far / near
        for i in 1...count {
            let p = Float(i) / Float(count)
            let logSplit = near * pow(ratio, p)
            let linearSplit = near + range * p
            let split = linearSplit + (logSplit - linearSplit) * lambda
            splits.append(split)
        }
        return splits
    }

    private func enforceSplitEpsilon(splits: [Float], near: Float, far: Float) -> [Float] {
        guard !splits.isEmpty else { return splits }
        var stabilized: [Float] = []
        stabilized.reserveCapacity(splits.count)
        var previous = near
        for index in 0..<splits.count {
            let maxAllowed = far - Float(splits.count - index - 1) * cascadeEpsilon
            var value = min(splits[index], maxAllowed)
            value = max(value, previous + cascadeEpsilon)
            stabilized.append(value)
            previous = value
        }
        return stabilized
    }

    private func frustumCornersWorld(
        near: Float,
        far: Float,
        projection: CameraProjection,
        viewMatrix: matrix_float4x4
    ) -> [SIMD3<Float>] {
        let invView = simd_inverse(viewMatrix)
        let nearZ = -near
        let farZ = -far
        var corners: [SIMD3<Float>] = []
        corners.reserveCapacity(8)
        switch projection {
        case .perspective(let tanHalfFov, let aspect):
            let nearHeight = tanHalfFov * near
            let nearWidth = nearHeight * aspect
            let farHeight = tanHalfFov * far
            let farWidth = farHeight * aspect
            corners = [
                SIMD3<Float>(-nearWidth, -nearHeight, nearZ),
                SIMD3<Float>(nearWidth, -nearHeight, nearZ),
                SIMD3<Float>(nearWidth, nearHeight, nearZ),
                SIMD3<Float>(-nearWidth, nearHeight, nearZ),
                SIMD3<Float>(-farWidth, -farHeight, farZ),
                SIMD3<Float>(farWidth, -farHeight, farZ),
                SIMD3<Float>(farWidth, farHeight, farZ),
                SIMD3<Float>(-farWidth, farHeight, farZ)
            ]
        case .orthographic(let halfWidth, let halfHeight):
            corners = [
                SIMD3<Float>(-halfWidth, -halfHeight, nearZ),
                SIMD3<Float>(halfWidth, -halfHeight, nearZ),
                SIMD3<Float>(halfWidth, halfHeight, nearZ),
                SIMD3<Float>(-halfWidth, halfHeight, nearZ),
                SIMD3<Float>(-halfWidth, -halfHeight, farZ),
                SIMD3<Float>(halfWidth, -halfHeight, farZ),
                SIMD3<Float>(halfWidth, halfHeight, farZ),
                SIMD3<Float>(-halfWidth, halfHeight, farZ)
            ]
        }
        return corners.compactMap { corner in
            let world = invView * SIMD4<Float>(corner, 1.0)
            let worldPoint = SIMD3<Float>(world.x, world.y, world.z)
            return isFinite(worldPoint) ? worldPoint : nil
        }
    }

    private func lightViewMatrix(lightDirection: SIMD3<Float>, center: SIMD3<Float>, radius: Float) -> matrix_float4x4 {
        // lightDirection is the direction light rays travel in world space.
        let forward = safeNormalize(lightDirection, fallback: SIMD3<Float>(0, -1, 0))
        let worldUp = SIMD3<Float>(0, 1, 0)
        let worldRight = SIMD3<Float>(1, 0, 0)
        let upCandidate = abs(dot(forward, worldUp)) > 0.99 ? worldRight : worldUp
        var right = safeNormalize(cross(upCandidate, forward), fallback: worldRight)
        var up = cross(forward, right)
        if determinant3x3(right: right, up: up, forward: forward) < 0.0 {
            right = -right
            up = cross(forward, right)
        }
        let extraMargin = max(1.0, radius * 0.1)
        let distance = max(minLightDistance, radius + extraMargin)
        let eye = center - forward * distance
        return viewMatrix(right: right, up: up, forward: forward, eye: eye)
    }

    private func stabilizeLightView(
        lightView: matrix_float4x4,
        center: SIMD3<Float>,
        radius: Float,
        resolution: Int
    ) -> matrix_float4x4 {
        let safeResolution = max(1, resolution)
        let worldUnitsPerTexel = (2.0 * radius) / Float(safeResolution)
        guard worldUnitsPerTexel > 0.0 else { return lightView }

        let centerLS = lightView * SIMD4<Float>(center, 1.0)
        let snappedX = round(centerLS.x / worldUnitsPerTexel) * worldUnitsPerTexel
        let snappedY = round(centerLS.y / worldUnitsPerTexel) * worldUnitsPerTexel
        if !snappedX.isFinite || !snappedY.isFinite {
            return lightView
        }
        var stabilized = lightView
        stabilized.columns.3.x += snappedX - centerLS.x
        stabilized.columns.3.y += snappedY - centerLS.y
        return stabilized
    }

    private func computeLightNearFar(centerZ: Float, radius: Float) -> (Float, Float) {
        let depthPad = max(depthPadding, radius * 0.005)
        var minZ = centerZ - radius - depthPad
        var maxZ = centerZ + radius + depthPad
        let span = abs(maxZ - minZ)
        if span < minNearFarSpan {
            let extra = (minNearFarSpan - span) * 0.5
            maxZ += extra
            minZ -= extra
        }
        if !minZ.isFinite || !maxZ.isFinite {
            maxZ = -depthPadding
            minZ = maxZ - minNearFarSpan
        }
        let nearZ = maxZ
        let farZ = minZ
        return (nearZ, farZ)
    }

    private func lightProjectionMatrix(radius: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
        let extent = radius
        return metalOrthographic(
            left: -extent,
            right: extent,
            bottom: -extent,
            top: extent,
            nearZ: nearZ,
            farZ: farZ
        )
    }

    private func metalOrthographic(
        left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        nearZ: Float,
        farZ: Float
    ) -> matrix_float4x4 {
        let rl = right - left
        let tb = top - bottom
        var fn = farZ - nearZ
        if abs(fn) < 1e-6 {
            fn = fn >= 0.0 ? 1e-6 : -1e-6
        }
        var result = matrix_identity_float4x4
        result.columns = (
            SIMD4<Float>(2.0 / rl, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / tb, 0, 0),
            SIMD4<Float>(0, 0, 1.0 / fn, 0),
            SIMD4<Float>(-(right + left) / rl, -(top + bottom) / tb, -nearZ / fn, 1.0)
        )
        return result
    }

    private struct NdcBounds {
        var minX: Float
        var maxX: Float
        var minY: Float
        var maxY: Float
        var minZ: Float
        var maxZ: Float
    }

    private func ndcBoundsForCorners(_ corners: [SIMD3<Float>], lightViewProj: matrix_float4x4) -> NdcBounds {
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        for corner in corners {
            let clip = lightViewProj * SIMD4<Float>(corner, 1.0)
            if abs(clip.w) < 1e-6 || !isFinite(clip) {
                continue
            }
            let invW = 1.0 / clip.w
            let ndc = SIMD3<Float>(clip.x * invW, clip.y * invW, clip.z * invW)
            minX = min(minX, ndc.x)
            maxX = max(maxX, ndc.x)
            minY = min(minY, ndc.y)
            maxY = max(maxY, ndc.y)
            minZ = min(minZ, ndc.z)
            maxZ = max(maxZ, ndc.z)
        }
        if !minX.isFinite || !maxX.isFinite {
            return NdcBounds(minX: 0, maxX: 0, minY: 0, maxY: 0, minZ: 0, maxZ: 0)
        }
        return NdcBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY, minZ: minZ, maxZ: maxZ)
    }

    private struct BoundingSphere {
        let center: SIMD3<Float>
        let radius: Float
    }

    private func stableCascadeRadius(splitFar: Float, projection: CameraProjection) -> Float {
        switch projection {
        case .perspective(let tanHalfFov, let aspect):
            let diagonal = tanHalfFov * sqrt(1.0 + aspect * aspect)
            let radius = splitFar * diagonal
            return max(radius, minSphereRadius)
        case .orthographic(let halfWidth, let halfHeight):
            let radius = sqrt(halfWidth * halfWidth + halfHeight * halfHeight)
            return max(radius, minSphereRadius)
        }
    }

    private func ritterBoundingSphere(points: [SIMD3<Float>]) -> BoundingSphere {
        guard !points.isEmpty else {
            return BoundingSphere(center: SIMD3<Float>(0, 0, 0), radius: minSphereRadius)
        }

        let first = points[0]
        var farthest = first
        var maxDist = Float.leastNonzeroMagnitude
        for p in points {
            let d = simd_length_squared(p - first)
            if d > maxDist {
                maxDist = d
                farthest = p
            }
        }

        var farthest2 = farthest
        maxDist = Float.leastNonzeroMagnitude
        for p in points {
            let d = simd_length_squared(p - farthest)
            if d > maxDist {
                maxDist = d
                farthest2 = p
            }
        }

        var center = (farthest + farthest2) * 0.5
        var radius = max(sqrt(simd_length_squared(farthest2 - farthest)) * 0.5, minSphereRadius)

        for p in points {
            let toPoint = p - center
            let dist = simd_length(toPoint)
            if dist > radius {
                let newRadius = (radius + dist) * 0.5
                let shift = (newRadius - radius) / max(dist, 1e-6)
                center += toPoint * shift
                radius = newRadius
            }
        }

        if !center.x.isFinite || !center.y.isFinite || !center.z.isFinite || !radius.isFinite {
            center = points.reduce(SIMD3<Float>(0, 0, 0), +) / Float(points.count)
            var maxDistanceSquared: Float = 0.0
            for p in points {
                maxDistanceSquared = max(maxDistanceSquared, simd_length_squared(p - center))
            }
            radius = max(sqrt(maxDistanceSquared), minSphereRadius)
        }

        return BoundingSphere(center: center, radius: max(radius, minSphereRadius))
    }

    private func viewZForDistance(_ distance: Float, projection: CameraProjection) -> Float {
        let d = max(distance, 0.001)
        switch projection {
        case .perspective(let tanHalfFov, let aspect):
            let t = tanHalfFov
            let a = aspect
            let factor = max(1e-4, sqrt(1.0 + t * t * (a * a + 1.0)))
            return max(d / factor, 0.001)
        case .orthographic(let halfWidth, let halfHeight):
            let lateral = halfWidth * halfWidth + halfHeight * halfHeight
            let zSquared = max(d * d - lateral, 0.000001)
            return max(sqrt(zSquared), 0.001)
        }
    }

    private func selectCascadeIndex(value: Float, splits: [Float], cascadeCount: Int) -> Int {
        var cascade = 0
        if splits.count > 0 && value > splits[0] { cascade = 1 }
        if splits.count > 1 && value > splits[1] { cascade = 2 }
        if splits.count > 2 && value > splits[2] { cascade = 3 }
        let maxCascade = max(cascadeCount - 1, 0)
        return min(cascade, maxCascade)
    }

    private func determinant3x3(right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
        let m00 = right.x
        let m01 = up.x
        let m02 = forward.x
        let m10 = right.y
        let m11 = up.y
        let m12 = forward.y
        let m20 = right.z
        let m21 = up.z
        let m22 = forward.z
        return m00 * (m11 * m22 - m12 * m21)
            - m01 * (m10 * m22 - m12 * m20)
            + m02 * (m10 * m21 - m11 * m20)
    }

    private func shadowSceneConstants(viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4, totalTime: Float) -> SceneConstants {
        var constants = SceneConstants()
        constants.totalGameTime = totalTime
        constants.viewMatrix = viewMatrix
        constants.skyViewMatrix = viewMatrix
        constants.projectionMatrix = projectionMatrix
        constants.cameraPositionAndIBL = SIMD4<Float>(0, 0, 0, 0)
        return constants
    }

    private func viewMatrix(right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>, eye: SIMD3<Float>) -> matrix_float4x4 {
        let r = SIMD4<Float>(right.x, up.x, -forward.x, 0.0)
        let u = SIMD4<Float>(right.y, up.y, -forward.y, 0.0)
        let f = SIMD4<Float>(right.z, up.z, -forward.z, 0.0)
        let t = SIMD4<Float>(-dot(right, eye), -dot(up, eye), dot(forward, eye), 1.0)
        return matrix_float4x4(columns: (r, u, f, t))
    }

    private func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private func isFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    private func isFinite(_ matrix: matrix_float4x4) -> Bool {
        isFinite(matrix.columns.0) && isFinite(matrix.columns.1) && isFinite(matrix.columns.2) && isFinite(matrix.columns.3)
    }

    private func safeNormalize(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        if lengthSquared > 1e-8 {
            return simd_normalize(value)
        }
        return fallback
    }

}
