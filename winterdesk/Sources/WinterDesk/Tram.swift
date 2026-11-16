import AppKit
import SpriteKit

/// The little station at the top-center of the screen. Drag from it to string a new cable.
@MainActor
final class TramStation {
    let node = SKNode()
    private let hint: SKLabelNode

    /// Where cables leave the station, in scene coordinates.
    var anchor: CGPoint { CGPoint(x: node.position.x, y: node.position.y - 12) }

    init() {
        let red = Art.color(0.84, 0.13, 0.15)
        node.addChild(Art.box(CGRect(x: -38, y: -12, width: 76, height: 24), Art.color(0.18, 0.20, 0.27, 0.95), radius: 6))
        node.addChild(Art.polygon([CGPoint(x: -46, y: 11), CGPoint(x: 46, y: 11), CGPoint(x: 0, y: 26)],
                                  Art.color(0.60, 0.08, 0.10)))
        node.addChild(Art.polygon([CGPoint(x: -40, y: 15), CGPoint(x: 40, y: 15), CGPoint(x: 0, y: 26)],
                                  Art.color(0.95, 0.97, 1.0), outline: false))
        // tiny tram in the window
        node.addChild(Art.box(CGRect(x: -11, y: -6, width: 22, height: 13), red, radius: 3))
        node.addChild(Art.box(CGRect(x: -8, y: -1, width: 6, height: 5), Art.color(1, 0.86, 0.45), radius: 1, outline: false))
        node.addChild(Art.box(CGRect(x: 2, y: -1, width: 6, height: 5), Art.color(1, 0.86, 0.45), radius: 1, outline: false))
        node.addChild(Art.circle(CGPoint(x: 0, y: -12), 4, Art.color(0.98, 0.78, 0.30)))

        hint = SKLabelNode(text: "drag me")
        hint.fontName = "HelveticaNeue-Bold"
        hint.fontSize = 10
        hint.fontColor = NSColor.white.withAlphaComponent(0.85)
        hint.position = CGPoint(x: 0, y: -30)
        node.addChild(hint)
    }

    func showHint(_ show: Bool) { hint.isHidden = !show }

    func hitTest(_ p: CGPoint) -> Bool {
        let frame = CGRect(x: node.position.x - 46, y: node.position.y - 18, width: 92, height: 46)
        return frame.contains(p)
    }
}

/// A sagging cable from the station to wherever it was dropped,
/// with a red tram car gliding down it and back up again.
@MainActor
final class TramLine {
    let start: CGPoint
    private(set) var end: CGPoint
    private let cable = SKShapeNode()
    private let post = SKNode()
    private let car = SKNode()
    private var t: CGFloat = 0
    private var direction: CGFloat = 1
    private var pause: TimeInterval = 1.0
    private let carSpeed: CGFloat = 80

    init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
        cable.strokeColor = Art.color(0.10, 0.10, 0.13, 0.95)
        cable.lineWidth = 2
        cable.zPosition = 24

        post.zPosition = 25
        post.addChild(Art.circle(.zero, 7, Art.color(0.20, 0.21, 0.26)))
        post.addChild(Art.circle(.zero, 3, Art.color(0.84, 0.13, 0.15), outline: false))

        car.zPosition = 26
        let red = Art.color(0.84, 0.13, 0.15)
        let glow = Art.color(1.0, 0.86, 0.45)
        car.addChild(Art.box(CGRect(x: -1, y: -14, width: 2, height: 14), Art.color(0.12, 0.12, 0.15), radius: 0.5, outline: false))
        car.addChild(Art.circle(.zero, 3.5, Art.color(0.25, 0.25, 0.3)))
        car.addChild(Art.box(CGRect(x: -19, y: -16, width: 38, height: 5), Art.color(0.60, 0.08, 0.10), radius: 2))
        car.addChild(Art.box(CGRect(x: -17, y: -40, width: 34, height: 26), red, radius: 5))
        car.addChild(Art.box(CGRect(x: -13, y: -28, width: 11, height: 9), glow, radius: 2, outline: false))
        car.addChild(Art.box(CGRect(x: 2, y: -28, width: 11, height: 9), glow, radius: 2, outline: false))
        car.addChild(Art.box(CGRect(x: -17, y: -36, width: 34, height: 2.5), Art.color(0.98, 0.78, 0.30), radius: 1, outline: false))

        setEnd(end)
    }

    func add(to parent: SKNode) {
        parent.addChild(cable)
        parent.addChild(post)
        parent.addChild(car)
    }

    func remove() {
        cable.removeFromParent()
        post.removeFromParent()
        car.removeFromParent()
    }

    private var length: CGFloat { hypot(end.x - start.x, end.y - start.y) }

    private var control: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - length * 0.07)
    }

    private func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t, c = control
        return CGPoint(x: u * u * start.x + 2 * u * t * c.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * c.y + t * t * end.y)
    }

    func setEnd(_ p: CGPoint) {
        end = p
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        cable.path = path
        post.position = end
        car.position = point(t)
    }

    func endHitTest(_ p: CGPoint) -> Bool { hypot(p.x - end.x, p.y - end.y) < 14 }

    func step(_ dt: TimeInterval) {
        if pause > 0 { pause -= dt; return }
        // slow near the ends, quicker in the middle
        let ease = 0.25 + 0.75 * sin(CGFloat.pi * min(max(t, 0.03), 0.97))
        t += direction * CGFloat(dt) * carSpeed * ease / max(length, 1)
        if t >= 1 { t = 1; direction = -1; pause = 1.5 }
        if t <= 0 { t = 0; direction = 1; pause = 1.5 }
        car.position = point(t)
    }

    /// Dashed line shown while dragging out a new cable.
    static func previewPath(from a: CGPoint, to b: CGPoint) -> CGPath {
        let p = CGMutablePath()
        p.move(to: a)
        p.addLine(to: b)
        return p.copy(dashingWithPhase: 0, lengths: [6, 4])
    }
}
