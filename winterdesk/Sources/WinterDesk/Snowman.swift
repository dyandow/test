import AppKit
import SpriteKit

/// A snowball for rolling and stacking.
@MainActor
func makeSnowball(radius r: CGFloat) -> SKShapeNode {
    let ball = SKShapeNode(circleOfRadius: r)
    ball.fillColor = Art.color(0.97, 0.98, 1.0)
    ball.strokeColor = Art.color(0.72, 0.80, 0.93)
    ball.lineWidth = 1.2
    // a few specks so you can see it roll
    for k in 0..<4 {
        let a = CGFloat(k) * .pi / 2 + 0.4
        let speck = Art.circle(CGPoint(x: cos(a) * r * 0.55, y: sin(a) * r * 0.55), r * 0.08,
                               Art.color(0.78, 0.84, 0.94), outline: false)
        ball.addChild(speck)
    }
    return ball
}

/// A stack of up to three snowballs; at three it becomes a snowman you can dress up.
@MainActor
final class Snowman {
    let node = SKNode()
    private let decor = SKNode()      // face, buttons, outfit, hat: in front of the snowballs
    private let armsNode = SKNode()   // arms: behind the snowballs
    private(set) var radii: [CGFloat] = []
    private var top: CGFloat = 0
    private var centers: [CGFloat] = []
    private(set) var style: SnowmanStyle

    var isComplete: Bool { radii.count >= 3 }
    var baseRadius: CGFloat { radii.first ?? 0 }
    /// Height of the top of the stack above its base.
    var stackHeight: CGFloat { top }

    lazy var body: Body = {
        let b = Body(kind: .snowman, node: node, halfWidth: 14)
        b.snowman = self
        return b
    }()

    init(at p: CGPoint, style: SnowmanStyle) {
        node.position = p
        self.style = style
        decor.zPosition = 1
        armsNode.zPosition = -1
        node.addChild(decor)
        node.addChild(armsNode)
    }

    /// Adds a ball on top. Returns true when that completes the snowman.
    @discardableResult
    func add(radius r: CGFloat, chime: Bool = true) -> Bool {
        guard radii.count < 3 else { return false }
        let y = radii.isEmpty ? r : top + r * 0.78
        let ball = makeSnowball(radius: r)
        ball.position = CGPoint(x: 0, y: y)
        ball.setScale(0.6)
        ball.run(.scale(to: 1, duration: 0.15))
        node.addChild(ball)
        radii.append(r)
        centers.append(y)
        top = y + r
        if radii.count == 3 {
            redrawDecor()
            node.run(.sequence([.scale(to: 1.08, duration: 0.12), .scale(to: 1.0, duration: 0.12)]))
            if chime { NSSound(named: NSSound.Name("Glass"))?.play() }
            return true
        }
        return false
    }

    /// Stacks another snowball (or partial snowman) on top of this one, if there's room.
    func absorb(_ other: Snowman) -> Bool {
        guard radii.count + other.radii.count <= 3 else { return false }
        for r in other.radii { add(radius: r) }
        return true
    }

    func apply(_ newStyle: SnowmanStyle) {
        style = newStyle
        if isComplete { redrawDecor() }
    }

    // MARK: - Drawing the outfit

    private let coal = Art.color(0.1, 0.1, 0.12)

    private func arc(_ c: CGPoint, _ r: CGFloat, from a: CGFloat, to b: CGFloat, width: CGFloat) -> SKShapeNode {
        let p = CGMutablePath()
        p.addArc(center: c, radius: r, startAngle: a, endAngle: b, clockwise: false)
        let s = SKShapeNode(path: p)
        s.strokeColor = coal
        s.lineWidth = width
        s.lineCap = .round
        return s
    }

