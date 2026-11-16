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

/// A stack of up to three snowballs; at three it gets a face, scarf and hat.
@MainActor
final class Snowman {
    let node = SKNode()
    private(set) var radii: [CGFloat] = []
    private var top: CGFloat = 0
    private var centers: [CGFloat] = []

    var isComplete: Bool { radii.count >= 3 }
    var baseRadius: CGFloat { radii.first ?? 0 }

    init(at p: CGPoint) {
        node.position = p
    }

    func hitTest(_ p: CGPoint) -> Bool {
        node.calculateAccumulatedFrame().insetBy(dx: -4, dy: -4).contains(p)
    }

    /// Adds a ball on top. Returns true when that completes the snowman.
    @discardableResult
    func add(radius r: CGFloat) -> Bool {
        let y = radii.isEmpty ? r : top + r * 0.78
        let ball = makeSnowball(radius: r)
        ball.position = CGPoint(x: 0, y: y)
        ball.setScale(0.6)
        ball.run(.scale(to: 1, duration: 0.15))
        node.addChild(ball)
        radii.append(r)
        centers.append(y)
        top = y + r
        if radii.count == 3 { decorate(); return true }
        return false
    }

    private func decorate() {
        let headY = centers[2], headR = radii[2]
        let midY = centers[1], midR = radii[1]
        let coal = Art.color(0.1, 0.1, 0.12)

        // buttons
        for k in 0..<3 {
            node.addChild(Art.circle(CGPoint(x: 0, y: midY + midR * (0.45 - CGFloat(k) * 0.42)),
                                     max(1.4, midR * 0.09), coal, outline: false))
        }
        // scarf
        let scarfY = headY - headR * 0.9
        let red = Art.color(0.85, 0.15, 0.18)
        node.addChild(Art.box(CGRect(x: -headR * 1.05, y: scarfY - headR * 0.18, width: headR * 2.1, height: headR * 0.36),
                              red, radius: headR * 0.15))
        let tail = Art.box(CGRect(x: headR * 0.35, y: scarfY - headR * 1.0, width: headR * 0.32, height: headR * 0.9),
                           red, radius: headR * 0.1)
        tail.zRotation = -0.15
        node.addChild(tail)
        // face
        node.addChild(Art.circle(CGPoint(x: -headR * 0.32, y: headY + headR * 0.2), max(1.2, headR * 0.1), coal, outline: false))
        node.addChild(Art.circle(CGPoint(x: headR * 0.32, y: headY + headR * 0.2), max(1.2, headR * 0.1), coal, outline: false))
        node.addChild(Art.polygon([CGPoint(x: 0, y: headY + headR * 0.08), CGPoint(x: 0, y: headY - headR * 0.14),
                                   CGPoint(x: headR * 0.85, y: headY - headR * 0.05)], Art.color(1.0, 0.55, 0.12)))
        for k in -2...2 {
            node.addChild(Art.circle(CGPoint(x: CGFloat(k) * headR * 0.18, y: headY - headR * 0.4 + abs(CGFloat(k)) * headR * 0.07),
                                     max(0.8, headR * 0.05), coal, outline: false))
        }
        // top hat
        let hatBase = headY + headR * 0.78
        node.addChild(Art.box(CGRect(x: -headR * 0.95, y: hatBase, width: headR * 1.9, height: headR * 0.2), coal, radius: 1))
        node.addChild(Art.box(CGRect(x: -headR * 0.6, y: hatBase, width: headR * 1.2, height: headR * 1.0), coal, radius: 1.5))
        node.addChild(Art.box(CGRect(x: -headR * 0.6, y: hatBase + headR * 0.22, width: headR * 1.2, height: headR * 0.18),
                              red, radius: 0, outline: false))

        node.run(.sequence([.scale(to: 1.08, duration: 0.12), .scale(to: 1.0, duration: 0.12)]))
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
