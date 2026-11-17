import AppKit
import SpriteKit

/// Santa's sleigh and four reindeer, drawn facing left (flip with xScale for the other way).
@MainActor
final class Santa {
    let node = SKNode()
    private(set) var active = false
    private(set) var direction: CGFloat = -1
    private var baseY: CGFloat = 0
    private var sparkleTimer: TimeInterval = 0
    let speed: CGFloat = 230
    var droppedPresent = false

    init() {
        build()
        node.isHidden = true
    }

    /// Where the sleigh itself is (presents fall from here).
    var sleighPoint: CGPoint { CGPoint(x: node.position.x, y: node.position.y + 20) }

    func start(width: CGFloat, y: CGFloat) {
        direction = Bool.random() ? -1 : 1
        baseY = y
        node.position = CGPoint(x: direction < 0 ? width + 260 : -260, y: y)
        node.xScale = direction < 0 ? 1 : -1
        node.isHidden = false
        active = true
        droppedPresent = false
    }

    func stop() {
        active = false
        node.isHidden = true
    }

    /// Moves along; calls `sparkle` with points for a little trail. Returns false once off screen.
    func step(_ dt: TimeInterval, clock: TimeInterval, width: CGFloat, sparkle: (CGPoint) -> Void) {
        guard active else { return }
        node.position.x += direction * speed * CGFloat(dt)
        node.position.y = baseY + 14 * sin(CGFloat(clock) * 1.6) + 6 * sin(CGFloat(clock) * 4.1)
        node.zRotation = 0.04 * cos(CGFloat(clock) * 1.6) * -direction
        sparkleTimer -= dt
        if sparkleTimer <= 0 {
            sparkleTimer = 0.05
            sparkle(CGPoint(x: node.position.x - direction * 50, y: node.position.y + .random(in: -4...6)))
        }
        if (direction < 0 && node.position.x < -300) || (direction > 0 && node.position.x > width + 300) { stop() }
    }

    // MARK: - Drawing

