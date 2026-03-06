import QuartzCore

struct SceneUpdateScheduler {
    struct UpdateRequest {
        let frame: FrameContext
        let isPlaying: Bool
        let isPaused: Bool
        let runRuntimeScripts: Bool
        let animateInSimulateWhenScriptsDisabled: Bool
    }

    struct UpdatePipeline {
        let beginDebugFrame: (() -> Void)?
        let endDebugFrame: (() -> Void)?
        let updateInputSnapshot: (FrameContext) -> Void
        let ensureCamera: () -> Void
        let updateCamera: (_ isPlaying: Bool, _ frame: FrameContext) -> Void
        let updateSceneConstants: (FrameContext) -> Void
        let updateSky: () -> Void
        let handleRuntimeCursorToggle: (_ isPlaying: Bool) -> Void
        let scriptUpdate: (_ dt: Float, _ runRuntimeScripts: Bool) -> Void
        let animationUpdate: (_ dt: Float, _ isPlaying: Bool, _ runRuntimeScripts: Bool, _ animateInSimulateWhenScriptsDisabled: Bool) -> Void
        let audioUpdate: (_ frame: FrameContext) -> Void
        let runtimeUpdate: (_ isPlaying: Bool, _ isPaused: Bool, _ totalTime: Float) -> Void
        let syncLights: () -> Void
    }

    struct FixedRequest {
        let mode: FixedStepMode
        let fixedDelta: Float
    }

    struct FixedPipeline {
        let profiler: RendererProfiler?
        let scriptFixedPrePhysics: (_ executeScripts: Bool, _ fixedDelta: Float) -> Void
        let characterFixed: (_ fixedDelta: Float) -> Void
        let physicsStep: (_ fixedDelta: Float) -> Void
        let drainPhysicsEvents: (_ dispatchEvents: Bool) -> [PhysicsScriptEvent]?
        let scriptFixedPostPhysics: (_ executeScripts: Bool, _ dispatchEvents: Bool, _ fixedDelta: Float, _ events: [PhysicsScriptEvent]) -> Void
    }

    func runUpdate(request: UpdateRequest, pipeline: UpdatePipeline) {
        pipeline.beginDebugFrame?()
        defer { pipeline.endDebugFrame?() }
        pipeline.updateInputSnapshot(request.frame)
        pipeline.ensureCamera()
        pipeline.updateCamera(request.isPlaying, request.frame)
        pipeline.updateSceneConstants(request.frame)
        pipeline.updateSky()
        pipeline.handleRuntimeCursorToggle(request.isPlaying)
        pipeline.scriptUpdate(request.frame.time.deltaTime, request.runRuntimeScripts)
        pipeline.animationUpdate(request.frame.time.deltaTime,
                                 request.isPlaying,
                                 request.runRuntimeScripts,
                                 request.animateInSimulateWhenScriptsDisabled)
        pipeline.audioUpdate(request.frame)
        pipeline.runtimeUpdate(request.isPlaying, request.isPaused, request.frame.time.totalTime)
        pipeline.syncLights()
    }

    @discardableResult
    func runFixedStep(request: FixedRequest, pipeline: FixedPipeline) -> Float {
        @inline(__always)
        func recordScope(_ scope: RendererProfiler.Scope,
                         profiler: RendererProfiler?,
                         _ block: () -> Void) {
            guard let profiler else {
                block()
                return
            }
            let start = CACurrentMediaTime()
            block()
            profiler.record(scope, seconds: CACurrentMediaTime() - start)
        }

        recordScope(.scriptFixed, profiler: pipeline.profiler) {
            pipeline.scriptFixedPrePhysics(request.mode.contains(.executeScripts), request.fixedDelta)
        }
        recordScope(.characterFixed, profiler: pipeline.profiler) {
            pipeline.characterFixed(request.fixedDelta)
        }
        recordScope(.physicsStep, profiler: pipeline.profiler) {
            pipeline.physicsStep(request.fixedDelta)
        }

        var drainedEvents: [PhysicsScriptEvent]?
        recordScope(.physicsEvents, profiler: pipeline.profiler) {
            drainedEvents = pipeline.drainPhysicsEvents(request.mode.contains(.dispatchScriptEvents))
        }
        let fixedEvents = drainedEvents ?? []
        recordScope(.scriptPhysicsDispatch, profiler: pipeline.profiler) {
            pipeline.scriptFixedPostPhysics(request.mode.contains(.executeScripts),
                                            request.mode.contains(.dispatchScriptEvents),
                                            request.fixedDelta,
                                            fixedEvents)
        }
        return request.fixedDelta
    }
}
