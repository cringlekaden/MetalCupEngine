/// AnimationAssetSerializers.swift
/// Defines skeleton and animation clip serialization helpers.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct Matrix4x4DTO: Codable {
    public var values: [Float]

    public init(_ matrix: simd_float4x4) {
        values = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    public func toSIMD() -> simd_float4x4? {
        guard values.count >= 16 else { return nil }
        return simd_float4x4(
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        )
    }
}

public struct SkeletonAssetDocument: Codable {
    public struct JointDocument: Codable {
        public var name: String
        public var parentIndex: Int
        public var bindLocalPosition: Vector3DTO
        public var bindLocalRotation: Vector4DTO
        public var bindLocalScale: Vector3DTO
        public var inverseBindGlobal: Matrix4x4DTO?
    }

    public var schemaVersion: Int
    public var id: String?
    public var name: String?
    public var sourcePath: String?
    public var joints: [JointDocument]

    public init(schemaVersion: Int = 1,
                id: String? = nil,
                name: String? = nil,
                sourcePath: String? = nil,
                joints: [JointDocument] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.joints = joints
    }
}

public struct AnimationClipAssetDocument: Codable {
    public struct TranslationKeyframeDocument: Codable {
        public var time: Float
        public var value: Vector3DTO
    }

    public struct RotationKeyframeDocument: Codable {
        public var time: Float
        public var value: Vector4DTO
    }

    public struct ScaleKeyframeDocument: Codable {
        public var time: Float
        public var value: Vector3DTO
    }

    public struct JointTrackDocument: Codable {
        public var jointIndex: Int
        public var translations: [TranslationKeyframeDocument]
        public var rotations: [RotationKeyframeDocument]
        public var scales: [ScaleKeyframeDocument]
    }

    public var schemaVersion: Int
    public var id: String?
    public var name: String?
    public var sourcePath: String?
    public var durationSeconds: Float
    public var tracks: [JointTrackDocument]

    public init(schemaVersion: Int = 1,
                id: String? = nil,
                name: String? = nil,
                sourcePath: String? = nil,
                durationSeconds: Float = 0,
                tracks: [JointTrackDocument] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.durationSeconds = durationSeconds
        self.tracks = tracks
    }
}

public struct AnimationGraphAssetDocument: Codable {
    public struct ParameterDocument: Codable {
        public var name: String
        public var type: String
        public var defaultFloat: Float
        public var defaultBool: Bool
        public var defaultInt: Int
    }

    public struct ConditionDocument: Codable {
        public var parameterName: String
        public var op: String
        public var floatValue: Float?
        public var intValue: Int?
        public var boolValue: Bool?
    }

    public struct TransitionDocument: Codable {
        public var id: String
        public var fromStateID: String
        public var toStateID: String
        public var durationSeconds: Float
        public var minimumNormalizedTime: Float?
        public var conditions: [ConditionDocument]
    }

    public struct StateDocument: Codable {
        public struct RootMotionSettingsDocument: Codable {
            public var translationSourceJointName: String?
            public var rotationSourceJointName: String?
            public var consumeJointName: String?
            public var applyTranslation: Bool?
            public var applyRotation: Bool?
            public var consumeTranslation: Bool?
            public var consumeRotation: Bool?
        }

        public var id: String
        public var name: String
        public var clipHandle: String?
        public var nodeID: String?
        public var isOneShot: Bool?
        public var usesRootMotion: Bool?
        public var rootMotion: RootMotionSettingsDocument?
    }

    public struct StateMachineDocument: Codable {
        public var defaultStateID: String?
        public var states: [StateDocument]
        public var transitions: [TransitionDocument]
    }

    public struct NodeDocument: Codable {
        public struct Blend1DSampleDocument: Codable {
            public var clipHandle: String
            public var threshold: Float
        }

        public struct Blend1DDocument: Codable {
            public var parameterName: String
            public var samples: [Blend1DSampleDocument]
        }

        public struct Blend2DSampleDocument: Codable {
            public var clipHandle: String
            public var position: Vector2DTO
        }

        public struct Blend2DDocument: Codable {
            public var parameterXName: String
            public var parameterYName: String
            public var samples: [Blend2DSampleDocument]
        }