    private func reindeer(at p: CGPoint, lead: Bool) -> SKNode {
        let r = SKNode()
        r.position = p
        let fur = Art.color(0.52, 0.33, 0.18)
        let dark = Art.color(0.30, 0.18, 0.10)
        // legs (galloping)
        for (x, phase) in [(-9.0, 0.0), (-4.0, 0.5), (7.0, 0.25), (11.0, 0.75)] as [(CGFloat, Double)] {
            let leg = SKNode()
            leg.position = CGPoint(x: x, y: -3)
            leg.addChild(Art.line([.zero, CGPoint(x: 0, y: -12)], dark, width: 2.2))
            leg.zRotation = -0.4
            leg.run(.sequence([.wait(forDuration: phase * 0.36),
                               .repeatForever(.sequence([.rotate(toAngle: 0.5, duration: 0.18), .rotate(toAngle: -0.5, duration: 0.18)]))]))
            r.addChild(leg)
        }
        r.addChild(Art.ellipse(CGRect(x: -15, y: -7, width: 30, height: 14), fur))
        r.addChild(Art.ellipse(CGRect(x: 10, y: -4, width: 8, height: 7), Art.color(0.9, 0.85, 0.78), outline: false))
        // neck and head (facing left = negative x)
        let neck = Art.polygon([CGPoint(x: -10, y: 2), CGPoint(x: -16, y: 14), CGPoint(x: -10, y: 16), CGPoint(x: -5, y: 4)], fur)
        r.addChild(neck)
        r.addChild(Art.ellipse(CGRect(x: -24, y: 11, width: 13, height: 9), fur))
        r.addChild(Art.circle(CGPoint(x: -16, y: 17), 1.2, Art.color(0.05, 0.05, 0.05), outline: false))
        if lead {
            let nose = Art.circle(CGPoint(x: -24.5, y: 14.5), 2.8, Art.color(1, 0.15, 0.15), outline: false)
            nose.glowWidth = 3
            nose.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.4), .fadeAlpha(to: 1, duration: 0.4)])))
            r.addChild(nose)
        } else {
            r.addChild(Art.circle(CGPoint(x: -24, y: 14.5), 2, dark, outline: false))
        }
        // antlers
        for dx in [-12.0, -16.0] as [CGFloat] {
            r.addChild(Art.line([CGPoint(x: dx, y: 19), CGPoint(x: dx + 2, y: 29), CGPoint(x: dx + 6, y: 33)], dark, width: 1.4))
            r.addChild(Art.line([CGPoint(x: dx + 1, y: 25), CGPoint(x: dx - 3, y: 29)], dark, width: 1.2))
        }
        r.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: 0.18), .moveBy(x: 0, y: -3, duration: 0.18)])))
        return r
    }

    private func build() {
        let red = Art.color(0.82, 0.10, 0.14)
        let gold = Art.color(0.96, 0.76, 0.28)
        // reins
        let reins = CGMutablePath()
        reins.move(to: CGPoint(x: -36, y: 26))
        reins.addQuadCurve(to: CGPoint(x: -150, y: 18), control: CGPoint(x: -95, y: 6))
        let reinsNode = SKShapeNode(path: reins)
        reinsNode.strokeColor = Art.color(0.45, 0.25, 0.12)
        reinsNode.lineWidth = 1.2
        node.addChild(reinsNode)
        // reindeer, two pairs
        node.addChild(reindeer(at: CGPoint(x: -165, y: 22), lead: true))
        node.addChild(reindeer(at: CGPoint(x: -150, y: 12), lead: false))
        node.addChild(reindeer(at: CGPoint(x: -100, y: 18), lead: false))
        node.addChild(reindeer(at: CGPoint(x: -85, y: 8), lead: false))
        // sack behind Santa
        node.addChild(Art.circle(CGPoint(x: 28, y: 40), 14, Art.color(0.55, 0.38, 0.22)))
        node.addChild(Art.box(CGRect(x: 22, y: 50, width: 12, height: 5), Art.color(0.45, 0.3, 0.16), radius: 2))
        // Santa
        node.addChild(Art.circle(CGPoint(x: 6, y: 36), 14, red))
        node.addChild(Art.box(CGRect(x: -8, y: 30, width: 28, height: 4), Art.color(0.1, 0.1, 0.1), radius: 1, outline: false))
        node.addChild(Art.box(CGRect(x: 3, y: 29, width: 6, height: 6), gold, radius: 1, outline: false))
        node.addChild(Art.circle(CGPoint(x: 4, y: 56), 8, Art.color(0.98, 0.82, 0.68)))
        node.addChild(Art.ellipse(CGRect(x: -6, y: 42, width: 18, height: 14), .white))
        node.addChild(Art.circle(CGPoint(x: 0, y: 58), 1.2, Art.color(0.1, 0.1, 0.1), outline: false))
        let hat = Art.polygon([CGPoint(x: -4, y: 62), CGPoint(x: 13, y: 62), CGPoint(x: 18, y: 76)], red)
        node.addChild(hat)
        node.addChild(Art.box(CGRect(x: -5, y: 60, width: 19, height: 4), .white, radius: 2, outline: false))
        node.addChild(Art.circle(CGPoint(x: 19, y: 77), 3, .white, outline: false))
        node.addChild(Art.line([CGPoint(x: -4, y: 38), CGPoint(x: -30, y: 28)], red, width: 4))
        node.addChild(Art.circle(CGPoint(x: -31, y: 28), 2.6, .white, outline: false))
        // sleigh
        let sleigh = CGMutablePath()
        sleigh.move(to: CGPoint(x: -40, y: 6))
        sleigh.addLine(to: CGPoint(x: 42, y: 6))
        sleigh.addQuadCurve(to: CGPoint(x: 46, y: 40), control: CGPoint(x: 52, y: 22))
        sleigh.addLine(to: CGPoint(x: 26, y: 34))
        sleigh.addLine(to: CGPoint(x: -24, y: 30))
        sleigh.addQuadCurve(to: CGPoint(x: -48, y: 30), control: CGPoint(x: -40, y: 40))
        sleigh.addQuadCurve(to: CGPoint(x: -40, y: 6), control: CGPoint(x: -50, y: 12))
        sleigh.closeSubpath()
        let body = SKShapeNode(path: sleigh)
        body.fillColor = red
        body.strokeColor = gold
        body.lineWidth = 2
        node.addChild(body)
        node.addChild(Art.line([CGPoint(x: -34, y: 18), CGPoint(x: 38, y: 18)], gold, width: 1.5))
        // runners
        let runner = CGMutablePath()
        runner.move(to: CGPoint(x: 44, y: -4))
        runner.addLine(to: CGPoint(x: -40, y: -4))
        runner.addQuadCurve(to: CGPoint(x: -52, y: 8), control: CGPoint(x: -58, y: -4))
        let r = SKShapeNode(path: runner)
        r.strokeColor = gold
        r.lineWidth = 2.5
        node.addChild(r)
        for x in [-28.0, 28.0] as [CGFloat] {
            node.addChild(Art.line([CGPoint(x: x, y: -4), CGPoint(x: x, y: 6)], gold, width: 2))
        }
    }
}

/// A wrapped present. Click it to open it.
@MainActor
final class Present {
    let node = SKNode()
    lazy var body: Body = {
        let b = Body(kind: .present, node: node, halfWidth: 13)
        b.present = self
        return b
    }()

    init() {
        let wraps: [(NSColor, NSColor)] = [
            (Art.color(0.85, 0.12, 0.15), Art.color(0.98, 0.8, 0.3)),
            (Art.color(0.12, 0.5, 0.28), Art.color(0.95, 0.15, 0.2)),
            (Art.color(0.2, 0.4, 0.85), Art.color(0.95, 0.95, 0.98)),
            (Art.color(0.95, 0.85, 0.3), Art.color(0.8, 0.1, 0.2)),
        ]
        let (paper, ribbon) = wraps.randomElement()!
        node.addChild(Art.box(CGRect(x: -13, y: 0, width: 26, height: 20), paper, radius: 2))
        node.addChild(Art.box(CGRect(x: -15, y: 17, width: 30, height: 6), paper.blended(withFraction: 0.15, of: .white) ?? paper, radius: 2))
        node.addChild(Art.box(CGRect(x: -2.5, y: 0, width: 5, height: 23), ribbon, radius: 0, outline: false))
        node.addChild(Art.box(CGRect(x: -15, y: 18, width: 30, height: 4), ribbon, radius: 0, outline: false))
        node.addChild(Art.ellipse(CGRect(x: -10, y: 21, width: 10, height: 7), ribbon))
        node.addChild(Art.ellipse(CGRect(x: 0, y: 21, width: 10, height: 7), ribbon))
        // a soft glimmer so it catches the eye
        let glint = Art.circle(CGPoint(x: -7, y: 14), 2, .white, outline: false)
        glint.run(.repeatForever(.sequence([.fadeAlpha(to: 0.1, duration: 0.8), .fadeAlpha(to: 0.9, duration: 0.8)])))
        node.addChild(glint)
    }
}
