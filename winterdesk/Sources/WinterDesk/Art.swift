import AppKit
import SpriteKit

/// Small drawing helpers shared by the train, tree and trams.
@MainActor
enum Art {
    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func box(_ rect: CGRect, _ fill: NSColor, radius: CGFloat = 2, outline: Bool = true) -> SKShapeNode {
        let s = SKShapeNode(rect: rect, cornerRadius: radius)
        s.fillColor = fill
        s.strokeColor = outline ? (fill.blended(withFraction: 0.4, of: .black) ?? fill) : .clear
        s.lineWidth = outline ? 1 : 0
        return s
    }

    static func circle(_ center: CGPoint, _ r: CGFloat, _ fill: NSColor, outline: Bool = true) -> SKShapeNode {
        let s = SKShapeNode(circleOfRadius: r)
        s.position = center
        s.fillColor = fill
        s.strokeColor = outline ? (fill.blended(withFraction: 0.4, of: .black) ?? fill) : .clear
        s.lineWidth = outline ? 1 : 0
        return s
    }

    static func polygonPath(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts)
        p.closeSubpath()
        return p
    }

    static func polygon(_ pts: [CGPoint], _ fill: NSColor, outline: Bool = true) -> SKShapeNode {
        let s = SKShapeNode(path: polygonPath(pts))
        s.fillColor = fill
        s.strokeColor = outline ? (fill.blended(withFraction: 0.4, of: .black) ?? fill) : .clear
        s.lineWidth = outline ? 1 : 0
        return s
    }

    static func heartPath(size s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -s * 0.9))
        p.addCurve(to: CGPoint(x: 0, y: s * 0.35), control1: CGPoint(x: s * 1.3, y: -s * 0.1),
                   control2: CGPoint(x: s * 0.6, y: s * 1.1))
        p.addCurve(to: CGPoint(x: 0, y: -s * 0.9), control1: CGPoint(x: -s * 0.6, y: s * 1.1),
                   control2: CGPoint(x: -s * 1.3, y: -s * 0.1))
        p.closeSubpath()
        return p
    }

    static func ellipse(_ rect: CGRect, _ fill: NSColor, outline: Bool = true) -> SKShapeNode {
        let s = SKShapeNode(ellipseIn: rect)
        s.fillColor = fill
        s.strokeColor = outline ? (fill.blended(withFraction: 0.25, of: .black) ?? fill) : .clear
        s.lineWidth = outline ? 1 : 0
        return s
    }

    static func line(_ pts: [CGPoint], _ color: NSColor, width: CGFloat = 1) -> SKShapeNode {
        let p = CGMutablePath()
        p.addLines(between: pts)
        let s = SKShapeNode(path: p)
        s.strokeColor = color
        s.lineWidth = width
        return s
    }

    static func starPath(radius r: CGFloat, inner: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let rr = i % 2 == 0 ? r : inner
            let pt = CGPoint(x: cos(angle) * rr, y: sin(angle) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Textures drawn in code, so the app ships with no image files.
@MainActor
enum Textures {
    static func image(_ size: CGSize, _ draw: @escaping (CGContext, CGRect) -> Void) -> SKTexture {
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, rect)
            return true
        }
        return SKTexture(image: img)
    }

    private static func radial(_ colors: [NSColor], _ locations: [CGFloat], size: CGFloat = 64) -> SKTexture {
        image(CGSize(width: size, height: size)) { ctx, rect in
            let cg = colors.map(\.cgColor) as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cg, locations: locations) else { return }
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width / 2, options: [])
        }
    }

    /// A crisp-ish round snowflake.
    static let flake: SKTexture = radial(
        [.white, NSColor.white.withAlphaComponent(0.9), NSColor.white.withAlphaComponent(0)],
        [0, 0.4, 1])

    /// A very soft dot for bokeh, glow and smoke.
    static let softDot: SKTexture = radial(
        [NSColor.white.withAlphaComponent(0.9), NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)],
        [0, 0.45, 1])

    static let vignette: SKTexture = image(CGSize(width: 256, height: 256)) { ctx, rect in
        let colors = [NSColor.black.withAlphaComponent(0).cgColor,
                      NSColor.black.withAlphaComponent(0.08).cgColor,
                      NSColor.black.withAlphaComponent(0.55).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                               endRadius: rect.width * 0.72, options: [.drawsAfterEndLocation])
    }

    static func verticalGradient(bottom: NSColor, top: NSColor) -> SKTexture {
        image(CGSize(width: 4, height: 256)) { _, rect in
            NSGradient(starting: bottom, ending: top)?.draw(in: rect, angle: 90)
        }
    }
}
