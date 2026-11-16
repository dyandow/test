import AppKit
import SpriteKit

/// A cartoon red steam train (caboose, coal car, engine with a snow plow)
/// that chugs left to right along the bottom of the screen.
@MainActor
final class Train {
    let node = SKNode()
    /// From the back of the caboose to the tip of the plow.
    let length: CGFloat = 300
    var sceneWidth: CGFloat

    private var wheels: [(node: SKNode, radius: CGFloat)] = []
    private let chimneyTop = CGPoint(x: 258, y: 74)
    private let cruiseSpeed: CGFloat = 65
    private var boost: TimeInterval = 0
    private var waiting: TimeInterval = 0
    private var smokeTimer: TimeInterval = 0
    private(set) var speed: CGFloat = 0

    var rearX: CGFloat { node.position.x }
    var frontX: CGFloat { node.position.x + length }
    var isRunning: Bool { waiting <= 0 && !node.isHidden }

    init(sceneWidth: CGFloat, baseY: CGFloat) {
        self.sceneWidth = sceneWidth
        node.position = CGPoint(x: -length - 20, y: baseY)
        build()
    }

    func hitTest(_ p: CGPoint) -> Bool {
        !node.isHidden && node.calculateAccumulatedFrame().contains(p)
    }

    /// Click the train: it whistles out a big puff of smoke and hurries for a bit.
    func toot() { boost = 2.5 }

    /// Advances the train. `smoke` is called with scene points where a puff should appear.
    func step(_ dt: TimeInterval, smoke: (CGPoint, Bool) -> Void) {
        if waiting > 0 {
            waiting -= dt
            if waiting <= 0 { node.position.x = -length - 20 }
            speed = 0
            return
        }
        speed = cruiseSpeed * (boost > 0 ? 2.2 : 1)
        boost = max(0, boost - dt)
        node.position.x += speed * CGFloat(dt)
        for w in wheels { w.node.zRotation -= speed * CGFloat(dt) / w.radius }

        smokeTimer -= dt
        if smokeTimer <= 0 {
            smokeTimer = boost > 0 ? 0.1 : 0.32
            smoke(CGPoint(x: node.position.x + chimneyTop.x, y: node.position.y + chimneyTop.y), boost > 0)
        }
        if node.position.x > sceneWidth + 60 { waiting = 8 }
    }

    // MARK: - Drawing

    private func wheel(at c: CGPoint, r: CGFloat) -> SKNode {
        let w = Art.circle(c, r, Art.color(0.14, 0.14, 0.17))
        w.strokeColor = Art.color(0.85, 0.66, 0.25)
        w.lineWidth = 2
        for k in 0..<3 {
            let spoke = Art.box(CGRect(x: -r + 2, y: -1, width: 2 * r - 4, height: 2),
                                Art.color(0.85, 0.66, 0.25), radius: 1, outline: false)
            spoke.zRotation = CGFloat(k) * .pi / 3
            w.addChild(spoke)
        }
        w.addChild(Art.circle(.zero, r * 0.28, Art.color(0.9, 0.72, 0.3)))
        w.zPosition = 2
        wheels.append((w, r))
        return w
    }

    private func build() {
        let red = Art.color(0.84, 0.13, 0.15)
        let darkRed = Art.color(0.60, 0.08, 0.10)
        let iron = Art.color(0.16, 0.16, 0.19)
        let gold = Art.color(0.98, 0.78, 0.30)
        let glow = Art.color(1.0, 0.86, 0.45)
        let add: (SKNode) -> Void = { self.node.addChild($0) }

        // Caboose (x 0...72)
        add(Art.box(CGRect(x: 0, y: 12, width: 72, height: 38), red, radius: 4))
        add(Art.box(CGRect(x: 22, y: 50, width: 28, height: 16), red, radius: 3))
        add(Art.box(CGRect(x: 18, y: 64, width: 36, height: 5), darkRed, radius: 2))
        add(Art.box(CGRect(x: -3, y: 48, width: 78, height: 6), darkRed, radius: 3))
        add(Art.box(CGRect(x: 10, y: 28, width: 14, height: 12), glow, radius: 2))
        add(Art.box(CGRect(x: 48, y: 28, width: 14, height: 12), glow, radius: 2))
        add(Art.box(CGRect(x: 0, y: 17, width: 72, height: 3), gold, radius: 1, outline: false))
        add(wheel(at: CGPoint(x: 16, y: 9), r: 9))
        add(wheel(at: CGPoint(x: 56, y: 9), r: 9))

        // Couplers
        add(Art.box(CGRect(x: 72, y: 16, width: 8, height: 4), iron, radius: 1))
        add(Art.box(CGRect(x: 152, y: 16, width: 8, height: 4), iron, radius: 1))

        // Coal car (x 80...152)
        for (x, y) in [(92.0, 40.0), (106.0, 44.0), (121.0, 42.0), (136.0, 44.0), (146.0, 39.0)] {
            add(Art.circle(CGPoint(x: x, y: y), 9, Art.color(0.1, 0.1, 0.12)))
        }
        add(Art.box(CGRect(x: 80, y: 12, width: 72, height: 26), red, radius: 3))
        add(Art.box(CGRect(x: 78, y: 35, width: 76, height: 5), darkRed, radius: 2))
        add(Art.box(CGRect(x: 80, y: 17, width: 72, height: 3), gold, radius: 1, outline: false))
        add(wheel(at: CGPoint(x: 96, y: 9), r: 9))
        add(wheel(at: CGPoint(x: 136, y: 9), r: 9))

        // Engine (x 160...300)
        add(Art.box(CGRect(x: 160, y: 12, width: 112, height: 8), iron, radius: 2))
        add(Art.box(CGRect(x: 160, y: 18, width: 40, height: 52), darkRed, radius: 3))
        add(Art.box(CGRect(x: 156, y: 68, width: 48, height: 7), iron, radius: 3))
        add(Art.box(CGRect(x: 170, y: 44, width: 20, height: 16), glow, radius: 2))
        add(Art.box(CGRect(x: 198, y: 20, width: 70, height: 30), red, radius: 12))
        add(Art.box(CGRect(x: 214, y: 20, width: 4, height: 30), gold, radius: 1, outline: false))
        add(Art.box(CGRect(x: 244, y: 20, width: 4, height: 30), gold, radius: 1, outline: false))
        add(Art.circle(CGPoint(x: 228, y: 51), 8, gold))
        add(Art.box(CGRect(x: 252, y: 48, width: 13, height: 22), iron, radius: 2))
        add(Art.box(CGRect(x: 248, y: 68, width: 21, height: 6), iron, radius: 2))
        add(Art.box(CGRect(x: 264, y: 20, width: 8, height: 30), iron, radius: 3))
        let lamp = Art.circle(CGPoint(x: 272, y: 46), 5, glow)
        lamp.glowWidth = 4
        add(lamp)
        // Plow (cow-catcher) that pushes the snow
        add(Art.polygon([CGPoint(x: 264, y: 1), CGPoint(x: 300, y: 1), CGPoint(x: 268, y: 30)],
                        Art.color(0.32, 0.33, 0.38)))
        add(wheel(at: CGPoint(x: 180, y: 9), r: 9))
        add(wheel(at: CGPoint(x: 214, y: 12), r: 12))
        add(wheel(at: CGPoint(x: 244, y: 12), r: 12))
        let rod = Art.box(CGRect(x: 210, y: 10, width: 38, height: 3), gold, radius: 1)
        rod.zPosition = 3
        add(rod)
    }
}
