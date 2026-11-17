import AppKit
import SpriteKit

/// A strip of settled snow: a row of small columns ("bins") with heights,
/// drawn as one smooth white shape. Used for the ground and for window tops.
@MainActor
final class SnowPile {
    let binWidth: CGFloat
    let maxHeight: CGFloat
    let baseHeight: CGFloat
    let taperEdges: Bool
    private(set) var width: CGFloat
    var heights: [CGFloat]
    /// Bins hidden behind a window in front are not drawn and don't catch snow.
    private(set) var visible: [Bool]
    var dirty = true
    let node = SKShapeNode()
    private let shadow = SKShapeNode()
    /// Window corners are rounded; the snow drapes down around them.
    var cornerRadius: CGFloat = 0

    /// How far below the window's top edge the surface sits at this column (the rounded corners).
    func baseline(_ b: Int) -> CGFloat {
        guard cornerRadius > 0 else { return 0 }
        let x = (CGFloat(b) + 0.5) * binWidth
        let d = min(x, width - x)
        guard d < cornerRadius else { return 0 }
        let t = cornerRadius - d
        return -(cornerRadius - (cornerRadius * cornerRadius - t * t).squareRoot())
    }

    /// Top of the snow at this column, relative to the window's top edge.
    func surfaceOffset(_ b: Int) -> CGFloat { baseline(b) + heights[b] }

    var binCount: Int { heights.count }

    init(width: CGFloat, binWidth: CGFloat, maxHeight: CGFloat, baseHeight: CGFloat, taperEdges: Bool) {
        self.width = width
        self.binWidth = binWidth
        self.maxHeight = maxHeight
        self.baseHeight = baseHeight
        self.taperEdges = taperEdges
        let n = max(1, Int(ceil(width / binWidth)))
        heights = Array(repeating: 0, count: n)
        visible = Array(repeating: true, count: n)
        node.fillColor = Art.color(0.97, 0.98, 1.0)
        node.strokeColor = Art.color(0.86, 0.90, 0.98, 0.9)
        node.lineWidth = 0.8
        node.isAntialiased = true
        shadow.fillColor = Art.color(0.45, 0.52, 0.72, 0.35)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -1.8)
        shadow.zPosition = -0.5
        node.addChild(shadow)
    }

    func resize(width newWidth: CGFloat) {
        width = newWidth
        let n = max(1, Int(ceil(newWidth / binWidth)))
        if n > heights.count {
            heights += Array(repeating: 0, count: n - heights.count)
            visible += Array(repeating: true, count: n - visible.count)
        } else if n < heights.count {
            heights.removeLast(heights.count - n)
            visible.removeLast(visible.count - n)
        }
        for b in 0..<heights.count { heights[b] = min(heights[b], cap(b)) }
        dirty = true
    }

    func bin(atLocalX x: CGFloat) -> Int? {
        let b = Int(floor(x / binWidth))
        return b >= 0 && b < heights.count ? b : nil
    }

    func isVisible(_ b: Int) -> Bool { visible[b] }

    /// Top of the snow at a local x, measured from the pile's base line.
    func surface(atLocalX x: CGFloat) -> CGFloat {
        guard let b = bin(atLocalX: x) else { return baseHeight }
        return baseHeight + heights[b]
    }

    func cap(_ b: Int) -> CGFloat {
        guard taperEdges else { return maxHeight }
        let fromEdge = CGFloat(min(b, heights.count - 1 - b)) * binWidth
        return min(maxHeight, 4 + fromEdge * 0.7)
    }

    /// Spreads each landing flake over a few neighbouring columns so piles build up evenly.
    func deposit(bin b: Int, amount: CGFloat) {
        let spread: [(Int, CGFloat)] = [(0, 0.24), (-1, 0.18), (1, 0.18), (-2, 0.11), (2, 0.11),
                                        (-3, 0.06), (3, 0.06), (-4, 0.03), (4, 0.03)]
        for (o, w) in spread {
            let i = b + o
            guard i >= 0, i < heights.count else { continue }
            heights[i] = min(cap(i), heights[i] + amount * w)
        }
        dirty = true
    }

    func clear() {
        for b in 0..<heights.count { heights[b] = 0 }
        dirty = true
    }

    func updateVisibility(_ isVisible: (CGFloat) -> Bool) {
        for b in 0..<visible.count {
            let v = isVisible((CGFloat(b) + 0.5) * binWidth)
            if v != visible[b] { visible[b] = v; dirty = true }
        }
    }

    /// Let steep spots slump into their neighbours.
    func relax(maxSlope: CGFloat) {
        guard heights.count > 1 else { return }
        var changed = false
        for b in 0..<(heights.count - 1) {
            let d = heights[b] - heights[b + 1]
            if abs(d) > maxSlope + 0.05 {
                let move = (abs(d) - maxSlope) * 0.25 * (d > 0 ? 1 : -1)
                heights[b] -= move
                heights[b + 1] += move
                changed = true
            }
        }
        if changed { dirty = true }
    }

    private func baseAt(_ x: CGFloat) -> CGFloat {
        guard cornerRadius > 0 else { return 0 }
        return baseline(min(max(Int(x / binWidth), 0), heights.count - 1))
    }

    func redrawIfNeeded() {
        guard dirty else { return }
        dirty = false
        let path = CGMutablePath()
        var run: [CGPoint] = []

        func flush() {
            defer { run.removeAll(keepingCapacity: true) }
            guard let first = run.first, let last = run.last else { return }
            let x0 = max(0, first.x - binWidth / 2)
            let x1 = min(width, last.x + binWidth / 2)
            let b0 = baseAt(x0), b1 = baseAt(x1)
            path.move(to: CGPoint(x: x0, y: b0))
            path.addQuadCurve(to: CGPoint(x: first.x, y: first.y), control: CGPoint(x: x0, y: first.y))
            for j in run.indices.dropFirst() {
                let a = run[j - 1], b = run[j]
                path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            }
            path.addLine(to: last)
            path.addQuadCurve(to: CGPoint(x: x1, y: b1), control: CGPoint(x: x1, y: last.y))
            // back along the window's (rounded) top edge
            var x = x1
            while x > x0 {
                path.addLine(to: CGPoint(x: x, y: baseAt(x)))
                x -= binWidth
            }
            path.addLine(to: CGPoint(x: x0, y: b0))
            path.closeSubpath()
        }

        // Draw a softened outline (average of neighbours) for a clean, rounded look.
        let n = heights.count
        for b in 0..<n {
            var sum: CGFloat = 0, count: CGFloat = 0
            for i in max(0, b - 4)...min(n - 1, b + 4) { sum += heights[i]; count += 1 }
            let h = visible[b] ? baseHeight + sum / count : 0
            if h > 0.3 {
                run.append(CGPoint(x: (CGFloat(b) + 0.5) * binWidth, y: baseline(b) + h))
            } else {
                flush()
            }
        }
        flush()
        node.path = path.isEmpty ? nil : path
        shadow.path = node.path
    }
}
