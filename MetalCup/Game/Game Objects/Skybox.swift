//
//  Skybox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/27/26.
//

import MetalKit

class Skybox: GameObject {

    override var renderPipelineState: RenderPipelineStateType { return .Skybox }

    init() {
        super.init(name: "Skybox", meshType: .Skybox)
        setScale(100)
        setCullMode(.front)
        setFrontFacing(.clockwise)
        setDepthState(.LessEqualNoWrite)
    }

    override func render(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setFragmentTexture(Assets.Textures[.EnvironmentCubemap], index: 10)
        super.render(renderCommandEncoder: renderCommandEncoder)
    }
}
