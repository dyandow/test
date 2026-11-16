import AppKit
import SpriteKit

/// Sits just above the wallpaper (below every window): dims the desktop
/// into a winter night with a moon glow and warm out-of-focus lights.
@MainActor
final class BackdropScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        let tint = SKSpriteNode(texture: Textures.verticalGradient(bottom: Art.color(0.06, 0.05, 0.12, 0.42),
                                                                   top: Art.color(0.02, 0.03, 0.10, 0.62)),
                                size: size)
        tint.anchorPoint = .zero
        addChild(tint)

        let vignette = SKSpriteNode(texture: Textures.vignette, size: size)
        vignette.anchorPoint = .zero
        vignette.zPosition = 1
        addChild(vignette)

        let moon = SKSpriteNode(texture: Textures.softDot, size: CGSize(width: 460, height: 460))
        moon.position = CGPoint(x: size.width * 0.82, y: size.height * 0.84)
        moon.color = Art.color(0.75, 0.82, 1.0)
        moon.colorBlendFactor = 1
        moon.alpha = 0.10
        moon.zPosition = 2
        addChild(moon)

        for _ in 0..<18 {
            let d = CGFloat.random(in: 18...70)
            let s = SKSpriteNode(texture: Textures.softDot, size: CGSize(width: d, height: d))
            s.position = CGPoint(x: .random(in: 0...size.width), y: size.height * .random(in: 0.04...0.32))
            s.color = Art.color(1.0, .random(in: 0.68...0.85), .random(in: 0.30...0.45))
            s.colorBlendFactor = 1
            let base = CGFloat.random(in: 0.12...0.32)
            s.alpha = base
            s.zPosition = 3
            addChild(s)
            let t = Double.random(in: 2...5)
            s.run(.repeatForever(.sequence([.fadeAlpha(to: base * 0.45, duration: t),
                                            .fadeAlpha(to: base, duration: t)])))
        }
    }
}
