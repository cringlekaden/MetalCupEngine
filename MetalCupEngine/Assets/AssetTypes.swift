/// AssetTypes.swift
/// Defines the AssetTypes types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct AssetHandle: Hashable, Codable {
    public let rawValue: UUID

    public init() {
        self.rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(string: String) {
        self.rawValue = UUID(uuidString: string) ?? UUID()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.rawValue = UUID(uuidString: value) ?? UUID()
    }
}

public typealias TextureHandle = AssetHandle
public typealias MeshHandle = AssetHandle
public typealias MaterialHandle = AssetHandle
public typealias SkeletonHandle = AssetHandle
public typealias AnimationClipHandle = AssetHandle
public typealias AnimationGraphHandle = AssetHandle
public typealias AudioHandle = AssetHandle

public enum AssetType: String, Codable {
    case texture
    case model
    case material
    case environment
    case scene
    case prefab
    case script
    case skeleton
    case animationClip
    case animationGraph
    case audio
    case unknown
}

public struct SkeletonAsset {
    public struct Joint {
        public var name: String
        public var parentIndex: Int
        public var bindLocalPosition: SIMD3<Float>
        public var bindLocalRotation: SIMD4<Float>
        public var bindLocalScale: SIMD3<Float>
        public var inverseBindGlobalMatrix: simd_float4x4?

        public init(name: String,
                    parentIndex: Int,
                    bindLocalPosition: SIMD3<Float> = .zero,
                    bindLocalRotation: SIMD4<Float> = TransformMath.identityQuaternion,
                    bindLocalScale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0),
                    inverseBindGlobalMatrix: simd_float4x4? = nil) {
            self.name = name
            self.parentIndex = parentIndex
            self.bindLocalPosition = bindLocalPosition
            self.bindLocalRotation = TransformMath.normalizedQuaternion(bindLocalRotation)
            self.bindLocalScale = bindLocalScale
            self.inverseBindGlobalMatrix = inverseBindGlobalMatrix
        }
    }

    public var handle: SkeletonHandle
    public var name: String
    public var sourcePath: String
    public var boneCount: Int
    public var joints: [Joint]

    public init(handle: SkeletonHandle,
                name: String,
                sourcePath: String,
                boneCount: Int = 0,
                joints: [Joint] = []) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.joints = joints
        self.boneCount = joints.isEmpty ? boneCount : joints.count
    }
}

public struct AnimationClipAsset {
    public struct TranslationKeyframe {
        public var time: Float
        public var value: SIMD3<Float>

        public init(time: Float, value: SIMD3<Float>) {
            self.time = time
            self.value = value
        }
    }

    public struct RotationKeyframe {
        public var time: Float
        public var value: SIMD4<Float>

        public init(time: Float, value: SIMD4<Float>) {
            self.time = time
            self.value = TransformMath.normalizedQuaternion(value)
        }
    }

    public struct ScaleKeyframe {
        public var time: Float
        public var value: SIMD3<Float>

        public init(time: Float, value: SIMD3<Float>) {
            self.time = time
            self.value = value
        }
    }

    public struct JointTrack {
        public var jointIndex: Int
        public var translations: [TranslationKeyframe]
        public var rotations: [RotationKeyframe]
        public var scales: [ScaleKeyframe]

        public init(jointIndex: Int,
                    translations: [TranslationKeyframe] = [],
                    rotations: [RotationKeyframe] = [],
                    scales: [ScaleKeyframe] = []) {
            self.jointIndex = jointIndex
            self.translations = translations.sorted { $0.time < $1.time }
            self.rotations = rotations.sorted { $0.time < $1.time }
            self.scales = scales.sorted { $0.time < $1.time }
        }
    }

    public var handle: AnimationClipHandle
    public var name: String
    public var sourcePath: String
    public var durationSeconds: Float
    public var tracks: [JointTrack]

    public init(handle: AnimationClipHandle,
                name: String,
                sourcePath: String,
                durationSeconds: Float = 0.0,
                tracks: [JointTrack] = []) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.durationSeconds = durationSeconds
        self.tracks = tracks
    }
}

public struct AudioAsset {
    public var handle: AudioHandle
    public var name: String
    public var sourcePath: String
    public var durationSeconds: Float

    public init(handle: AudioHandle,
                name: String,
                sourcePath: String,
                durationSeconds: Float = 0.0) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.durationSeconds = durationSeconds
    }
}

