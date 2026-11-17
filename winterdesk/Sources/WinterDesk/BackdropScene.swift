import AppKit
import SpriteKit

/// Sits just above the wallpaper (below every window and the desktop icons).
/// Either dims your own wallpaper into a winter night, or replaces it with a scene.
@MainActor
final class BackdropScene: SKScene {
    let theme: Backdrop
    private var W: CGFloat { size.width }
    private var H: CGFloat { size.height }
    private var aurora: [(sprite: SKSpriteNode, band: Int, i: Int, baseY: CGFloat, baseAlpha: CGFloat)] = []
    private var clock: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    init(size: CGSize, theme: Backdrop) {
        self.theme = theme
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        switch theme {
        case .off, .dim: buildDim()
        case .cabin: if !buildPainted("cabin") { buildVillage() }
        case .fireplace: if !buildPainted("fireplace") { buildFireplace() }
        case .village: if !buildPainted("village") { buildVillage() }
        case .aurora: if !buildPainted("aurora") { buildAurora() }
        }
    }

    // MARK: - Painted backgrounds (pictures shipped inside the app, with animated touches on top)

    /// Where the picture sits on screen (it fills the screen, cropping the overflow).
    private var picture = CGRect.zero
    private var pictureScale: CGFloat { picture.width / 2560 }

    /// Converts a position in the picture (0...1 from its top-left) to scene coordinates.
    private func at(_ u: Double, _ v: Double) -> CGPoint {
        CGPoint(x: picture.minX + CGFloat(u) * picture.width, y: picture.maxY - CGFloat(v) * picture.height)
    }