    private func redrawDecor() {
        decor.removeAllChildren()
        decor.removeAllActions()
        armsNode.removeAllChildren()
        guard isComplete else { return }
        let hy = centers[2], R = radii[2]
        let my = centers[1], mr = radii[1]
        let add: (SKNode) -> Void = { self.decor.addChild($0) }

        // Arms go behind the body
        let arms = armsNode
        let brown = Art.color(0.36, 0.22, 0.12)
        func stickArm(_ side: CGFloat, up: Bool) -> SKNode {
            let arm = SKNode()
            arm.position = CGPoint(x: side * mr * 0.75, y: my + mr * 0.25)
            let end = CGPoint(x: side * mr * 1.25, y: up ? mr * 1.0 : mr * 0.45)
            arm.addChild(Art.line([.zero, end], brown, width: max(1.6, mr * 0.12)))
            let fork = CGPoint(x: end.x * 0.7, y: end.y * 0.7)
            arm.addChild(Art.line([fork, CGPoint(x: fork.x + side * mr * 0.25, y: fork.y + mr * 0.3)], brown, width: max(1.2, mr * 0.08)))
            if style.arms == .mittens {
                arm.addChild(Art.circle(end, max(2.5, mr * 0.22), Art.color(0.85, 0.15, 0.18)))
            }
            return arm
        }
        switch style.arms {
        case .none: break
        case .sticks, .mittens:
            arms.addChild(stickArm(-1, up: false))
            arms.addChild(stickArm(1, up: false))
        case .waving:
            arms.addChild(stickArm(-1, up: false))
            let wave = stickArm(1, up: true)
            wave.run(.repeatForever(.sequence([.rotate(toAngle: 0.35, duration: 0.3), .rotate(toAngle: -0.1, duration: 0.3)])))
            arms.addChild(wave)
        }

        // Buttons
        for k in 0..<3 {
            add(Art.circle(CGPoint(x: 0, y: my + mr * (0.45 - CGFloat(k) * 0.42)), max(1.4, mr * 0.09), coal, outline: false))
        }

        // Outfit at the neck
        let neckY = hy - R * 0.9
        func scarf(_ c1: NSColor, _ c2: NSColor?) {
            add(Art.box(CGRect(x: -R * 1.05, y: neckY - R * 0.18, width: R * 2.1, height: R * 0.36), c1, radius: R * 0.15))
            let tail = Art.box(CGRect(x: R * 0.35, y: neckY - R * 1.0, width: R * 0.32, height: R * 0.9), c1, radius: R * 0.1)
            tail.zRotation = -0.15
            add(tail)
            if let c2 {
                for k in 0..<4 {
                    add(Art.box(CGRect(x: -R * 0.9 + CGFloat(k) * R * 0.5, y: neckY - R * 0.18, width: R * 0.18, height: R * 0.36),
                                c2, radius: 0, outline: false))
                }
                for k in 0..<2 {
                    let stripe = Art.box(CGRect(x: R * 0.37, y: neckY - R * (0.45 + CGFloat(k) * 0.3), width: R * 0.28, height: R * 0.1),
                                         c2, radius: 0, outline: false)
                    stripe.zRotation = -0.15
                    add(stripe)
                }
            }
        }
        switch style.outfit {
        case .redScarf: scarf(Art.color(0.85, 0.15, 0.18), nil)
        case .greenScarf: scarf(Art.color(0.12, 0.55, 0.28), nil)
        case .stripedScarf: scarf(Art.color(0.85, 0.15, 0.18), Art.color(0.98, 0.97, 0.95))
        case .bowTie:
            let red = Art.color(0.85, 0.12, 0.2)
            add(Art.polygon([CGPoint(x: 0, y: neckY), CGPoint(x: -R * 0.45, y: neckY + R * 0.22), CGPoint(x: -R * 0.45, y: neckY - R * 0.22)], red))
            add(Art.polygon([CGPoint(x: 0, y: neckY), CGPoint(x: R * 0.45, y: neckY + R * 0.22), CGPoint(x: R * 0.45, y: neckY - R * 0.22)], red))
            add(Art.circle(CGPoint(x: 0, y: neckY), R * 0.1, red))
        case .none: break
        }

        // Face
        let eyeL = CGPoint(x: -R * 0.32, y: hy + R * 0.2), eyeR = CGPoint(x: R * 0.32, y: hy + R * 0.2)
        let eyeR0 = max(1.2, R * 0.1)
        let stroke = max(1.1, R * 0.09)
        func dotEyes() { add(Art.circle(eyeL, eyeR0, coal, outline: false)); add(Art.circle(eyeR, eyeR0, coal, outline: false)) }
        func dotSmile() {
            for k in -2...2 {
                add(Art.circle(CGPoint(x: CGFloat(k) * R * 0.18, y: hy - R * 0.4 + abs(CGFloat(k)) * R * 0.07),
                               max(0.8, R * 0.05), coal, outline: false))
            }
        }
        func smile() { add(arc(CGPoint(x: 0, y: hy - R * 0.15), R * 0.35, from: .pi * 1.15, to: .pi * 1.85, width: stroke)) }
        switch style.face {
        case .classic:
            dotEyes(); dotSmile()
        case .happy:
            add(arc(eyeL, R * 0.13, from: 0.2, to: .pi - 0.2, width: stroke))
            add(arc(eyeR, R * 0.13, from: 0.2, to: .pi - 0.2, width: stroke))
            smile()
        case .wink:
            add(Art.circle(eyeL, eyeR0, coal, outline: false))
            add(Art.line([CGPoint(x: eyeR.x - R * 0.13, y: eyeR.y), CGPoint(x: eyeR.x + R * 0.13, y: eyeR.y)], coal, width: stroke))
            smile()
        case .cool:
            let glass = Art.color(0.08, 0.08, 0.1)
            add(Art.box(CGRect(x: eyeL.x - R * 0.24, y: eyeL.y - R * 0.12, width: R * 0.46, height: R * 0.26), glass, radius: R * 0.08))
            add(Art.box(CGRect(x: eyeR.x - R * 0.22, y: eyeR.y - R * 0.12, width: R * 0.46, height: R * 0.26), glass, radius: R * 0.08))
            add(Art.line([CGPoint(x: eyeL.x + R * 0.2, y: eyeL.y + R * 0.06), CGPoint(x: eyeR.x - R * 0.2, y: eyeR.y + R * 0.06)], glass, width: stroke))
            add(Art.line([CGPoint(x: -R * 0.2, y: hy - R * 0.42), CGPoint(x: R * 0.3, y: hy - R * 0.36)], coal, width: stroke))
        case .surprised:
            for e in [eyeL, eyeR] {
                add(Art.circle(e, eyeR0 * 1.6, coal, outline: false))
                add(Art.circle(CGPoint(x: e.x + eyeR0 * 0.5, y: e.y + eyeR0 * 0.5), eyeR0 * 0.45, .white, outline: false))
            }
            let o = SKShapeNode(circleOfRadius: R * 0.14)
            o.position = CGPoint(x: 0, y: hy - R * 0.45)
            o.strokeColor = coal
            o.lineWidth = stroke
            o.fillColor = Art.color(0.3, 0.1, 0.1)
            add(o)
        case .sleepy:
            add(arc(eyeL, R * 0.13, from: .pi * 1.1, to: .pi * 1.9, width: stroke))
            add(arc(eyeR, R * 0.13, from: .pi * 1.1, to: .pi * 1.9, width: stroke))
            add(Art.line([CGPoint(x: -R * 0.12, y: hy - R * 0.42), CGPoint(x: R * 0.12, y: hy - R * 0.42)], coal, width: stroke))
            let z = SKLabelNode(text: "z")
            z.fontName = "HelveticaNeue-Bold"
            z.fontSize = max(8, R * 0.7)
            z.fontColor = Art.color(0.55, 0.7, 1.0)
            z.position = CGPoint(x: R * 0.9, y: hy + R * 0.9)
            z.run(.repeatForever(.sequence([.group([.moveBy(x: R * 0.3, y: R * 0.6, duration: 1.4), .fadeOut(withDuration: 1.4)]),
                                            .moveBy(x: -R * 0.3, y: -R * 0.6, duration: 0), .fadeIn(withDuration: 0.2)])))
            add(z)
        case .grumpy:
            dotEyes()
            add(Art.line([CGPoint(x: eyeL.x - R * 0.15, y: eyeL.y + R * 0.25), CGPoint(x: eyeL.x + R * 0.15, y: eyeL.y + R * 0.13)], coal, width: stroke))
            add(Art.line([CGPoint(x: eyeR.x + R * 0.15, y: eyeR.y + R * 0.25), CGPoint(x: eyeR.x - R * 0.15, y: eyeR.y + R * 0.13)], coal, width: stroke))
            add(arc(CGPoint(x: 0, y: hy - R * 0.62), R * 0.25, from: .pi * 0.2, to: .pi * 0.8, width: stroke))
        case .inLove:
            for e in [eyeL, eyeR] {
                let h = SKShapeNode(path: Art.heartPath(size: R * 0.16))
                h.fillColor = Art.color(0.95, 0.2, 0.35)
                h.strokeColor = .clear
                h.position = e
                h.run(.repeatForever(.sequence([.scale(to: 1.2, duration: 0.35), .scale(to: 1.0, duration: 0.35)])))
                add(h)
            }
            smile()
            add(Art.circle(CGPoint(x: -R * 0.55, y: hy - R * 0.15), R * 0.12, Art.color(1, 0.5, 0.55, 0.6), outline: false))
            add(Art.circle(CGPoint(x: R * 0.55, y: hy - R * 0.15), R * 0.12, Art.color(1, 0.5, 0.55, 0.6), outline: false))
        }
        // Carrot nose
        add(Art.polygon([CGPoint(x: 0, y: hy + R * 0.06), CGPoint(x: 0, y: hy - R * 0.14),
                         CGPoint(x: R * 0.85, y: hy - R * 0.06)], Art.color(1.0, 0.55, 0.12)))

        // Hat
        let base = hy + R * 0.72
        switch style.hat {
        case .topHat:
            add(Art.box(CGRect(x: -R * 0.95, y: base, width: R * 1.9, height: R * 0.2), coal, radius: 1))
            add(Art.box(CGRect(x: -R * 0.6, y: base, width: R * 1.2, height: R * 1.0), coal, radius: 1.5))
            add(Art.box(CGRect(x: -R * 0.6, y: base + R * 0.22, width: R * 1.2, height: R * 0.18), Art.color(0.85, 0.15, 0.18), radius: 0, outline: false))
        case .santa:
            let red = Art.color(0.85, 0.12, 0.15)
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: -R * 0.85, y: base + R * 0.1))
            cone.addQuadCurve(to: CGPoint(x: R * 1.25, y: base + R * 0.45), control: CGPoint(x: R * 0.1, y: base + R * 1.6))
            cone.addQuadCurve(to: CGPoint(x: R * 0.85, y: base + R * 0.1), control: CGPoint(x: R * 0.6, y: base + R * 0.8))
            cone.closeSubpath()
            let c = SKShapeNode(path: cone)
            c.fillColor = red
            c.strokeColor = red.blended(withFraction: 0.3, of: .black) ?? red
            add(c)
            add(Art.box(CGRect(x: -R * 0.95, y: base - R * 0.05, width: R * 1.9, height: R * 0.3), .white, radius: R * 0.15))
            add(Art.circle(CGPoint(x: R * 1.25, y: base + R * 0.45), R * 0.2, .white))
        case .beanie:
            let blue = Art.color(0.2, 0.45, 0.85)
            let dome = SKShapeNode(path: {
                let p = CGMutablePath()
                p.addArc(center: CGPoint(x: 0, y: base), radius: R * 0.9, startAngle: 0, endAngle: .pi, clockwise: false)
                p.closeSubpath()
                return p
            }())
            dome.fillColor = blue
            dome.strokeColor = blue.blended(withFraction: 0.3, of: .black) ?? blue
            add(dome)
            add(Art.box(CGRect(x: -R * 0.95, y: base - R * 0.12, width: R * 1.9, height: R * 0.3), Art.color(0.95, 0.95, 0.95), radius: R * 0.1))
            add(Art.box(CGRect(x: -R * 0.82, y: base + R * 0.35, width: R * 1.64, height: R * 0.14), Art.color(0.95, 0.95, 0.95), radius: 0, outline: false))
            add(Art.circle(CGPoint(x: 0, y: base + R * 0.95), R * 0.2, Art.color(0.95, 0.95, 0.95)))
        case .earmuffs:
            add(arc(CGPoint(x: 0, y: hy), R * 1.0, from: 0.15, to: .pi - 0.15, width: max(1.5, R * 0.12)))
            add(Art.circle(CGPoint(x: -R * 0.98, y: hy + R * 0.05), R * 0.26, Art.color(1.0, 0.55, 0.75)))
            add(Art.circle(CGPoint(x: R * 0.98, y: hy + R * 0.05), R * 0.26, Art.color(1.0, 0.55, 0.75)))
        case .bucket:
            let pail = Art.polygon([CGPoint(x: -R * 0.7, y: base - R * 0.05), CGPoint(x: R * 0.7, y: base - R * 0.05),
                                    CGPoint(x: R * 0.55, y: base + R * 0.85), CGPoint(x: -R * 0.55, y: base + R * 0.85)],
                                   Art.color(0.55, 0.6, 0.66))
            pail.zRotation = 0.12
            add(pail)
        case .none: break
        }
    }
}
