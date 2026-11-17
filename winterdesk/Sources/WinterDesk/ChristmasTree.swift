import AppKit
import SpriteKit

/// A little tree you can drag around. Click its branches to hang a light,
/// click a light to take it off.
@MainActor
final class ChristmasTree {
    let node = SKNode()
    private let lights = SKNode()
    private var tiers: [CGPath] = []
    private var nextColor = 0

    static let palette: [NSColor] = [
        Art.color(1.0, 0.27, 0.27), Art.color(1.0, 0.82, 0.25), Art.color(0.35, 0.65, 1.0),
        Art.color(0.45, 1.0, 0.50), Art.color(1.0, 0.50, 0.85), Art.color(1.0, 0.97, 0.85),
    ]

    init() {
        let gold = Art.color(0.86, 0.62, 0.22)
        node.addChild(Art.polygon([CGPoint(x: -18, y: -16), CGPoint(x: 18, y: -16),
                                   CGPoint(x: 23, y: 4), CGPoint(x: -23, y: 4)], gold))
        node.addChild(Art.box(CGRect(x: -26, y: 2, width: 52, height: 6), Art.color(0.95, 0.74, 0.32), radius: 3))
        node.addChild(Art.box(CGRect(x: -7, y: 6, width: 14, height: 14), Art.color(0.42, 0.26, 0.14), radius: 1))

        for i in 0..<3 {
            let base = 16 + CGFloat(i) * 30
            let half = 54 - CGFloat(i) * 13
            let path = Art.polygonPath([CGPoint(x: -half, y: base), CGPoint(x: half, y: base),
                                        CGPoint(x: 0, y: base + 50)])
            let tier = SKShapeNode(path: path)
            tier.fillColor = Art.color(0.10, 0.42 + 0.06 * CGFloat(i), 0.24)
            tier.strokeColor = Art.color(0.05, 0.28, 0.15)
            tier.lineWidth = 1.5
            node.addChild(tier)
            // a dusting of snow along each tier's edge
            let snow = Art.box(CGRect(x: -half + 6, y: base - 1, width: 2 * half - 12, height: 3.5),
                               Art.color(0.95, 0.97, 1.0, 0.9), radius: 1.75, outline: false)
            node.addChild(snow)
            tiers.append(path)
        }

        let star = SKShapeNode(path: Art.starPath(radius: 11, inner: 5))
        star.position = CGPoint(x: 0, y: 127)
        star.fillColor = Art.color(1.0, 0.84, 0.30)
        star.strokeColor = Art.color(0.85, 0.6, 0.15)
        star.glowWidth = 3
        star.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 1.2), .scale(to: 1.0, duration: 1.2)])))
        node.addChild(star)

        lights.zPosition = 2
        node.addChild(lights)
    }

    func hitTest(_ scenePoint: CGPoint) -> Bool {
        !node.isHidden && node.calculateAccumulatedFrame().insetBy(dx: -4, dy: -4).contains(scenePoint)
    }

    /// Whether a click landed on the star at the top.
    func starHit(_ scenePoint: CGPoint) -> Bool {
        hypot(scenePoint.x - node.position.x, scenePoint.y - (node.position.y + 127)) < 16
    }

    /// Adds or removes a light where the user clicked. Returns true if something changed.
    @discardableResult
    func toggleLight(atScenePoint p: CGPoint) -> Bool {
        let lp = CGPoint(x: p.x - node.position.x, y: p.y - node.position.y)
        if let existing = lights.children.first(where: { hypot($0.position.x - lp.x, $0.position.y - lp.y) < 7 }) {
            existing.run(.sequence([.scale(to: 0, duration: 0.12), .removeFromParent()]))
            existing.name = nil
            return true
        }
        guard tiers.contains(where: { $0.contains(lp) }) else { return false }
        addLight(at: lp, colorIndex: nextColor, animate: true)
        nextColor = (nextColor + 1) % Self.palette.count
        return true
    }

    func addLight(at p: CGPoint, colorIndex: Int, animate: Bool) {
        let idx = ((colorIndex % Self.palette.count) + Self.palette.count) % Self.palette.count
        let c = Self.palette[idx]
        let bulb = SKShapeNode(circleOfRadius: 3.6)
        bulb.fillColor = c
        bulb.strokeColor = c.withAlphaComponent(0.7)
        bulb.glowWidth = 3
        bulb.position = p
        bulb.name = String(idx)
        lights.addChild(bulb)
        if animate {
            bulb.setScale(0)
            bulb.run(.scale(to: 1, duration: 0.15))
        }
        let d = Double.random(in: 0.5...1.3)
        bulb.run(.sequence([.wait(forDuration: .random(in: 0...1.5)),
                            .repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: d),
                                                      .fadeAlpha(to: 1.0, duration: d)]))]))
    }

    var lightRecords: [[Double]] {
        lights.children.compactMap { n in
            guard let name = n.name, let idx = Int(name) else { return nil }
            return [Double(n.position.x), Double(n.position.y), Double(idx)]
        }
    }

    func restore(_ records: [[Double]]) {
        for r in records where r.count == 3 {
            addLight(at: CGPoint(x: r[0], y: r[1]), colorIndex: Int(r[2]), animate: false)
        }
        nextColor = records.count % Self.palette.count
    }

    func clearLights() { lights.removeAllChildren() }

    /// Hangs a few lights at random spots on the branches.
    func addRandomLights(_ count: Int) {
        var added = 0, tries = 0
        while added < count && tries < 200 {
            tries += 1
            let p = CGPoint(x: .random(in: -50...50), y: .random(in: 18...120))
            guard tiers.contains(where: { $0.contains(p) }) else { continue }
            addLight(at: p, colorIndex: nextColor, animate: true)
            nextColor = (nextColor + 1) % Self.palette.count
            added += 1
        }
    }
}