        public var id: String
        public var type: String
        public var title: String
        public var position: Vector2DTO
        public var clipHandle: String?
        public var parameterName: String?
        public var blend1D: Blend1DDocument?
        public var blend2D: Blend2DDocument?
        public var stateMachine: StateMachineDocument?
    }

    public struct LinkDocument: Codable {
        public var id: String
        public var fromNodeID: String
        public var fromSlotIndex: Int
        public var toNodeID: String
        public var toSlotIndex: Int
    }

    public var schemaVersion: Int
    public var id: String?
    public var name: String?
    public var sourcePath: String?
    public var outputNodeID: String?
    public var parameters: [ParameterDocument]
    public var nodes: [NodeDocument]
    public var links: [LinkDocument]

    public init(schemaVersion: Int = 1,
                id: String? = nil,
                name: String? = nil,
                sourcePath: String? = nil,
                outputNodeID: String? = nil,
                parameters: [ParameterDocument] = [],
                nodes: [NodeDocument] = [],
                links: [LinkDocument] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.outputNodeID = outputNodeID
        self.parameters = parameters
        self.nodes = nodes
        self.links = links
    }
}

public enum SkeletonAssetSerializer {
    public static func load(from url: URL, fallbackHandle: AssetHandle?) -> SkeletonAsset? {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(SkeletonAssetDocument.self, from: data)
            let handle = resolvedHandle(id: document.id, fallback: fallbackHandle)
            let joints = document.joints.map { joint in
                SkeletonAsset.Joint(
                    name: joint.name,
                    parentIndex: joint.parentIndex,
                    bindLocalPosition: joint.bindLocalPosition.toSIMD(),
                    bindLocalRotation: joint.bindLocalRotation.toSIMD(),
                    bindLocalScale: joint.bindLocalScale.toSIMD(),
                    inverseBindGlobalMatrix: joint.inverseBindGlobal?.toSIMD()
                )
            }
            return SkeletonAsset(
                handle: handle,
                name: document.name ?? url.deletingPathExtension().lastPathComponent,
                sourcePath: document.sourcePath ?? url.lastPathComponent,
                joints: joints
            )
        } catch {
            EngineLoggerContext.log(
                "Skeleton load failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return nil
        }
    }

    @discardableResult
    public static func save(_ asset: SkeletonAsset, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = SkeletonAssetDocument(
            schemaVersion: 1,
            id: asset.handle.rawValue.uuidString,
            name: asset.name,
            sourcePath: asset.sourcePath,
            joints: asset.joints.map { joint in
                SkeletonAssetDocument.JointDocument(
                    name: joint.name,
                    parentIndex: joint.parentIndex,
                    bindLocalPosition: Vector3DTO(joint.bindLocalPosition),
                    bindLocalRotation: Vector4DTO(joint.bindLocalRotation),
                    bindLocalScale: Vector3DTO(joint.bindLocalScale),
                    inverseBindGlobal: joint.inverseBindGlobalMatrix.map(Matrix4x4DTO.init)
                )
            }
        )
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            EngineLoggerContext.log(
                "Skeleton save failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return false
        }
    }
}

public enum AnimationClipAssetSerializer {
    public static func load(from url: URL, fallbackHandle: AssetHandle?) -> AnimationClipAsset? {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(AnimationClipAssetDocument.self, from: data)
            let handle = resolvedHandle(id: document.id, fallback: fallbackHandle)
            let tracks = document.tracks.map { track in
                AnimationClipAsset.JointTrack(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map {
                        AnimationClipAsset.TranslationKeyframe(time: $0.time, value: $0.value.toSIMD())
                    },
                    rotations: track.rotations.map {
                        AnimationClipAsset.RotationKeyframe(time: $0.time, value: $0.value.toSIMD())
                    },
                    scales: track.scales.map {
                        AnimationClipAsset.ScaleKeyframe(time: $0.time, value: $0.value.toSIMD())
                    }
                )
            }
            return AnimationClipAsset(
                handle: handle,
                name: document.name ?? url.deletingPathExtension().lastPathComponent,
                sourcePath: document.sourcePath ?? url.lastPathComponent,
                durationSeconds: document.durationSeconds,
                tracks: tracks
            )
        } catch {
            EngineLoggerContext.log(
                "Animation clip load failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return nil
        }
    }

