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
    private var coal: [SKNode] = []
    private let wedding = SKNode()
    private let weddingFront = SKNode()
    private(set) var isWedding = false
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
            let lump = Art.circle(CGPoint(x: x, y: y), 9, Art.color(0.1, 0.1, 0.12))
            coal.append(lump)
            add(lump)
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

        buildWedding()
    }

    /// Wedding mode: the couple rides in the second car, with a "Just Married" sign and cans.
    func setWedding(_ on: Bool) {
        isWedding = on
        wedding.isHidden = !on
        weddingFront.isHidden = !on
        coal.forEach { $0.isHidden = on }
    }

    private func face(_ n: SKNode, x: CGFloat, skin: NSColor) {
        n.addChild(Art.box(CGRect(x: x - 2.5, y: 49, width: 5, height: 6), skin, radius: 1, outline: false))
        n.addChild(Art.circle(CGPoint(x: x, y: 61), 8.5, skin))
        let ink = Art.color(0.18, 0.12, 0.10)
        n.addChild(Art.circle(CGPoint(x: x - 3, y: 61.5), 1.1, ink, outline: false))
        n.addChild(Art.circle(CGPoint(x: x + 3, y: 61.5), 1.1, ink, outline: false))
        let smile = CGMutablePath()
        smile.addArc(center: CGPoint(x: x, y: 59), radius: 3, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        let mouth = SKShapeNode(path: smile)
        mouth.strokeColor = ink
        mouth.lineWidth = 1
        n.addChild(mouth)
        let blush = Art.color(1.0, 0.55, 0.55, 0.45)
        n.addChild(Art.circle(CGPoint(x: x - 5, y: 58.5), 1.6, blush, outline: false))
        n.addChild(Art.circle(CGPoint(x: x + 5, y: 58.5), 1.6, blush, outline: false))
    }

    private func buildWedding() {
        let skin = Art.color(0.98, 0.82, 0.68)
        let tux = Art.color(0.08, 0.08, 0.10)
        let white = Art.color(0.99, 0.98, 0.96)
        let gx: CGFloat = 104   // groom
        let bx: CGFloat = 130   // bride

        // Behind the car body (their laps are "inside" the car)
        wedding.zPosition = -0.5
        node.addChild(wedding)
        // In front of the car body (the gown spilling over the side, the sign, the cans)
        weddingFront.zPosition = 1
        node.addChild(weddingFront)

        // Bride's veil, flowing back in the wind
        let veil = SKShapeNode(path: Art.polygonPath([CGPoint(x: 0, y: 0), CGPoint(x: -22, y: -6),
                                                      CGPoint(x: -30, y: -30), CGPoint(x: -8, y: -24)]))
        veil.fillColor = NSColor.white.withAlphaComponent(0.6)
        veil.strokeColor = NSColor.white.withAlphaComponent(0.8)
        veil.position = CGPoint(x: bx - 5, y: 69)
        veil.run(.repeatForever(.sequence([.scaleX(to: 1.12, duration: 0.5), .scaleX(to: 0.95, duration: 0.5)])))
        wedding.addChild(veil)

        // Groom: tux, white shirt, bow tie, arm around the bride
        wedding.addChild(Art.box(CGRect(x: gx + 4, y: 40, width: 18, height: 5), tux, radius: 2.5))
        wedding.addChild(Art.box(CGRect(x: gx - 9, y: 30, width: 18, height: 22), tux, radius: 5))
        wedding.addChild(Art.polygon([CGPoint(x: gx - 4, y: 52), CGPoint(x: gx + 4, y: 52), CGPoint(x: gx, y: 41)], white))
        wedding.addChild(Art.polygon([CGPoint(x: gx - 4.5, y: 51), CGPoint(x: gx, y: 49), CGPoint(x: gx - 4.5, y: 47)], tux, outline: false))
        wedding.addChild(Art.polygon([CGPoint(x: gx + 4.5, y: 51), CGPoint(x: gx, y: 49), CGPoint(x: gx + 4.5, y: 47)], tux, outline: false))
        wedding.addChild(Art.circle(CGPoint(x: gx - 5.5, y: 45), 1.7, Art.color(0.9, 0.15, 0.25), outline: false))
        face(wedding, x: gx, skin: skin)
        wedding.addChild(Art.ellipse(CGRect(x: gx - 9, y: 62, width: 18, height: 10), Art.color(0.22, 0.14, 0.08)))

        // Bride: long hair, gown, tiara, bouquet
        let hair = Art.color(0.45, 0.28, 0.16)
        wedding.addChild(Art.box(CGRect(x: bx - 10.5, y: 44, width: 21, height: 26), hair, radius: 8))
        wedding.addChild(Art.box(CGRect(x: bx - 8, y: 30, width: 16, height: 18), white, radius: 5))
        wedding.addChild(Art.box(CGRect(x: bx - 7, y: 46, width: 14, height: 4), skin, radius: 2, outline: false))
        face(wedding, x: bx, skin: skin)
        wedding.addChild(Art.ellipse(CGRect(x: bx - 9, y: 62, width: 18, height: 10), hair))
        for (dx, dy) in [(-4.0, 69.5), (0.0, 70.8), (4.0, 69.5)] {
            wedding.addChild(Art.circle(CGPoint(x: bx + dx, y: dy), 1.4, Art.color(0.92, 0.94, 1.0)))
        }

        // Gown skirt spilling over the side of the car, and the bouquet
        weddingFront.addChild(Art.ellipse(CGRect(x: bx - 17, y: 30, width: 34, height: 15), white))
        for dx in stride(from: -12.0, through: 12.0, by: 6.0) {
            weddingFront.addChild(Art.circle(CGPoint(x: bx + dx, y: 33), 1, Art.color(0.85, 0.85, 0.9), outline: false))
        }
        weddingFront.addChild(Art.circle(CGPoint(x: bx + 4, y: 41), 3, Art.color(0.3, 0.6, 0.3), outline: false))
        for (dx, dy, c) in [(2.0, 44.0, Art.color(1, 0.45, 0.6)), (6.0, 45.0, Art.color(1, 1, 1)),
                            (4.0, 47.5, Art.color(0.95, 0.2, 0.3)), (8.0, 43.0, Art.color(1, 0.7, 0.8))] {
            weddingFront.addChild(Art.circle(CGPoint(x: bx + dx, y: dy), 2.6, c))
        }

        // "Just Married" sign on the caboose
        weddingFront.addChild(Art.box(CGRect(x: 4, y: 24, width: 64, height: 15), white, radius: 3))
        let sign = SKLabelNode(text: "JUST MARRIED")
        sign.fontName = "HelveticaNeue-Bold"
        sign.fontSize = 7.5
        sign.fontColor = Art.color(0.8, 0.1, 0.2)
        sign.verticalAlignmentMode = .center
        sign.position = CGPoint(x: 36, y: 31.5)
        weddingFront.addChild(sign)

        // Cans tied to the back
        for i in 0..<3 {
            let cx = -16 - CGFloat(i) * 12
            weddingFront.addChild(Art.line([CGPoint(x: 0, y: 15), CGPoint(x: cx, y: 7)], Art.color(0.8, 0.8, 0.85)))
            weddingFront.addChild(Art.box(CGRect(x: cx - 3, y: 1, width: 6, height: 8), Art.color(0.75, 0.77, 0.82), radius: 1))
        }

        setWedding(false)
    }
}
