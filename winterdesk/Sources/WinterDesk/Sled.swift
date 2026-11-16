import AppKit
import SpriteKit

/// A little wooden sled that rides on window tops and can be flung between them.
@MainActor
final class Sled {
    enum State {
        case onWindow(CGWindowID, localX: CGFloat)
        case flying
        case ground
    }

    let node = SKNode()
    var state: State = .ground
    var velocity = CGVector.zero
    let halfWidth: CGFloat = 28

    init() {
        let wood = Art.color(0.62, 0.38, 0.18)
        let runner = Art.color(0.80, 0.12, 0.14)
        // runners with curled fronts
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -26, y: 1))
        path.addLine(to: CGPoint(x: 22, y: 1))
        path.addQuadCurve(to: CGPoint(x: 26, y: 10), control: CGPoint(x: 32, y: 1))
        let r = SKShapeNode(path: path)
        r.strokeColor = runner
        r.lineWidth = 2.5
        node.addChild(r)
        for x in [-16.0, 12.0] as [CGFloat] {
            node.addChild(Art.box(CGRect(x: x, y: 1, width: 3, height: 6), runner, radius: 1, outline: false))
        }
        // deck planks
        node.addChild(Art.box(CGRect(x: -24, y: 6, width: 44, height: 5), wood, radius: 2))
        for x in stride(from: -18.0, through: 14.0, by: 8.0) {
            node.addChild(Art.box(CGRect(x: x, y: 6, width: 1, height: 5), Art.color(0.42, 0.25, 0.12), radius: 0, outline: false))
        }
        // pull rope
        let rope = CGMutablePath()
        rope.move(to: CGPoint(x: 24, y: 9))
        rope.addQuadCurve(to: CGPoint(x: 10, y: 12), control: CGPoint(x: 20, y: 20))
        let ropeNode = SKShapeNode(path: rope)
        ropeNode.strokeColor = Art.color(0.85, 0.75, 0.55)
        ropeNode.lineWidth = 1.2
        node.addChild(ropeNode)
    }

    func hitTest(_ p: CGPoint) -> Bool {
        !node.isHidden && node.calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(p)
    }
}