public enum AnimationGraphParameterType: String, Codable {
    case float
    case bool
    case int
    case trigger
}

public struct AnimationGraphParameterDefinition: Codable {
    public var name: String
    public var type: AnimationGraphParameterType
    public var defaultFloat: Float
    public var defaultBool: Bool
    public var defaultInt: Int

    public init(name: String,
                type: AnimationGraphParameterType,
                defaultFloat: Float = 0.0,
                defaultBool: Bool = false,
                defaultInt: Int = 0) {
        self.name = name
        self.type = type
        self.defaultFloat = defaultFloat
        self.defaultBool = defaultBool
        self.defaultInt = defaultInt
    }
}

public enum AnimationGraphNodeType: String, Codable {
    case outputPose
    case clipPlayer
    case blend1D
    case blend2D
    case stateMachine
    case state
    case transition
    case parameter
}

public struct AnimationGraphConditionDefinition: Codable {
    public var parameterName: String
    public var op: String
    public var floatValue: Float?
    public var intValue: Int?
    public var boolValue: Bool?

    public init(parameterName: String,
                op: String,
                floatValue: Float? = nil,
                intValue: Int? = nil,
                boolValue: Bool? = nil) {
        self.parameterName = parameterName
        self.op = op
        self.floatValue = floatValue
        self.intValue = intValue
        self.boolValue = boolValue
    }
}

public struct AnimationGraphTransitionDefinition: Codable {
    public var id: UUID
    public var fromStateID: UUID
    public var toStateID: UUID
    public var durationSeconds: Float
    public var minimumNormalizedTime: Float?
    public var conditions: [AnimationGraphConditionDefinition]

    public init(id: UUID = UUID(),
                fromStateID: UUID,
                toStateID: UUID,
                durationSeconds: Float = 0.15,
                minimumNormalizedTime: Float? = nil,
                conditions: [AnimationGraphConditionDefinition] = []) {
        self.id = id
        self.fromStateID = fromStateID
        self.toStateID = toStateID
        self.durationSeconds = durationSeconds
        self.minimumNormalizedTime = minimumNormalizedTime
        self.conditions = conditions
    }
}

public struct AnimationGraphStateDefinition: Codable {
    public var id: UUID
    public var name: String
    public var clipHandle: AssetHandle?
    public var nodeID: UUID?
    public var isOneShot: Bool
    public var usesRootMotion: Bool

    public init(id: UUID = UUID(),
                name: String,
                clipHandle: AssetHandle? = nil,
                nodeID: UUID? = nil,
                isOneShot: Bool = false,
                usesRootMotion: Bool = false) {
        self.id = id
        self.name = name
        self.clipHandle = clipHandle
        self.nodeID = nodeID
        self.isOneShot = isOneShot
        self.usesRootMotion = usesRootMotion
    }
}

public struct AnimationGraphStateMachineScaffold: Codable {
    public var defaultStateID: UUID?
    public var states: [AnimationGraphStateDefinition]
    public var transitions: [AnimationGraphTransitionDefinition]

    public init(defaultStateID: UUID? = nil,
                states: [AnimationGraphStateDefinition] = [],
                transitions: [AnimationGraphTransitionDefinition] = []) {
        self.defaultStateID = defaultStateID
        self.states = states
        self.transitions = transitions
    }
}

public struct AnimationGraphNodeDefinition: Codable {
    public var id: UUID
    public var type: AnimationGraphNodeType
    public var title: String
    public var position: SIMD2<Float>
    public var clipHandle: AssetHandle?
    public var parameterName: String?
    public var blend1D: AnimationGraphBlend1DDefinition?
    public var blend2D: AnimationGraphBlend2DDefinition?
    public var stateMachine: AnimationGraphStateMachineScaffold?

    public init(id: UUID = UUID(),
                type: AnimationGraphNodeType,
                title: String,
                position: SIMD2<Float> = .zero,
                clipHandle: AssetHandle? = nil,
                parameterName: String? = nil,
                blend1D: AnimationGraphBlend1DDefinition? = nil,
                blend2D: AnimationGraphBlend2DDefinition? = nil,
                stateMachine: AnimationGraphStateMachineScaffold? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.position = position
        self.clipHandle = clipHandle
        self.parameterName = parameterName
        self.blend1D = blend1D
        self.blend2D = blend2D
        self.stateMachine = stateMachine
    }
}