    private func buildPainted(_ name: String) -> Bool {
        guard let url = Bundle.main.url(forResource: "bg-\(name)", withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else { return false }
        let rep = image.representations.first
        let pw = CGFloat(rep?.pixelsWide ?? Int(image.size.width))
        let ph = CGFloat(rep?.pixelsHigh ?? Int(image.size.height))
        guard pw > 0, ph > 0 else { return false }
        let scale = max(W / pw, H / ph)
        let size = CGSize(width: pw * scale, height: ph * scale)
        picture = CGRect(x: (W - size.width) / 2, y: (H - size.height) / 2, width: size.width, height: size.height)
        let sprite = SKSpriteNode(texture: SKTexture(image: image), size: size)
        sprite.position = CGPoint(x: W / 2, y: H / 2)
        add(sprite, z: 0)

        var feats: [String: Any] = [:]
        if let jurl = Bundle.main.url(forResource: "bg-\(name)", withExtension: "json"),
           let data = try? Data(contentsOf: jurl),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            feats = obj
        }
        let k = pictureScale

        // Twinkling stars in the sky
        if name != "fireplace" {
            for _ in 0..<70 {
                let p = at(.random(in: 0...1), .random(in: 0...0.42))
                let g = glow(p, diameter: .random(in: 3...7) * max(k, 0.6), color: .white, alpha: 0.0, z: 1)
                g.run(.sequence([.wait(forDuration: .random(in: 0...6)),
                                 .repeatForever(.sequence([.fadeAlpha(to: .random(in: 0.5...0.9), duration: .random(in: 0.4...1.2)),
                                                           .fadeAlpha(to: 0, duration: .random(in: 0.6...1.5)),
                                                           .wait(forDuration: .random(in: 1...6))]))]))
            }
        }
        // Little lights (eaves, garland, the village tree) twinkle
        for l in feats["lights"] as? [[Double]] ?? [] where l.count >= 2 {
            let warm = name == "cabin" || name == "fireplace"
            let c = warm ? Art.color(1, .random(in: 0.75...0.9), .random(in: 0.4...0.55))
                         : ChristmasTree.palette.randomElement() ?? .white
            let g = glow(at(l[0], l[1]), diameter: 26 * max(k, 0.5), color: c, alpha: 0.7, z: 2)
            g.blendMode = .add
            pulse(g, from: 0.75, to: 0.25, period: 0.5...1.6)
        }
        // Warm windows and lanterns breathe a little
        for gl in feats["glows"] as? [[Double]] ?? [] where gl.count >= 3 {
            let g = glow(at(gl[0], gl[1]), diameter: CGFloat(gl[2]) * picture.width * 1.6,
                         color: Art.color(1, 0.62, 0.25), alpha: 0.16, z: 2)
            g.blendMode = .add
            g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.10, duration: .random(in: 0.8...1.6)),
                                            .fadeAlpha(to: 0.18, duration: .random(in: 0.8...1.6))])))
        }
        // Chimney smoke
        for sm in feats["smoke"] as? [[Double]] ?? [] where sm.count >= 2 {
            let e = SKEmitterNode()
            e.particleTexture = Textures.softDot
            e.particleBirthRate = 3
            e.particleLifetime = 6
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = 0.2
            e.particleSpeed = 24 * max(k, 0.6)
            e.xAcceleration = -3
            e.particleScale = 0.35 * max(k, 0.6)
            e.particleScaleSpeed = 0.16
            e.particleAlpha = 0.28
            e.particleAlphaSpeed = -0.045
            e.particleColor = Art.color(0.8, 0.8, 0.92)
            e.particleColorBlendFactor = 1
            e.position = at(sm[0], sm[1])
            e.advanceSimulationTime(6)
            add(e, z: 3)
        }
        // Fireplace: flames, embers and flickering firelight
        if let f = feats["fire"] as? [Double], f.count >= 3 {
            let base = at(f[0], f[1])
            let ow = CGFloat(f[2]) * picture.width
            let s = ow / 64
            let fire = SKEmitterNode()
            fire.particleTexture = Textures.softDot
            fire.particleBirthRate = 170
            fire.particleLifetime = 0.9
            fire.particleLifetimeRange = 0.35
            fire.particlePositionRange = CGVector(dx: ow * 0.5, dy: 4)
            fire.emissionAngle = .pi / 2
            fire.emissionAngleRange = 0.28
            fire.particleSpeed = ow * 0.22
            fire.particleSpeedRange = ow * 0.1
            fire.yAcceleration = ow * 0.12
            fire.particleScale = s * 0.2
            fire.particleScaleRange = s * 0.07
            fire.particleScaleSpeed = -s * 0.18
            fire.particleAlpha = 0.9
            fire.particleAlphaSpeed = -0.9
            fire.particleColorBlendFactor = 1
            fire.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [Art.color(1, 0.95, 0.7), Art.color(1, 0.65, 0.15), Art.color(0.95, 0.25, 0.05), Art.color(0.4, 0.05, 0.02)],
                times: [0, 0.25, 0.6, 1])
            fire.particleBlendMode = .add
            fire.position = base
            add(fire, z: 4)
            let embers = SKEmitterNode()
            embers.particleTexture = Textures.flake
            embers.particleBirthRate = 7
            embers.particleLifetime = 2.2
            embers.particlePositionRange = CGVector(dx: ow * 0.4, dy: 4)
            embers.emissionAngle = .pi / 2
            embers.emissionAngleRange = 0.7
            embers.particleSpeed = ow * 0.35
            embers.particleSpeedRange = ow * 0.15
            embers.particleScale = 0.08 * max(k, 0.6)
            embers.particleAlphaSpeed = -0.45
            embers.particleColor = Art.color(1, 0.6, 0.2)
            embers.particleColorBlendFactor = 1
            embers.particleBlendMode = .add
            embers.position = CGPoint(x: base.x, y: base.y + 10)
            add(embers, z: 4.1)
            let room = glow(CGPoint(x: base.x, y: base.y + ow * 0.3), diameter: W * 1.1, color: Art.color(1, 0.55, 0.2), alpha: 0.12, z: 5)
            room.blendMode = .add
            room.run(.repeatForever(.sequence([.fadeAlpha(to: 0.08, duration: 0.3), .fadeAlpha(to: 0.14, duration: 0.4),
                                               .fadeAlpha(to: 0.10, duration: 0.2), .fadeAlpha(to: 0.13, duration: 0.35)])))
        }
        for c in feats["candles"] as? [[Double]] ?? [] where c.count >= 2 {
            let p = at(c[0], c[1])
            let flame = glow(p, diameter: 16 * max(k, 0.6), color: Art.color(1, 0.85, 0.5), alpha: 1, z: 4)
            flame.yScale = 1.7
            flame.run(.repeatForever(.sequence([.scaleX(to: 0.8, duration: 0.15), .scaleX(to: 1.1, duration: 0.2)])))
            let halo = glow(p, diameter: 80 * max(k, 0.6), color: Art.color(1, 0.7, 0.3), alpha: 0.3, z: 3.9)
            halo.blendMode = .add
            pulse(halo, from: 0.3, to: 0.18, period: 0.15...0.35)
        }
        // Northern lights: soft shimmer moving over the painted curtains
        for (bi, band) in (feats["bands"] as? [[String: Any]] ?? []).enumerated() {
            guard let base = band["base"] as? Double, let amp = band["amp"] as? Double, let wl = band["wl"] as? Double,
                  let seed = band["seed"] as? Double, let height = band["height"] as? Double,
                  let c0 = band["c0"] as? [Double], c0.count == 3 else { continue }
            let columns = 40
            for i in 0..<columns {
                let u = Double(i) / Double(columns - 1)
                let xpx = u * 2560
                let v = base + amp * sin(xpx / (wl * 2560) + seed) + amp * 0.4 * sin(xpx / (wl * 0.37 * 2560) + seed * 2)
                let p = at(u, v - height * 0.35)
                let sprite = SKSpriteNode(texture: Textures.softDot,
                                          size: CGSize(width: picture.width / CGFloat(columns) * 2.6, height: CGFloat(height) * picture.height * 0.9))
                sprite.color = Art.color(CGFloat(c0[0]), CGFloat(c0[1]), CGFloat(c0[2]))
                sprite.colorBlendFactor = 1
                sprite.blendMode = .add
                sprite.alpha = 0.1
                sprite.position = p
                add(sprite, z: 1.5)
                aurora.append((sprite, bi, i, p.y, 0.12))
            }
        }
        return true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Helpers

    private func gradient(_ rect: CGRect, bottom: NSColor, top: NSColor, z: CGFloat = 0) {
        let s = SKSpriteNode(texture: Textures.verticalGradient(bottom: bottom, top: top), size: rect.size)
        s.anchorPoint = .zero
        s.position = rect.origin
        s.zPosition = z
        addChild(s)
    }

    @discardableResult
    private func glow(_ p: CGPoint, diameter: CGFloat, color: NSColor, alpha: CGFloat, z: CGFloat,
                      parent: SKNode? = nil) -> SKSpriteNode {
        let s = SKSpriteNode(texture: Textures.softDot, size: CGSize(width: diameter, height: diameter))
        s.position = p
        s.color = color
        s.colorBlendFactor = 1
        s.alpha = alpha
        s.zPosition = z
        (parent ?? self).addChild(s)
        return s
    }

    private func pulse(_ n: SKNode, from a: CGFloat, to b: CGFloat, period: ClosedRange<Double>) {
        let t = Double.random(in: period)
        n.run(.repeatForever(.sequence([.fadeAlpha(to: b, duration: t), .fadeAlpha(to: a, duration: t)])))
    }

    @discardableResult
    private func add(_ n: SKNode, z: CGFloat) -> SKNode {
        n.zPosition = z
        addChild(n)
        return n
    }

    private func stars(count: Int, minY: CGFloat, z: CGFloat) {
        for _ in 0..<count {
            let r = CGFloat.random(in: 0.6...1.6)
            let s = Art.circle(CGPoint(x: .random(in: 0...W), y: .random(in: minY...H)), r,
                               Art.color(1, 1, 0.95), outline: false)
            s.alpha = .random(in: 0.4...0.95)
            add(s, z: z)
            if Bool.random() { pulse(s, from: s.alpha, to: 0.2, period: 1.0...3.0) }
        }
    }

    /// A wavy filled band from the bottom of the screen up to about `baseY`.
    private func hill(baseY: CGFloat, amp: CGFloat, waves: CGFloat, phase: CGFloat, color: NSColor, z: CGFloat) {
        let p = CGMutablePath()
        p.move(to: .zero)
        var x: CGFloat = 0
        while x <= W + 20 {
            let y = baseY + amp * sin(x / W * waves * 2 * .pi + phase) + amp * 0.4 * sin(x / W * waves * 5.3 + phase * 2)
            p.addLine(to: CGPoint(x: x, y: y))
            x += 16
        }
        p.addLine(to: CGPoint(x: W + 20, y: 0))
        p.closeSubpath()
        let s = SKShapeNode(path: p)
        s.fillColor = color
        s.strokeColor = .clear
        add(s, z: z)
    }

    private func pine(at p: CGPoint, height h: CGFloat, color: NSColor, snow: Bool, z: CGFloat) {
        let n = SKNode()
        n.position = p
        n.addChild(Art.box(CGRect(x: -h * 0.04, y: 0, width: h * 0.08, height: h * 0.15),
                           Art.color(0.18, 0.11, 0.07), radius: 1, outline: false))
        for i in 0..<3 {
            let base = h * (0.1 + CGFloat(i) * 0.25)
            let half = h * (0.32 - CGFloat(i) * 0.08)
            n.addChild(Art.polygon([CGPoint(x: -half, y: base), CGPoint(x: half, y: base),
                                    CGPoint(x: 0, y: base + h * 0.42)], color, outline: false))
            if snow {
                n.addChild(Art.polygon([CGPoint(x: -half * 0.45, y: base + h * 0.23), CGPoint(x: half * 0.45, y: base + h * 0.23),
                                        CGPoint(x: 0, y: base + h * 0.42)], Art.color(0.93, 0.95, 1.0), outline: false))
            }
        }
        add(n, z: z)
    }

    /// A drooping string of twinkling coloured bulbs.
    private func stringLights(from a: CGPoint, to b: CGPoint, sag: CGFloat, bulbs: Int, z: CGFloat) {
        let c = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - sag)
        let wire = CGMutablePath()
        wire.move(to: a)
        wire.addQuadCurve(to: b, control: c)
        let w = SKShapeNode(path: wire)
        w.strokeColor = Art.color(0.1, 0.12, 0.1, 0.9)
        w.lineWidth = 1.2
        add(w, z: z)
        for k in 1..<bulbs {
            let t = CGFloat(k) / CGFloat(bulbs)
            let u = 1 - t
            let p = CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                            y: u * u * a.y + 2 * u * t * c.y + t * t * b.y - 3)
            let col = ChristmasTree.palette[k % ChristmasTree.palette.count]
            let g = glow(p, diameter: 22, color: col, alpha: 0.45, z: z)
            let bulb = Art.circle(p, 2.6, col, outline: false)
            add(bulb, z: z + 0.1)
            pulse(g, from: 0.5, to: 0.15, period: 0.6...1.6)
        }
    }

    // MARK: - Dimmed wallpaper

    private func buildDim() {
        gradient(CGRect(origin: .zero, size: size),
                 bottom: Art.color(0.06, 0.05, 0.12, 0.42), top: Art.color(0.02, 0.03, 0.10, 0.62))
        let vignette = SKSpriteNode(texture: Textures.vignette, size: size)
        vignette.anchorPoint = .zero
        add(vignette, z: 1)
        glow(CGPoint(x: W * 0.82, y: H * 0.84), diameter: 460, color: Art.color(0.75, 0.82, 1.0), alpha: 0.10, z: 2)
        for _ in 0..<18 {
            let base = CGFloat.random(in: 0.12...0.32)
            let g = glow(CGPoint(x: .random(in: 0...W), y: H * .random(in: 0.04...0.32)),
                         diameter: .random(in: 18...70),
                         color: Art.color(1.0, .random(in: 0.68...0.85), .random(in: 0.30...0.45)), alpha: base, z: 3)
            pulse(g, from: base, to: base * 0.45, period: 2...5)
        }
    }

    // MARK: - Cozy fireplace

    private func buildFireplace() {
        let floorH = H * 0.17
        // Wall and wallpaper stripes
        gradient(CGRect(x: 0, y: floorH, width: W, height: H - floorH),
                 bottom: Art.color(0.24, 0.09, 0.07), top: Art.color(0.09, 0.04, 0.04))
        for x in stride(from: CGFloat(0), to: W, by: 70) {
            add(Art.box(CGRect(x: x, y: floorH, width: 26, height: H - floorH), Art.color(1, 0.85, 0.7, 0.035),
                        radius: 0, outline: false), z: 0.5)
        }
        // Wooden floor with planks and a rug
        gradient(CGRect(x: 0, y: 0, width: W, height: floorH),
                 bottom: Art.color(0.16, 0.09, 0.05), top: Art.color(0.30, 0.17, 0.09), z: 1)
        for y in stride(from: CGFloat(12), to: floorH, by: 16) {
            add(Art.box(CGRect(x: 0, y: y, width: W, height: 1.2), Art.color(0, 0, 0, 0.25), radius: 0, outline: false), z: 1.1)
        }
        add(Art.box(CGRect(x: 0, y: floorH - 4, width: W, height: 8), Art.color(0.20, 0.10, 0.06), radius: 0, outline: false), z: 1.2)
        let rug = Art.ellipse(CGRect(x: W * 0.28, y: floorH * 0.08, width: W * 0.44, height: floorH * 0.62),
                              Art.color(0.50, 0.09, 0.12))
        rug.strokeColor = Art.color(0.85, 0.65, 0.3)
        rug.lineWidth = 4
        add(rug, z: 1.3)

        // Brick fireplace
        let fw = min(W * 0.44, 780), fh = fw * 0.6
        let fx = W / 2 - fw / 2, fy = floorH - 4
        let bricks = Textures.image(CGSize(width: fw, height: fh)) { ctx, rect in
            ctx.setFillColor(Art.color(0.30, 0.24, 0.22).cgColor)
            ctx.fill(rect)
            let bw: CGFloat = 44, bh: CGFloat = 18
            var row = 0
            var y: CGFloat = 0
            while y < rect.height {
                var x: CGFloat = row % 2 == 0 ? 0 : -bw / 2
                var col = 0
                while x < rect.width {
                    let v = CGFloat((row * 7 + col * 13) % 5) * 0.03
                    ctx.setFillColor(Art.color(0.55 + v, 0.24 + v * 0.5, 0.18 + v * 0.3).cgColor)
                    ctx.fill(CGRect(x: x + 1.5, y: y + 1.5, width: bw - 3, height: bh - 3))
                    x += bw
                    col += 1
                }
                y += bh
                row += 1
            }
        }
        let surround = SKSpriteNode(texture: bricks, size: CGSize(width: fw, height: fh))
        surround.anchorPoint = .zero
        surround.position = CGPoint(x: fx, y: fy)
        add(surround, z: 2)

        // Firebox opening (arched)
        let ow = fw * 0.56, oh = fh * 0.6
        let ox = W / 2 - ow / 2, oy = fy + fh * 0.07
        let opening = CGMutablePath()
        opening.move(to: CGPoint(x: ox, y: oy))
        opening.addLine(to: CGPoint(x: ox, y: oy + oh - ow / 2 * 0.5))
        opening.addQuadCurve(to: CGPoint(x: ox + ow, y: oy + oh - ow / 2 * 0.5), control: CGPoint(x: W / 2, y: oy + oh + ow * 0.2))
        opening.addLine(to: CGPoint(x: ox + ow, y: oy))
        opening.closeSubpath()
        let box = SKShapeNode(path: opening)
        box.fillColor = Art.color(0.05, 0.03, 0.03)
        box.strokeColor = Art.color(0.22, 0.18, 0.17)
        box.lineWidth = 6
        add(box, z: 3)
        let inner = glow(CGPoint(x: W / 2, y: oy + oh * 0.3), diameter: ow * 1.1, color: Art.color(1, 0.45, 0.1), alpha: 0.45, z: 3.2)
        inner.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.18), .fadeAlpha(to: 0.5, duration: 0.25),
                                            .fadeAlpha(to: 0.38, duration: 0.15), .fadeAlpha(to: 0.48, duration: 0.3)])))

        // Logs
        let wood = Art.color(0.33, 0.19, 0.10)
        let log1 = Art.box(CGRect(x: -ow * 0.3, y: -7, width: ow * 0.6, height: 14), wood, radius: 7)
        log1.position = CGPoint(x: W / 2, y: oy + 14)
        log1.zRotation = 0.12
        add(log1, z: 3.5)
        let log2 = Art.box(CGRect(x: -ow * 0.3, y: -7, width: ow * 0.6, height: 14), wood.blended(withFraction: 0.15, of: .black)!, radius: 7)
        log2.position = CGPoint(x: W / 2, y: oy + 14)
        log2.zRotation = -0.12
        add(log2, z: 3.4)

        // Flames and embers
        let s = ow / 64
        let fire = SKEmitterNode()
        fire.particleTexture = Textures.softDot
        fire.particleBirthRate = 150
        fire.particleLifetime = 1.0
        fire.particleLifetimeRange = 0.4
        fire.particlePositionRange = CGVector(dx: ow * 0.42, dy: 6)
        fire.emissionAngle = .pi / 2
        fire.emissionAngleRange = 0.3
        fire.particleSpeed = oh * 0.22
        fire.particleSpeedRange = oh * 0.1
        fire.yAcceleration = oh * 0.15
        fire.particleScale = s * 0.17
        fire.particleScaleRange = s * 0.06
        fire.particleScaleSpeed = -s * 0.14
        fire.particleAlpha = 0.9
        fire.particleAlphaSpeed = -0.85
        fire.particleColorBlendFactor = 1
        fire.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [Art.color(1, 0.95, 0.7), Art.color(1, 0.65, 0.15), Art.color(0.95, 0.25, 0.05), Art.color(0.4, 0.05, 0.02)],
            times: [0, 0.25, 0.6, 1])
        fire.particleBlendMode = .add
        fire.position = CGPoint(x: W / 2, y: oy + 22)
        add(fire, z: 3.6)

        let embers = SKEmitterNode()
        embers.particleTexture = Textures.flake
        embers.particleBirthRate = 7
        embers.particleLifetime = 2.4
        embers.particlePositionRange = CGVector(dx: ow * 0.35, dy: 4)
        embers.emissionAngle = .pi / 2
        embers.emissionAngleRange = 0.7
        embers.particleSpeed = oh * 0.45
        embers.particleSpeedRange = oh * 0.2
        embers.particleScale = 0.06
        embers.particleAlphaSpeed = -0.4
        embers.particleColor = Art.color(1, 0.6, 0.2)
        embers.particleColorBlendFactor = 1
        embers.particleBlendMode = .add
        embers.position = CGPoint(x: W / 2, y: oy + 30)
        add(embers, z: 3.7)

        // Hearth and mantel
        add(Art.box(CGRect(x: fx - 24, y: fy - 8, width: fw + 48, height: 16), Art.color(0.42, 0.38, 0.36), radius: 3), z: 4)
        add(Art.box(CGRect(x: fx - 34, y: fy + fh, width: fw + 68, height: 22), Art.color(0.36, 0.20, 0.10), radius: 4), z: 4)
        add(Art.box(CGRect(x: fx - 26, y: fy + fh - 8, width: fw + 52, height: 9), Art.color(0.28, 0.15, 0.08), radius: 2), z: 4)

        // Garland along the mantel with lights
        let my = fy + fh + 2
        var x = fx - 28
        var k = 0
        while x < fx + fw + 28 {
            add(Art.circle(CGPoint(x: x, y: my + 2 * sin(x * 0.2)), 7, Art.color(0.10, 0.36, 0.18), outline: false), z: 4.5)
            if k % 2 == 0 {
                let col = ChristmasTree.palette[(k / 2) % ChristmasTree.palette.count]
                let p = CGPoint(x: x, y: my - 3)
                pulse(glow(p, diameter: 20, color: col, alpha: 0.5, z: 4.6), from: 0.5, to: 0.15, period: 0.6...1.6)
                add(Art.circle(p, 2.6, col, outline: false), z: 4.7)
            }
            x += 9
            k += 1
        }

        // Stockings hanging from the mantel
        let stockingColors = [Art.color(0.80, 0.12, 0.15), Art.color(0.15, 0.45, 0.25), Art.color(0.80, 0.12, 0.15)]
        for (i, c) in stockingColors.enumerated() {
            let sx = fx + fw * (0.22 + CGFloat(i) * 0.28)
            let top = fy + fh - 10
            let sock = Art.polygon([CGPoint(x: sx - 10, y: top), CGPoint(x: sx + 10, y: top), CGPoint(x: sx + 10, y: top - 42),
                                    CGPoint(x: sx + 24, y: top - 50), CGPoint(x: sx + 22, y: top - 62),
                                    CGPoint(x: sx - 6, y: top - 60), CGPoint(x: sx - 10, y: top - 50)], c)
            add(sock, z: 5)
            add(Art.box(CGRect(x: sx - 12, y: top - 10, width: 24, height: 12), Art.color(0.97, 0.97, 0.97), radius: 4), z: 5.1)
        }

        // Candles on the mantel
        for dx in [-0.38, -0.31, 0.33] as [CGFloat] {
            let cx = W / 2 + fw * dx
            let ch: CGFloat = dx == -0.31 ? 26 : 38
            add(Art.box(CGRect(x: cx - 6, y: fy + fh + 22, width: 12, height: ch), Art.color(0.96, 0.92, 0.82), radius: 2), z: 4.8)
            let flameP = CGPoint(x: cx, y: fy + fh + 22 + ch + 7)
            let halo = glow(flameP, diameter: 70, color: Art.color(1, 0.7, 0.3), alpha: 0.35, z: 4.85)
            pulse(halo, from: 0.35, to: 0.22, period: 0.2...0.4)
            let flame = glow(flameP, diameter: 14, color: Art.color(1, 0.85, 0.5), alpha: 1, z: 4.9)
            flame.yScale = 1.6
        }

        // Warm firelight across the room
        let room = glow(CGPoint(x: W / 2, y: oy + oh * 0.5), diameter: W * 1.1, color: Art.color(1, 0.55, 0.2), alpha: 0.16, z: 6)
        room.blendMode = .add
        room.run(.repeatForever(.sequence([.fadeAlpha(to: 0.12, duration: 0.3), .fadeAlpha(to: 0.18, duration: 0.4),
                                           .fadeAlpha(to: 0.14, duration: 0.2), .fadeAlpha(to: 0.17, duration: 0.35)])))
        let vignette = SKSpriteNode(texture: Textures.vignette, size: size)
        vignette.anchorPoint = .zero
        add(vignette, z: 7)
    }

    // MARK: - Winter village with lights

    private func buildVillage() {
        gradient(CGRect(origin: .zero, size: size), bottom: Art.color(0.14, 0.17, 0.34), top: Art.color(0.02, 0.04, 0.13))
        stars(count: 140, minY: H * 0.45, z: 0.5)
        glow(CGPoint(x: W * 0.8, y: H * 0.8), diameter: 280, color: Art.color(0.85, 0.9, 1), alpha: 0.25, z: 0.6)
        add(Art.circle(CGPoint(x: W * 0.8, y: H * 0.8), 38, Art.color(0.97, 0.96, 0.88), outline: false), z: 0.7)

        hill(baseY: H * 0.34, amp: H * 0.04, waves: 1.3, phase: 0.6, color: Art.color(0.42, 0.50, 0.68), z: 1)
        for i in 0..<28 {
            let x = W * CGFloat(i) / 27 + .random(in: -15...15)
            pine(at: CGPoint(x: x, y: H * 0.30 + .random(in: -8...14)), height: .random(in: 30...55),
                 color: Art.color(0.10, 0.16, 0.26), snow: false, z: 1.1)
        }
        hill(baseY: H * 0.25, amp: H * 0.03, waves: 0.9, phase: 2.1, color: Art.color(0.70, 0.77, 0.92), z: 2)
        hill(baseY: H * 0.15, amp: H * 0.02, waves: 0.7, phase: 4.0, color: Art.color(0.92, 0.94, 1.0), z: 4)

        // Two tall pines with a string of lights between them
        let leftTree = CGPoint(x: W * 0.12, y: H * 0.13)
        let rightTree = CGPoint(x: W * 0.46, y: H * 0.14)
        pine(at: leftTree, height: H * 0.42, color: Art.color(0.07, 0.24, 0.16), snow: true, z: 5)
        pine(at: rightTree, height: H * 0.36, color: Art.color(0.07, 0.24, 0.16), snow: true, z: 5)
        stringLights(from: CGPoint(x: leftTree.x + 10, y: leftTree.y + H * 0.30),
                     to: CGPoint(x: rightTree.x - 10, y: rightTree.y + H * 0.25), sag: H * 0.08, bulbs: 22, z: 5.5)

        // A little cabin with glowing windows and lights on the roof
        let cw = min(W * 0.16, 280), chh = cw * 0.55
        let cx = W * 0.68, cy = H * 0.15
        add(Art.box(CGRect(x: cx - cw * 0.3, y: cy + chh, width: cw * 0.1, height: chh * 0.7), Art.color(0.35, 0.2, 0.15), radius: 1), z: 5.9)
        add(Art.box(CGRect(x: cx - cw / 2, y: cy, width: cw, height: chh), Art.color(0.42, 0.24, 0.13), radius: 2), z: 6)
        for y in stride(from: cy + 8, to: cy + chh, by: 10) {
            add(Art.box(CGRect(x: cx - cw / 2, y: y, width: cw, height: 1.2), Art.color(0, 0, 0, 0.25), radius: 0, outline: false), z: 6.05)
        }
        let roof = [CGPoint(x: cx - cw * 0.6, y: cy + chh), CGPoint(x: cx + cw * 0.6, y: cy + chh), CGPoint(x: cx, y: cy + chh + cw * 0.38)]
        add(Art.polygon(roof, Art.color(0.25, 0.12, 0.10)), z: 6.1)
        add(Art.polygon([CGPoint(x: cx - cw * 0.62, y: cy + chh - 2), CGPoint(x: cx + cw * 0.62, y: cy + chh - 2),
                         CGPoint(x: cx + cw * 0.5, y: cy + chh + 8), CGPoint(x: cx, y: cy + chh + cw * 0.42),
                         CGPoint(x: cx - cw * 0.5, y: cy + chh + 8)], Art.color(0.95, 0.97, 1.0), outline: false), z: 6.2)
        for wx in [cx - cw * 0.3, cx + cw * 0.3] {
            let wr = CGRect(x: wx - cw * 0.09, y: cy + chh * 0.35, width: cw * 0.18, height: chh * 0.36)
            glow(CGPoint(x: wr.midX, y: wr.midY), diameter: cw * 0.6, color: Art.color(1, 0.7, 0.3), alpha: 0.4, z: 6.3)
            add(Art.box(wr, Art.color(1, 0.82, 0.45), radius: 2), z: 6.4)
            add(Art.box(CGRect(x: wr.midX - 1, y: wr.minY, width: 2, height: wr.height), Art.color(0.3, 0.17, 0.1), radius: 0, outline: false), z: 6.5)
        }
        add(Art.box(CGRect(x: cx - cw * 0.07, y: cy, width: cw * 0.14, height: chh * 0.6), Art.color(0.28, 0.14, 0.08), radius: 2), z: 6.4)
        stringLights(from: roof[0], to: roof[2], sag: 4, bulbs: 9, z: 6.6)
        stringLights(from: roof[2], to: roof[1], sag: 4, bulbs: 9, z: 6.6)

        // Chimney smoke
        let smoke = SKEmitterNode()
        smoke.particleTexture = Textures.softDot
        smoke.particleBirthRate = 3
        smoke.particleLifetime = 5
        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = 0.2
        smoke.particleSpeed = 22
        smoke.xAcceleration = -3
        smoke.particleScale = 0.25
        smoke.particleScaleSpeed = 0.18
        smoke.particleAlpha = 0.35
        smoke.particleAlphaSpeed = -0.07
        smoke.particleColor = Art.color(0.8, 0.82, 0.9)
        smoke.particleColorBlendFactor = 1
        smoke.position = CGPoint(x: cx - cw * 0.25, y: cy + chh * 1.7)
        smoke.advanceSimulationTime(5)
        add(smoke, z: 5.8)

        // Lamp post
        let lx = W * 0.32, ly = H * 0.12
        add(Art.box(CGRect(x: lx - 2.5, y: ly, width: 5, height: H * 0.16), Art.color(0.12, 0.12, 0.15), radius: 1), z: 7)
        let lampP = CGPoint(x: lx, y: ly + H * 0.16 + 8)
        add(Art.box(CGRect(x: lx - 8, y: lampP.y - 8, width: 16, height: 16), Art.color(1, 0.85, 0.55), radius: 3), z: 7.1)
        let halo = glow(lampP, diameter: 160, color: Art.color(1, 0.75, 0.4), alpha: 0.45, z: 7.2)
        pulse(halo, from: 0.45, to: 0.35, period: 1.5...2.5)

        // Warm bokeh up close
        for _ in 0..<12 {
            let base = CGFloat.random(in: 0.10...0.25)
            let g = glow(CGPoint(x: .random(in: 0...W), y: H * .random(in: 0.02...0.12)), diameter: .random(in: 25...80),
                         color: Art.color(1.0, .random(in: 0.65...0.85), .random(in: 0.3...0.5)), alpha: base, z: 8)
            pulse(g, from: base, to: base * 0.4, period: 2...5)
        }
    }

    // MARK: - Northern lights

    private func buildAurora() {
        gradient(CGRect(origin: .zero, size: size), bottom: Art.color(0.04, 0.09, 0.14), top: Art.color(0.0, 0.01, 0.05))
        stars(count: 220, minY: H * 0.25, z: 0.5)

        // Glowing curtains: columns of soft light that ripple and breathe (animated in update)
        let bands: [(y: CGFloat, color: NSColor, amp: CGFloat)] = [
            (0.62, Art.color(0.25, 1.0, 0.55), 0.10),
            (0.70, Art.color(0.20, 0.85, 0.80), 0.07),
            (0.76, Art.color(0.65, 0.35, 1.0), 0.06),
        ]
        let columns = 46
        for (bi, band) in bands.enumerated() {
            for i in 0..<columns {
                let s = SKSpriteNode(texture: Textures.softDot, size: CGSize(width: W / CGFloat(columns) * 3.2, height: H * 0.42))
                s.color = band.color
                s.colorBlendFactor = 1
                s.blendMode = .add
                let x = W * CGFloat(i) / CGFloat(columns - 1)
                let y = H * band.y + H * band.amp * sin(CGFloat(i) * 0.23 + CGFloat(bi) * 1.7)
                s.position = CGPoint(x: x, y: y)
                let a: CGFloat = bi == 2 ? 0.10 : 0.16
                s.alpha = a
                add(s, z: 1 + CGFloat(bi) * 0.1)
                aurora.append((s, bi, i, y, a))
            }
        }

        // Mountains with snowy peaks
        let peaks: [(CGFloat, CGFloat)] = [(0, 0.30), (0.08, 0.40), (0.17, 0.33), (0.27, 0.47), (0.38, 0.35),
                                           (0.50, 0.44), (0.60, 0.34), (0.70, 0.50), (0.82, 0.36), (0.91, 0.42), (1.0, 0.31)]
        var mountain = [CGPoint(x: 0, y: H * 0.18)]
        mountain += peaks.map { CGPoint(x: W * $0.0, y: H * $0.1) }
        mountain.append(CGPoint(x: W, y: H * 0.18))
        add(Art.polygon(mountain, Art.color(0.05, 0.07, 0.12), outline: false), z: 2)
        for (i, pk) in peaks.enumerated() where i > 0 && i < peaks.count - 1 && i % 2 == 1 {
            let tip = CGPoint(x: W * pk.0, y: H * pk.1)
            let w = W * 0.035, d = H * 0.05
            add(Art.polygon([tip, CGPoint(x: tip.x + w, y: tip.y - d), CGPoint(x: tip.x + w * 0.3, y: tip.y - d * 0.7),
                             CGPoint(x: tip.x - w * 0.3, y: tip.y - d * 0.85), CGPoint(x: tip.x - w, y: tip.y - d)],
                            Art.color(0.80, 0.86, 0.95), outline: false), z: 2.1)
        }

        // Frozen lake catching the glow, and a dark shoreline of pines
        gradient(CGRect(x: 0, y: 0, width: W, height: H * 0.18), bottom: Art.color(0.05, 0.08, 0.13),
                 top: Art.color(0.10, 0.17, 0.22), z: 3)
        let shine = glow(CGPoint(x: W * 0.5, y: H * 0.1), diameter: W * 0.9, color: Art.color(0.3, 1, 0.6), alpha: 0.10, z: 3.1)
        shine.yScale = 0.15
        pulse(shine, from: 0.10, to: 0.05, period: 3...5)
        for i in 0..<40 {
            let x = W * CGFloat(i) / 39 + .random(in: -10...10)
            pine(at: CGPoint(x: x, y: H * 0.165), height: .random(in: 26...60), color: Art.color(0.02, 0.03, 0.05),
                 snow: false, z: 4)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard !aurora.isEmpty else { return }
        let dt = lastUpdate == 0 ? 1.0 / 30 : min(0.1, currentTime - lastUpdate)
        lastUpdate = currentTime
        clock += dt
        let t = CGFloat(clock)
        for c in aurora {
            let i = CGFloat(c.i), b = CGFloat(c.band)
            let wave = sin(t * 0.35 + i * 0.21 + b * 1.3)
            c.sprite.position.y = c.baseY + H * 0.025 * wave
            let breathe = 0.55 + 0.45 * sin(t * 0.5 + i * 0.37 - b * 0.9) * sin(t * 0.13 + i * 0.07)
            c.sprite.alpha = c.baseAlpha * max(0.15, breathe)
            c.sprite.xScale = 1 + 0.2 * sin(t * 0.4 + i * 0.5)
        }
    }
}