    @discardableResult
    public static func save(_ asset: AnimationClipAsset, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = AnimationClipAssetDocument(
            schemaVersion: 1,
            id: asset.handle.rawValue.uuidString,
            name: asset.name,
            sourcePath: asset.sourcePath,
            durationSeconds: asset.durationSeconds,
            tracks: asset.tracks.map { track in
                AnimationClipAssetDocument.JointTrackDocument(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map {
                        AnimationClipAssetDocument.TranslationKeyframeDocument(
                            time: $0.time,
                            value: Vector3DTO($0.value)
                        )
                    },
                    rotations: track.rotations.map {
                        AnimationClipAssetDocument.RotationKeyframeDocument(
                            time: $0.time,
                            value: Vector4DTO($0.value)
                        )
                    },
                    scales: track.scales.map {
                        AnimationClipAssetDocument.ScaleKeyframeDocument(
                            time: $0.time,
                            value: Vector3DTO($0.value)
                        )
                    }
                )
            }
        )
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            EngineLoggerContext.log(
                "Animation clip save failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return false
        }
    }
}

public enum AnimationGraphAssetSerializer {
    public static func load(from url: URL, fallbackHandle: AssetHandle?) -> AnimationGraphAsset? {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(AnimationGraphAssetDocument.self, from: data)
            let handle = resolvedHandle(id: document.id, fallback: fallbackHandle)

            let parameters = document.parameters.map { parameter -> AnimationGraphParameterDefinition in
                AnimationGraphParameterDefinition(
                    name: parameter.name,
                    type: AnimationGraphParameterType(rawValue: parameter.type) ?? .float,
                    defaultFloat: parameter.defaultFloat,
                    defaultBool: parameter.defaultBool,
                    defaultInt: parameter.defaultInt
                )
            }

            let nodes = document.nodes.compactMap { nodeDocument -> AnimationGraphNodeDefinition? in
                guard let nodeID = UUID(uuidString: nodeDocument.id) else { return nil }
                let nodeType = AnimationGraphNodeType(rawValue: nodeDocument.type) ?? .parameter
                let clipHandle: AssetHandle? = nodeDocument.clipHandle.flatMap { raw in
                    guard let uuid = UUID(uuidString: raw) else { return nil }
                    return AssetHandle(rawValue: uuid)
                }
                let stateMachine: AnimationGraphStateMachineScaffold? = nodeDocument.stateMachine.map { machine in
                    let states = machine.states.compactMap { state -> AnimationGraphStateDefinition? in
                        guard let stateID = UUID(uuidString: state.id) else { return nil }
                        let stateClipHandle: AssetHandle? = state.clipHandle.flatMap { raw in
                            guard let uuid = UUID(uuidString: raw) else { return nil }
                            return AssetHandle(rawValue: uuid)
                        }
                        let stateNodeID = state.nodeID.flatMap(UUID.init(uuidString:))
                        let rootMotionSettings = state.rootMotion.map { rootMotion in
                            AnimationGraphStateDefinition.RootMotionSettings(
                                translationSourceJointName: rootMotion.translationSourceJointName,
                                rotationSourceJointName: rootMotion.rotationSourceJointName,
                                consumeJointName: rootMotion.consumeJointName,
                                applyTranslation: rootMotion.applyTranslation,
                                applyRotation: rootMotion.applyRotation,
                                consumeTranslation: rootMotion.consumeTranslation,
                                consumeRotation: rootMotion.consumeRotation
                            )
                        }
                        return AnimationGraphStateDefinition(id: stateID,
                                                             name: state.name,
                                                             clipHandle: stateClipHandle,
                                                             nodeID: stateNodeID,
                                                             isOneShot: state.isOneShot ?? false,
                                                             usesRootMotion: state.usesRootMotion ?? inferredRootMotionUsage(for: state.name),
                                                             rootMotion: rootMotionSettings)
                    }
                    let transitions = machine.transitions.compactMap { transition -> AnimationGraphTransitionDefinition? in
                        guard let transitionID = UUID(uuidString: transition.id),
                              let fromStateID = UUID(uuidString: transition.fromStateID),
                              let toStateID = UUID(uuidString: transition.toStateID) else { return nil }
                        let conditions = transition.conditions.map { condition in
                            AnimationGraphConditionDefinition(
                                parameterName: condition.parameterName,
                                op: condition.op,
                                floatValue: condition.floatValue,
                                intValue: condition.intValue,
                                boolValue: condition.boolValue
                            )
                        }
                        return AnimationGraphTransitionDefinition(
                            id: transitionID,
                            fromStateID: fromStateID,
                            toStateID: toStateID,
                            durationSeconds: transition.durationSeconds,
                            minimumNormalizedTime: transition.minimumNormalizedTime,
                            conditions: conditions
                        )
                    }
                    let defaultStateID = machine.defaultStateID.flatMap(UUID.init(uuidString:))
                    return AnimationGraphStateMachineScaffold(defaultStateID: defaultStateID,
                                                              states: states,
                                                              transitions: transitions)
                }
                let blend1D: AnimationGraphBlend1DDefinition? = nodeDocument.blend1D.map { blend in
                    let samples = blend.samples.compactMap { sample -> AnimationGraphBlend1DSampleDefinition? in
                        guard let uuid = UUID(uuidString: sample.clipHandle) else { return nil }
                        return AnimationGraphBlend1DSampleDefinition(clipHandle: AssetHandle(rawValue: uuid),
                                                                     threshold: sample.threshold)
                    }
                    return AnimationGraphBlend1DDefinition(parameterName: blend.parameterName, samples: samples)
                }
                let blend2D: AnimationGraphBlend2DDefinition? = nodeDocument.blend2D.map { blend in
                    let samples = blend.samples.compactMap { sample -> AnimationGraphBlend2DSampleDefinition? in
                        guard let uuid = UUID(uuidString: sample.clipHandle) else { return nil }
                        return AnimationGraphBlend2DSampleDefinition(clipHandle: AssetHandle(rawValue: uuid),
                                                                     position: sample.position.toSIMD())
                    }
                    return AnimationGraphBlend2DDefinition(parameterXName: blend.parameterXName,
                                                           parameterYName: blend.parameterYName,
                                                           samples: samples)
                }
                return AnimationGraphNodeDefinition(
                    id: nodeID,
                    type: nodeType,
                    title: nodeDocument.title,
                    position: nodeDocument.position.toSIMD(),
                    clipHandle: clipHandle,
                    parameterName: nodeDocument.parameterName,
                    blend1D: blend1D,
                    blend2D: blend2D,
                    stateMachine: stateMachine
                )
            }

            let links = document.links.compactMap { linkDocument -> AnimationGraphLinkDefinition? in
                guard let linkID = UUID(uuidString: linkDocument.id),
                      let fromNodeID = UUID(uuidString: linkDocument.fromNodeID),
                      let toNodeID = UUID(uuidString: linkDocument.toNodeID) else { return nil }
                return AnimationGraphLinkDefinition(
                    id: linkID,
                    fromNodeID: fromNodeID,
                    fromSlotIndex: linkDocument.fromSlotIndex,
                    toNodeID: toNodeID,
                    toSlotIndex: linkDocument.toSlotIndex
                )
            }

            let outputNodeID = document.outputNodeID.flatMap(UUID.init(uuidString:))
            return AnimationGraphAsset(
                handle: handle,
                name: document.name ?? url.deletingPathExtension().lastPathComponent,
                sourcePath: document.sourcePath ?? url.lastPathComponent,
                outputNodeID: outputNodeID,
                parameters: parameters,
                nodes: nodes,
                links: links
            )
        } catch {
            EngineLoggerContext.log(
                "Animation graph load failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return nil
        }
    }