public struct AnimationGraphBlend1DSampleDefinition: Codable {
    public var clipHandle: AssetHandle
    public var threshold: Float

    public init(clipHandle: AssetHandle, threshold: Float) {
        self.clipHandle = clipHandle
        self.threshold = threshold
    }
}

public struct AnimationGraphBlend1DDefinition: Codable {
    public var parameterName: String
    public var samples: [AnimationGraphBlend1DSampleDefinition]

    public init(parameterName: String, samples: [AnimationGraphBlend1DSampleDefinition] = []) {
        self.parameterName = parameterName
        self.samples = samples
    }
}

public struct AnimationGraphBlend2DSampleDefinition: Codable {
    public var clipHandle: AssetHandle
    public var position: SIMD2<Float>

    public init(clipHandle: AssetHandle, position: SIMD2<Float>) {
        self.clipHandle = clipHandle
        self.position = position
    }
}

public struct AnimationGraphBlend2DDefinition: Codable {
    public var parameterXName: String
    public var parameterYName: String
    public var samples: [AnimationGraphBlend2DSampleDefinition]

    public init(parameterXName: String, parameterYName: String, samples: [AnimationGraphBlend2DSampleDefinition] = []) {
        self.parameterXName = parameterXName
        self.parameterYName = parameterYName
        self.samples = samples
    }
}

public struct AnimationGraphLinkDefinition: Codable {
    public var id: UUID
    public var fromNodeID: UUID
    public var fromSlotIndex: Int
    public var toNodeID: UUID
    public var toSlotIndex: Int

    public init(id: UUID = UUID(),
                fromNodeID: UUID,
                fromSlotIndex: Int,
                toNodeID: UUID,
                toSlotIndex: Int) {
        self.id = id
        self.fromNodeID = fromNodeID
        self.fromSlotIndex = fromSlotIndex
        self.toNodeID = toNodeID
        self.toSlotIndex = toSlotIndex
    }
}

public struct AnimationGraphAsset {
    public var handle: AnimationGraphHandle
    public var name: String
    public var sourcePath: String
    public var outputNodeID: UUID?
    public var parameters: [AnimationGraphParameterDefinition]
    public var nodes: [AnimationGraphNodeDefinition]
    public var links: [AnimationGraphLinkDefinition]

    public init(handle: AnimationGraphHandle,
                name: String,
                sourcePath: String,
                outputNodeID: UUID? = nil,
                parameters: [AnimationGraphParameterDefinition] = [],
                nodes: [AnimationGraphNodeDefinition] = [],
                links: [AnimationGraphLinkDefinition] = []) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.outputNodeID = outputNodeID
        self.parameters = parameters
        self.nodes = nodes
        self.links = links
    }
}

public struct CompiledAnimationGraph {
    public struct Parameter {
        public let index: Int
        public let name: String
        public let type: AnimationGraphParameterType
        public let defaultFloat: Float
        public let defaultBool: Bool
        public let defaultInt: Int
    }

    public struct Node {
        public let index: Int
        public let id: UUID
        public let type: AnimationGraphNodeType
        public let title: String
        public let clipHandle: AssetHandle?
        public let parameterName: String?
        public let blend1D: AnimationGraphBlend1DDefinition?
        public let blend2D: AnimationGraphBlend2DDefinition?
        public let position: SIMD2<Float>
        public let stateMachine: AnimationGraphStateMachineScaffold?
    }

    public struct Link {
        public let id: UUID
        public let fromNodeIndex: Int
        public let fromSlotIndex: Int
        public let toNodeIndex: Int
        public let toSlotIndex: Int
    }

    public let handle: AnimationGraphHandle
    public let name: String
    public let outputNodeIndex: Int
    public let parameters: [Parameter]
    public let parameterIndexByName: [String: Int]
    public let nodes: [Node]
    public let links: [Link]
    public let evaluationOrder: [Int]
    public let referencedClipHandles: [AssetHandle]
}

public enum AnimationGraphCompileError: Error {
    case invalidGraph([String])
}

