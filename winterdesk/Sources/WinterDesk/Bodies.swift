import AppKit
import SpriteKit

/// Something that sits on window tops or the ground and can be dragged, pushed, and dropped:
/// the sled and the snowmen.
@MainActor
final class Body {
    enum Kind { case sled, snowman, present }
    enum Support: Equatable {
        case ground
        case window(CGWindowID)
    }

    let kind: Kind
    let node: SKNode
    let halfWidth: CGFloat
    /// What it's resting on (nil while in the air).
    var support: Support?
    /// Position along the support: window-relative for windows, absolute for the ground.
    var localX: CGFloat = 0
    var velocity = CGVector.zero

    // Dragging
    var dragging = false
    var grab = CGPoint.zero
    var dragVelocity = CGVector.zero
    var lastDragPoint = CGPoint.zero
    var lastDragTime: TimeInterval = 0

    /// Highest point reached since it last left a surface (to know how far it fell).
    var highestPoint: CGFloat = 0
    /// Skip the "falls too far and breaks" rule for the next landing.
    var gentleLanding = false
    /// For snowmen: the snowman this body moves.
    var snowman: Snowman?
    /// For presents: the present this body moves.
    var present: Present?

    init(kind: Kind, node: SKNode, halfWidth: CGFloat) {
        self.kind = kind
        self.node = node
        self.halfWidth = halfWidth
    }

    func hitTest(_ p: CGPoint) -> Bool {
        !node.isHidden && node.calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(p)
    }
}