    @discardableResult
    public static func save(_ asset: AnimationGraphAsset, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = AnimationGraphAssetDocument(
            schemaVersion: 1,
            id: asset.handle.rawValue.uuidString,
            name: asset.name,
            sourcePath: asset.sourcePath,
            outputNodeID: asset.outputNodeID?.uuidString,
            parameters: asset.parameters.map { parameter in
                AnimationGraphAssetDocument.ParameterDocument(
                    name: parameter.name,
                    type: parameter.type.rawValue,
                    defaultFloat: parameter.defaultFloat,
                    defaultBool: parameter.defaultBool,
                    defaultInt: parameter.defaultInt
                )
            },
            nodes: asset.nodes.map { node in
                let stateMachine = node.stateMachine.map { machine in
                    AnimationGraphAssetDocument.StateMachineDocument(
                        defaultStateID: machine.defaultStateID?.uuidString,
                        states: machine.states.map { state in
                            AnimationGraphAssetDocument.StateDocument(
                                id: state.id.uuidString,
                                name: state.name,
                                clipHandle: state.clipHandle?.rawValue.uuidString,
                                nodeID: state.nodeID?.uuidString,
                                isOneShot: state.isOneShot,
                                usesRootMotion: state.usesRootMotion,
                                rootMotion: state.rootMotion.map { rootMotion in
                                    AnimationGraphAssetDocument.StateDocument.RootMotionSettingsDocument(
                                        translationSourceJointName: rootMotion.translationSourceJointName,
                                        rotationSourceJointName: rootMotion.rotationSourceJointName,
                                        consumeJointName: rootMotion.consumeJointName,
                                        applyTranslation: rootMotion.applyTranslation,
                                        applyRotation: rootMotion.applyRotation,
                                        consumeTranslation: rootMotion.consumeTranslation,
                                        consumeRotation: rootMotion.consumeRotation
                                    )
                                }
                            )
                        },
                        transitions: machine.transitions.map { transition in
                            AnimationGraphAssetDocument.TransitionDocument(
                                id: transition.id.uuidString,
                                fromStateID: transition.fromStateID.uuidString,
                                toStateID: transition.toStateID.uuidString,
                                durationSeconds: transition.durationSeconds,
                                minimumNormalizedTime: transition.minimumNormalizedTime,
                                conditions: transition.conditions.map { condition in
                                    AnimationGraphAssetDocument.ConditionDocument(
                                        parameterName: condition.parameterName,
                                        op: condition.op,
                                        floatValue: condition.floatValue,
                                        intValue: condition.intValue,
                                        boolValue: condition.boolValue
                                    )
                                }
                            )
                        }
                    )
                }
                return AnimationGraphAssetDocument.NodeDocument(
                    id: node.id.uuidString,
                    type: node.type.rawValue,
                    title: node.title,
                    position: Vector2DTO(node.position),
                    clipHandle: node.clipHandle?.rawValue.uuidString,
                    parameterName: node.parameterName,
                    blend1D: node.blend1D.map { blend in
                        AnimationGraphAssetDocument.NodeDocument.Blend1DDocument(
                            parameterName: blend.parameterName,
                            samples: blend.samples.map { sample in
                                AnimationGraphAssetDocument.NodeDocument.Blend1DSampleDocument(
                                    clipHandle: sample.clipHandle.rawValue.uuidString,
                                    threshold: sample.threshold
                                )
                            }
                        )
                    },
                    blend2D: node.blend2D.map { blend in
                        AnimationGraphAssetDocument.NodeDocument.Blend2DDocument(
                            parameterXName: blend.parameterXName,
                            parameterYName: blend.parameterYName,
                            samples: blend.samples.map { sample in
                                AnimationGraphAssetDocument.NodeDocument.Blend2DSampleDocument(
                                    clipHandle: sample.clipHandle.rawValue.uuidString,
                                    position: Vector2DTO(sample.position)
                                )
                            }
                        )
                    },
                    stateMachine: stateMachine
                )
            },
            links: asset.links.map { link in
                AnimationGraphAssetDocument.LinkDocument(
                    id: link.id.uuidString,
                    fromNodeID: link.fromNodeID.uuidString,
                    fromSlotIndex: link.fromSlotIndex,
                    toNodeID: link.toNodeID.uuidString,
                    toSlotIndex: link.toSlotIndex
                )
            }
        )
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            EngineLoggerContext.log(
                "Animation graph save failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return false
        }
    }
}

private func resolvedHandle(id: String?, fallback: AssetHandle?) -> AssetHandle {
    if let id, let uuid = UUID(uuidString: id) {
        return AssetHandle(rawValue: uuid)
    }
    return fallback ?? AssetHandle()
}

private func inferredRootMotionUsage(for stateName: String) -> Bool {
    let normalized = stateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    return normalized.contains("walk")
        || normalized.contains("run")
        || normalized.contains("strafe")
        || normalized.contains("turn")
        || normalized.contains("locomotion")
}