public enum AnimationGraphCompiler {
    private static func normalizedConditionOperator(_ rawOperator: String) -> String {
        let normalized = rawOperator
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case ">", "gt", "greater", "greaterthan":
            return ">"
        case ">=", "gte", "ge", "greaterorequal", "greaterthanorequal":
            return ">="
        case "<", "lt", "less", "lessthan":
            return "<"
        case "<=", "lte", "le", "lessorequal", "lessthanorequal":
            return "<="
        case "==", "=", "eq", "equal", "equals":
            return "=="
        case "!=", "<>", "neq", "notequal", "not":
            return "!="
        case "true", "istrue":
            return "istrue"
        case "false", "isfalse":
            return "isfalse"
        default:
            return normalized
        }
    }

    private static func supportsConditionOperator(_ normalizedOperator: String,
                                                  parameterType: AnimationGraphParameterType) -> Bool {
        if normalizedOperator.isEmpty { return true }
        switch parameterType {
        case .float, .int:
            return [">", ">=", "<", "<=", "==", "!="].contains(normalizedOperator)
        case .bool, .trigger:
            return ["==", "!=", "istrue", "isfalse"].contains(normalizedOperator)
        }
    }

    public static func compile(asset: AnimationGraphAsset,
                               clipExists: (AssetHandle) -> Bool) -> Result<CompiledAnimationGraph, AnimationGraphCompileError> {
        var diagnostics: [String] = []
        var parameterNameSet = Set<String>()
        var compiledParameters: [CompiledAnimationGraph.Parameter] = []
        compiledParameters.reserveCapacity(asset.parameters.count)
        for (index, parameter) in asset.parameters.enumerated() {
            let name = parameter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                diagnostics.append("Parameter[\(index)] has an empty name.")
                continue
            }
            if parameterNameSet.contains(name) {
                diagnostics.append("Duplicate parameter name '\(name)'.")
                continue
            }
            parameterNameSet.insert(name)
            compiledParameters.append(
                CompiledAnimationGraph.Parameter(
                    index: compiledParameters.count,
                    name: name,
                    type: parameter.type,
                    defaultFloat: parameter.defaultFloat,
                    defaultBool: parameter.defaultBool,
                    defaultInt: parameter.defaultInt
                )
            )
        }
        let parameterTypeByName = Dictionary(uniqueKeysWithValues: compiledParameters.map { ($0.name, $0.type) })

        guard !asset.nodes.isEmpty else {
            diagnostics.append("Graph has no nodes.")
            return .failure(.invalidGraph(diagnostics))
        }

        var nodeIndexByID: [UUID: Int] = [:]
        var compiledNodes: [CompiledAnimationGraph.Node] = []
        var referencedClipHandles = Set<AssetHandle>()
        for (index, node) in asset.nodes.enumerated() {
            if nodeIndexByID[node.id] != nil {
                diagnostics.append("Duplicate node ID '\(node.id.uuidString)'.")
                continue
            }
            nodeIndexByID[node.id] = compiledNodes.count
            if node.type == .clipPlayer {
                guard let clipHandle = node.clipHandle else {
                    diagnostics.append("ClipPlayer node '\(node.title)' is missing clip handle.")
                    continue
                }
                if !clipExists(clipHandle) {
                    diagnostics.append("ClipPlayer node '\(node.title)' references missing clip handle '\(clipHandle.rawValue.uuidString)'.")
                }
                referencedClipHandles.insert(clipHandle)
            } else if node.type == .blend1D {
                guard let blend = node.blend1D else {
                    diagnostics.append("Blend1D node '\(node.title)' is missing blend data.")
                    continue
                }
                if blend.parameterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    diagnostics.append("Blend1D node '\(node.title)' has empty parameter name.")
                }
                if blend.samples.isEmpty {
                    diagnostics.append("Blend1D node '\(node.title)' has no samples.")
                }
                for sample in blend.samples {
                    if !clipExists(sample.clipHandle) {
                        diagnostics.append("Blend1D node '\(node.title)' references missing clip handle '\(sample.clipHandle.rawValue.uuidString)'.")
                    }
                    referencedClipHandles.insert(sample.clipHandle)
                }
            } else if node.type == .blend2D {
                guard let blend = node.blend2D else {
                    diagnostics.append("Blend2D node '\(node.title)' is missing blend data.")
                    continue
                }
                if blend.parameterXName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    blend.parameterYName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    diagnostics.append("Blend2D node '\(node.title)' has empty parameter name(s).")
                }
                if blend.samples.isEmpty {
                    diagnostics.append("Blend2D node '\(node.title)' has no samples.")
                }
                for sample in blend.samples {
                    if !clipExists(sample.clipHandle) {
                        diagnostics.append("Blend2D node '\(node.title)' references missing clip handle '\(sample.clipHandle.rawValue.uuidString)'.")
                    }
                    referencedClipHandles.insert(sample.clipHandle)
                }
            } else if node.type == .stateMachine {
                guard let machine = node.stateMachine else {
                    diagnostics.append("StateMachine node '\(node.title)' is missing state machine data.")
                    continue
                }
                if machine.states.isEmpty {
                    diagnostics.append("StateMachine node '\(node.title)' has no states.")
                }
                let stateIDs = Set(machine.states.map(\.id))
                if let defaultStateID = machine.defaultStateID, !stateIDs.contains(defaultStateID) {
                    diagnostics.append("StateMachine node '\(node.title)' default state does not exist in state table.")
                }
                for state in machine.states {
                    let hasClip = (state.clipHandle != nil)
                    let hasNode = (state.nodeID != nil)
                    if !hasClip && !hasNode {
                        diagnostics.append("State '\(state.name)' in StateMachine '\(node.title)' is missing clip and node references.")
                    }
                    if hasClip && hasNode {
                        diagnostics.append("State '\(state.name)' in StateMachine '\(node.title)' must reference either clip or node, not both.")
                    }
                    if let clipHandle = state.clipHandle {
                        if !clipExists(clipHandle) {
                            diagnostics.append("State '\(state.name)' in StateMachine '\(node.title)' references missing clip handle '\(clipHandle.rawValue.uuidString)'.")
                        }
                        referencedClipHandles.insert(clipHandle)
                    }
                    if let referencedNodeID = state.nodeID {
                        guard let referencedNode = asset.nodes.first(where: { $0.id == referencedNodeID }) else {
                            diagnostics.append("State '\(state.name)' in StateMachine '\(node.title)' references unknown node ID '\(referencedNodeID.uuidString)'.")
                            continue
                        }
                        switch referencedNode.type {
                        case .clipPlayer, .blend1D, .blend2D, .stateMachine:
                            break
                        default:
                            diagnostics.append("State '\(state.name)' in StateMachine '\(node.title)' references unsupported node type '\(referencedNode.type.rawValue)'.")
                        }
                        if referencedNode.id == node.id {
                            diagnostics.append("State '\(state.name)' in StateMachine '\(node.title)' cannot reference the owning state machine node.")
                        }
                    }
                }
                for transition in machine.transitions {
                    if !stateIDs.contains(transition.fromStateID) {
                        diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' has invalid fromStateID.")
                    }
                    if !stateIDs.contains(transition.toStateID) {
                        diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' has invalid toStateID.")
                    }
                    if transition.durationSeconds < 0.0 {
                        diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' has negative duration.")
                    }
                    if let minimumNormalizedTime = transition.minimumNormalizedTime,
                       minimumNormalizedTime < 0.0 || minimumNormalizedTime > 1.0 {
                        diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' has minimumNormalizedTime outside [0, 1].")
                    }
                    for condition in transition.conditions {
                        let parameterName = condition.parameterName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if parameterName.isEmpty {
                            diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' contains condition with empty parameter name.")
                            continue
                        }
                        if !parameterNameSet.contains(parameterName) {
                            diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' references unknown parameter '\(parameterName)'.")
                            continue
                        }
                        if let parameterType = parameterTypeByName[parameterName] {
                            let normalizedOperator = normalizedConditionOperator(condition.op)
                            if !supportsConditionOperator(normalizedOperator, parameterType: parameterType) {
                                diagnostics.append("Transition '\(transition.id.uuidString)' in StateMachine '\(node.title)' uses unsupported operator '\(condition.op)' for parameter '\(parameterName)'.")
                            }
                        }
                    }
                }
            }
            compiledNodes.append(
                CompiledAnimationGraph.Node(
                    index: compiledNodes.count,
                    id: node.id,
                    type: node.type,
                    title: node.title.isEmpty ? "Node \(index)" : node.title,
                    clipHandle: node.clipHandle,
                    parameterName: node.parameterName,
                    blend1D: node.blend1D,
                    blend2D: node.blend2D,
                    position: node.position,
                    stateMachine: node.stateMachine
                )
            )
        }

        guard let outputNodeID = asset.outputNodeID else {
            diagnostics.append("Graph is missing output node ID.")
            return .failure(.invalidGraph(diagnostics))
        }
        guard let outputNodeIndex = nodeIndexByID[outputNodeID] else {
            diagnostics.append("Output node ID does not exist in node table.")
            return .failure(.invalidGraph(diagnostics))
        }
        if compiledNodes[outputNodeIndex].type != .outputPose {
            diagnostics.append("Output node must have type outputPose.")
        }

        var compiledLinks: [CompiledAnimationGraph.Link] = []
        for link in asset.links {
            guard let fromNodeIndex = nodeIndexByID[link.fromNodeID] else {
                diagnostics.append("Link '\(link.id.uuidString)' has invalid source node ID.")
                continue
            }
            guard let toNodeIndex = nodeIndexByID[link.toNodeID] else {
                diagnostics.append("Link '\(link.id.uuidString)' has invalid destination node ID.")
                continue
            }
            if fromNodeIndex == toNodeIndex {
                diagnostics.append("Link '\(link.id.uuidString)' cannot connect a node to itself.")
                continue
            }
            compiledLinks.append(
                CompiledAnimationGraph.Link(
                    id: link.id,
                    fromNodeIndex: fromNodeIndex,
                    fromSlotIndex: link.fromSlotIndex,
                    toNodeIndex: toNodeIndex,
                    toSlotIndex: link.toSlotIndex
                )
            )
        }
        let outputIncomingLinks = compiledLinks.filter { $0.toNodeIndex == outputNodeIndex }
        if outputIncomingLinks.isEmpty {
            diagnostics.append("OutputPose node has no incoming source link.")
        } else if outputIncomingLinks.count > 1 {
            diagnostics.append("OutputPose node has multiple incoming source links; exactly one is required.")
        }

        if !diagnostics.isEmpty {
            return .failure(.invalidGraph(diagnostics))
        }

        let parameterIndexByName = Dictionary(uniqueKeysWithValues: compiledParameters.map { ($0.name, $0.index) })
        let evaluationOrder = Array(0..<compiledNodes.count)
        return .success(
            CompiledAnimationGraph(
                handle: asset.handle,
                name: asset.name,
                outputNodeIndex: outputNodeIndex,
                parameters: compiledParameters,
                parameterIndexByName: parameterIndexByName,
                nodes: compiledNodes,
                links: compiledLinks,
                evaluationOrder: evaluationOrder,
                referencedClipHandles: Array(referencedClipHandles)
            )
        )
    }
}

public struct AssetMetadata: Codable {
    public var handle: AssetHandle
    public var type: AssetType
    public var sourcePath: String
    public var importSettings: [String: String]
    public var scriptLanguage: String?
    public var entryTypeName: String?
    public var dependencies: [AssetHandle]
    public var lastModified: TimeInterval

    public init(handle: AssetHandle,
                type: AssetType,
                sourcePath: String,
                importSettings: [String: String] = [:],
                scriptLanguage: String? = nil,
                entryTypeName: String? = nil,
                dependencies: [AssetHandle] = [],
                lastModified: TimeInterval = 0) {
        self.handle = handle
        self.type = type
        self.sourcePath = sourcePath
        self.importSettings = importSettings
        self.scriptLanguage = scriptLanguage
        self.entryTypeName = entryTypeName
        self.dependencies = dependencies
        self.lastModified = lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(AssetHandle.self, forKey: .handle)
        type = try container.decode(AssetType.self, forKey: .type)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        importSettings = try container.decodeIfPresent([String: String].self, forKey: .importSettings) ?? [:]
        scriptLanguage = try container.decodeIfPresent(String.self, forKey: .scriptLanguage)
        entryTypeName = try container.decodeIfPresent(String.self, forKey: .entryTypeName)
        dependencies = try container.decodeIfPresent([AssetHandle].self, forKey: .dependencies) ?? []
        lastModified = try container.decodeIfPresent(TimeInterval.self, forKey: .lastModified) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode(type, forKey: .type)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(importSettings, forKey: .importSettings)
        try container.encodeIfPresent(scriptLanguage, forKey: .scriptLanguage)
        try container.encodeIfPresent(entryTypeName, forKey: .entryTypeName)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(lastModified, forKey: .lastModified)
    }

    private enum CodingKeys: String, CodingKey {
        case handle
        case type
        case sourcePath
        case importSettings
        case scriptLanguage
        case entryTypeName
        case dependencies
        case lastModified
    }
}
