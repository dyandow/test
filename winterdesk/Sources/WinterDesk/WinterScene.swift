import AppKit
import SpriteKit

private struct Flake {
    let sprite: SKSpriteNode
    var vx: CGFloat
    var vy: CGFloat
    var phase: CGFloat
    var sway: CGFloat
    /// Thrown snow (plow spray, shaken-off snow) flies under gravity instead of drifting.
    var ballistic: Bool
    /// Only some flakes settle on window tops; the rest fall past in front, for depth.
    var catchable: Bool
    var size: CGFloat
}

/// The transparent layer over everything: falling snow, snow on window tops,
/// the snowy ground with the train, the tree and the trams.
@MainActor
final class WinterScene: SKScene {
    private let settings = Settings.shared
    private let groundY: CGFloat
    private let topInset: CGFloat

    private var flakes: [Flake] = []
    private let ground: SnowPile
    private var windowPiles: [CGWindowID: SnowPile] = [:]
    private var pileLastSeen: [CGWindowID: TimeInterval] = [:]
    private let tracker = WindowTracker()
    private let train: Train
    private let tree = ChristmasTree()
    private let station = TramStation()
    private var tramLines: [TramLine] = []
    /// Everything except the falling snow; hidden over full-screen apps.
    private let props = SKNode()
    private let snowLayer = SKNode()
    private var fullScreen = false
    /// Right-clicking the tree opens the app menu.
    var onMenuRequest: (() -> Void)?

    private var lastUpdate: TimeInterval = 0
    private var clock: TimeInterval = 0
    private var spawnDebt: Double = 0
    private var sprayDebt: Double = 0
    private var frameCount = 0
    private var drag: Drag?

    private enum Drag {
        case tree(grab: CGPoint, start: CGPoint, moved: Bool)
        case newLine(preview: SKShapeNode)
        case lineEnd(TramLine)
    }

    private static let maxFalling = 1000
    private static let maxTotal = 1700

    init(size: CGSize, groundY: CGFloat, topInset: CGFloat) {
        self.groundY = groundY
        self.topInset = topInset
        ground = SnowPile(width: size.width, binWidth: 4, maxHeight: 30, baseHeight: 6, taperEdges: false)
        train = Train(sceneWidth: size.width, baseY: groundY + 2)
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        self.addChild(props)
        snowLayer.zPosition = 0
        self.addChild(snowLayer)
        // Start with some snow on the ground so the train has something to plow.
        for b in 0..<ground.binCount {
            let x = CGFloat(b)
            ground.heights[b] = 9 + 3 * sin(x * 0.05) + 2 * sin(x * 0.13 + 1)
        }
        ground.node.position = CGPoint(x: 0, y: groundY)
        ground.node.zPosition = 35
        props.addChild(ground.node)

        train.node.zPosition = 30
        train.setWedding(settings.weddingTrain)
        props.addChild(train.node)

        tree.node.zPosition = 20
        tree.node.position = clampTree(settings.treePosition ?? CGPoint(x: size.width - 190, y: groundY + 40))
        tree.restore(settings.treeLights)
        props.addChild(tree.node)

        station.node.position = CGPoint(x: size.width / 2, y: size.height - topInset - 34)
        station.node.zPosition = 27
        props.addChild(station.node)
        for e in settings.tramEnds where e.count == 2 { addLine(end: clamp(CGPoint(x: e[0], y: e[1]))) }
        station.showHint(tramLines.isEmpty)

        tracker.onShake = { [weak self] id in self?.shakeOff(id) }

        if settings.snowEnabled {
            let count = min(Double(Self.maxFalling) * 0.8, settings.snowAmount.flakesPerSecond * Double(size.height) / 70)
            for _ in 0..<Int(count) { spawnFlake(y: .random(in: groundY...size.height)) }
        }
        applySettings()
    }

    // MARK: - Public controls (menu bar)

    func applySettings() {
        let mode = settings.fullScreenMode
        props.isHidden = fullScreen && mode != .keepAll
        snowLayer.isHidden = fullScreen && mode == .hideAll
        train.setWedding(settings.weddingTrain)
        train.node.isHidden = !settings.showTrain
        tree.node.isHidden = !settings.showTree
        if !settings.snowOnWindows {
            for pile in windowPiles.values { pile.node.removeFromParent() }
            windowPiles.removeAll()
            pileLastSeen.removeAll()
        }
    }

    func shakeAllWindows() {
        for id in Array(windowPiles.keys) { shakeOff(id) }
    }

    func clearTreeLights() {
        tree.clearLights()
        settings.treeLights = []
    }

    /// Reel every tram back into the station.
    func removeTramLines() {
        tramLines.forEach { $0.retract() }
        saveLines()
    }

    /// Whether the overlay should take the mouse at this point (otherwise clicks pass through).
    func isInteractive(at p: CGPoint) -> Bool {
        if drag != nil { return true }
        if fullScreen && settings.fullScreenMode != .keepAll { return false }
        if station.hitTest(p) { return true }
        if tramLines.contains(where: { $0.endHitTest(p) || $0.carHitTest(p) }) { return true }
        if tree.hitTest(p) { return true }
        if train.hitTest(p) { return true }
        return false
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastUpdate)
        lastUpdate = currentTime
        clock += dt
        frameCount += 1

        if frameCount % 2 == 0 { refreshWindows() }
        spawnSnow(dt)
        stepFlakes(dt)
        if settings.showTrain {
            train.step(dt) { [weak self] p, big in self?.puff(at: p, big: big) }
            plow()
        }
        for line in tramLines { line.step(dt) }
        if tramLines.contains(where: { $0.finished }) {
            tramLines.removeAll { $0.finished }
            saveLines()
        }

        ground.relax(maxSlope: 3)
        ground.redrawIfNeeded()
        for pile in windowPiles.values where !pile.node.isHidden {
            pile.relax(maxSlope: 2)
            pile.redrawIfNeeded()
        }
    }

    // MARK: - Falling snow

    private func spawnSnow(_ dt: TimeInterval) {
        guard settings.snowEnabled else { spawnDebt = 0; return }
        spawnDebt = min(spawnDebt + settings.snowAmount.flakesPerSecond * dt, 6)
        while spawnDebt >= 1 {
            spawnDebt -= 1
            if flakes.count < Self.maxFalling { spawnFlake() }
        }
    }

    private func spawnFlake(y: CGFloat? = nil) {
        let catchable = Double.random(in: 0..<1) < 0.5
        let s: CGFloat = catchable ? .random(in: 1.8...3.4) : .random(in: 3.0...6.0)
        let sprite = SKSpriteNode(texture: Textures.flake, size: CGSize(width: s, height: s))
        sprite.alpha = catchable ? .random(in: 0.65...0.9) : .random(in: 0.75...1.0)
        sprite.position = CGPoint(x: .random(in: -30...(size.width + 30)), y: y ?? size.height + 8)
        sprite.zPosition = catchable ? 36 : 40
        snowLayer.addChild(sprite)
        flakes.append(Flake(sprite: sprite, vx: .random(in: -10...14),
                            vy: -(26 + s * 11) * .random(in: 0.85...1.15),
                            phase: .random(in: 0...(2 * .pi)), sway: .random(in: 8...26),
                            ballistic: false, catchable: catchable, size: s))
    }

    private func spawnThrown(at p: CGPoint, vx: CGFloat, vy: CGFloat) {
        guard flakes.count < Self.maxTotal else { return }
        let s = CGFloat.random(in: 2.0...3.8)
        let sprite = SKSpriteNode(texture: Textures.flake, size: CGSize(width: s, height: s))
        sprite.alpha = .random(in: 0.8...1.0)
        sprite.position = p
        sprite.zPosition = 40
        snowLayer.addChild(sprite)
        flakes.append(Flake(sprite: sprite, vx: vx, vy: vy, phase: 0, sway: 0,
                            ballistic: true, catchable: false, size: s))
    }

    private func stepFlakes(_ dt: TimeInterval) {
        let t = CGFloat(clock)
        let d = CGFloat(dt)
        let wind = 6 * sin(t * 0.07)
        var i = 0
        while i < flakes.count {
            var f = flakes[i]
            let p0 = f.sprite.position
            var p = p0
            if f.ballistic {
                f.vy -= 520 * d
                p.x += f.vx * d
                p.y += f.vy * d
            } else {
                p.x += (f.vx + wind + sin(t * 1.3 + f.phase) * f.sway) * d
                p.y += f.vy * d
            }

            var landed = false
            if f.catchable && settings.snowOnWindows {
                landed = landOnWindow(from: p0, to: p, amount: f.size * 0.28)
            }
            if !landed, f.vy < 0, p.x >= 0, p.x < size.width,
               p.y <= groundY + ground.surface(atLocalX: p.x), let b = ground.bin(atLocalX: p.x) {
                ground.deposit(bin: b, amount: f.ballistic ? 0.5 : f.size * (f.catchable ? 0.2 : 0.1))
                landed = true
            }

            if landed || p.y < -20 || p.x < -60 || p.x > size.width + 60 {
                f.sprite.removeFromParent()
                flakes.swapAt(i, flakes.count - 1)
                flakes.removeLast()
                continue
            }
            f.sprite.position = p
            flakes[i] = f
            i += 1
        }
    }

    private func landOnWindow(from p0: CGPoint, to p: CGPoint, amount: CGFloat) -> Bool {
        for w in tracker.windows {
            guard p.x >= w.frame.minX, p.x < w.frame.maxX,
                  let pile = windowPiles[w.id], !pile.node.isHidden,
                  let b = pile.bin(atLocalX: p.x - w.frame.minX), pile.isVisible(b) else { continue }
            let surface = w.frame.maxY + pile.heights[b]
            if p0.y >= surface - 0.5 && p.y < surface {
                pile.deposit(bin: b, amount: amount)
                return true
            }
        }
        return false
    }

    // MARK: - Snow on windows

    private func refreshWindows() {
        let changed = tracker.refresh(screenHeight: size.height, now: clock)

        // A window covering the whole screen means an app is in full screen: step aside.
        // (On Macs with a camera notch, full-screen apps stop just below the notch,
        // so the window only has to reach the bottom of the menu bar area.)
        let isFull = tracker.windows.first.map { w in
            w.frame.minX <= 1 && w.frame.maxX >= size.width - 1 &&
                w.frame.minY <= 1 && w.frame.maxY >= size.height - topInset - 1
        } ?? false
        if isFull != fullScreen {
            fullScreen = isFull
            if isFull { drag = nil }
            applySettings()
        }

        guard settings.snowOnWindows else { return }
        var seen = Set<CGWindowID>()
        for w in tracker.windows {
            seen.insert(w.id)
            let pile: SnowPile
            if let existing = windowPiles[w.id] {
                pile = existing
            } else {
                pile = SnowPile(width: w.frame.width, binWidth: 4, maxHeight: 14, baseHeight: 0, taperEdges: true)
                pile.node.zPosition = 10
                props.addChild(pile.node)
                windowPiles[w.id] = pile
            }
            if abs(pile.width - w.frame.width) > 0.5 { pile.resize(width: w.frame.width) }
            pile.node.position = CGPoint(x: w.frame.minX, y: w.frame.maxY)
            pile.node.isHidden = false
            pileLastSeen[w.id] = clock
        }
        // Windows that vanished (minimized, other Space, closed) keep their snow for a while.
        var stale: [CGWindowID] = []
        for (id, pile) in windowPiles where !seen.contains(id) {
            pile.node.isHidden = true
            if clock - (pileLastSeen[id] ?? clock) > 600 { stale.append(id) }
        }
        for id in stale {
            windowPiles[id]?.node.removeFromParent()
            windowPiles[id] = nil
            pileLastSeen[id] = nil
        }
        if changed { updateOcclusion() }
    }

    /// Hide the parts of each window's snow that are covered by windows in front of it.
    private func updateOcclusion() {
        let ws = tracker.windows
        for (i, w) in ws.enumerated() {
            guard let pile = windowPiles[w.id] else { continue }
            let fronts = ws[..<i].map(\.frame)
            pile.updateVisibility { lx in
                let p = CGPoint(x: w.frame.minX + lx, y: w.frame.maxY + 2)
                return !fronts.contains { $0.contains(p) }
            }
        }
    }

    private func shakeOff(_ id: CGWindowID) {
        guard let pile = windowPiles[id], !pile.node.isHidden else { return }
        let origin = pile.node.position
        var budget = 400
        for b in 0..<pile.binCount where pile.heights[b] > 0.4 && pile.isVisible(b) && budget > 0 {
            let n = min(budget, 1 + Int(pile.heights[b] / 3))
            budget -= n
            for _ in 0..<n {
                spawnThrown(at: CGPoint(x: origin.x + (CGFloat(b) + 0.5) * pile.binWidth,
                                        y: origin.y + .random(in: 0...pile.heights[b])),
                            vx: .random(in: -90...90), vy: .random(in: -20...130))
            }
        }
        pile.clear()
    }

    // MARK: - Train plow

    private func plow() {
        guard train.isRunning else { return }
        let n = ground.binCount
        let front = train.frontX
        let fb = Int(floor(front / ground.binWidth))
        let rb = max(0, Int(floor(train.rearX / ground.binWidth)))
        guard fb >= 0 else { return }

        // Scoop up everything under the train...
        var load: CGFloat = 0
        if rb <= min(fb, n - 1) {
            for b in rb...min(fb, n - 1) where ground.heights[b] > 0 {
                load += ground.heights[b]
                ground.heights[b] = 0
            }
        }
        // ...and heap it up in a mound just ahead of the plow.
        if load > 0 {
            let weights: [CGFloat] = [0.32, 0.24, 0.17, 0.12, 0.08, 0.05, 0.02]
            var overflow: CGFloat = 0
            for (k, w) in weights.enumerated() {
                let b = fb + 1 + k
                let add = load * w
                guard b < n else { overflow += add; continue }
                let cap = max(6, 32 - CGFloat(k) * 4)
                let h = ground.heights[b] + add
                if h > cap { overflow += h - cap; ground.heights[b] = cap } else { ground.heights[b] = h }
            }
            ground.dirty = true
            sprayDebt += Double(overflow) * 0.7 + Double(load) * 0.08
        }
        // Spray flies off the top of the mound.
        sprayDebt = min(sprayDebt, 12)
        while sprayDebt >= 1 {
            sprayDebt -= 1
            let x = front + .random(in: 2...14)
            spawnThrown(at: CGPoint(x: x, y: groundY + ground.surface(atLocalX: x) + 2),
                        vx: train.speed + .random(in: 30...140), vy: .random(in: 60...190))
        }
    }

    private func puff(at p: CGPoint, big: Bool) {
        if train.isWedding && Bool.random() {
            let heart = SKShapeNode(path: Art.heartPath(size: .random(in: 4...7)))
            heart.fillColor = [Art.color(1, 0.35, 0.55), Art.color(1, 0.55, 0.7), Art.color(0.95, 0.2, 0.35)].randomElement()!
            heart.strokeColor = .clear
            heart.position = p
            heart.zPosition = 29
            props.addChild(heart)
            let dur = Double.random(in: 1.8...2.6)
            heart.run(.sequence([
                .group([.moveBy(x: -CGFloat.random(in: 10...40), y: CGFloat.random(in: 60...100), duration: dur),
                        .rotate(byAngle: .random(in: -0.6...0.6), duration: dur),
                        .fadeOut(withDuration: dur)]),
                .removeFromParent(),
            ]))
            return
        }
        let r = CGFloat.random(in: 6...10) * (big ? 1.5 : 1)
        let s = SKSpriteNode(texture: Textures.softDot, size: CGSize(width: r * 2.6, height: r * 2.6))
        s.color = Art.color(0.86, 0.88, 0.93)
        s.colorBlendFactor = 1
        s.alpha = 0.8
        s.position = p
        s.zPosition = 29
        props.addChild(s)
        let dur = Double.random(in: 1.6...2.4)
        s.run(.sequence([
            .group([.moveBy(x: -CGFloat.random(in: 20...50), y: CGFloat.random(in: 50...85), duration: dur),
                    .scale(to: 2.6, duration: dur),
                    .fadeOut(withDuration: dur)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        if event.modifierFlags.contains(.control) { secondaryClick(at: p); return }
        if let line = tramLines.last(where: { $0.endHitTest(p) }) {
            drag = .lineEnd(line)
        } else if !station.hitTest(p), let line = tramLines.last(where: { $0.carHitTest(p) }) {
            line.retract()
        } else if station.hitTest(p) {
            let preview = SKShapeNode()
            preview.strokeColor = Art.color(0.95, 0.95, 1.0, 0.85)
            preview.lineWidth = 2
            preview.zPosition = 24
            preview.path = TramLine.previewPath(from: station.anchor, to: p)
            props.addChild(preview)
            drag = .newLine(preview: preview)
        } else if tree.hitTest(p) {
            drag = .tree(grab: CGPoint(x: tree.node.position.x - p.x, y: tree.node.position.y - p.y),
                         start: p, moved: false)
        } else if train.hitTest(p) {
            settings.weddingTrain.toggle()
            train.setWedding(settings.weddingTrain)
            train.toot()
            for _ in 0..<5 { puff(at: CGPoint(x: train.rearX + 258, y: train.node.position.y + 74), big: true) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = event.location(in: self)
        guard let d = drag else { return }
        switch d {
        case .tree(let grab, let start, var moved):
            if !moved && hypot(p.x - start.x, p.y - start.y) > 4 { moved = true }
            if moved { tree.node.position = clampTree(CGPoint(x: p.x + grab.x, y: p.y + grab.y)) }
            drag = .tree(grab: grab, start: start, moved: moved)
        case .newLine(let preview):
            preview.path = TramLine.previewPath(from: station.anchor, to: p)
        case .lineEnd(let line):
            line.setEnd(clamp(p))
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = event.location(in: self)
        guard let d = drag else { return }
        drag = nil
        switch d {
        case .tree(_, _, let moved):
            if !moved {
                if tree.starHit(p) { onMenuRequest?() } else { tree.toggleLight(atScenePoint: p) }
            }
            saveTree()
        case .newLine(let preview):
            preview.removeFromParent()
            if hypot(p.x - station.anchor.x, p.y - station.anchor.y) > 80 {
                addLine(end: clamp(p))
                saveLines()
            } else if station.hitTest(p) {
                // A plain click on the station (no drag) opens the settings window.
                onMenuRequest?()
            }
        case .lineEnd:
            saveLines()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        secondaryClick(at: event.location(in: self))
    }

    /// Right-click (or control-click) a cable's end post to take that cable down.
    private func secondaryClick(at p: CGPoint) {
        if let i = tramLines.lastIndex(where: { $0.endHitTest(p) }) {
            tramLines[i].remove()
            tramLines.remove(at: i)
            saveLines()
        } else if tree.hitTest(p) {
            onMenuRequest?()
        }
    }

    // MARK: - Helpers

    private func addLine(end: CGPoint) {
        let line = TramLine(start: station.anchor, end: end)
        line.add(to: props)
        tramLines.append(line)
        station.showHint(false)
    }

    private func saveLines() {
        settings.tramEnds = tramLines.filter { !$0.retracting }.map { [Double($0.end.x), Double($0.end.y)] }
        station.showHint(tramLines.allSatisfy { $0.retracting })
    }

    private func saveTree() {
        settings.treePosition = tree.node.position
        settings.treeLights = tree.lightRecords
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 12), size.width - 12),
                y: min(max(p.y, groundY + 12), size.height - topInset - 60))
    }

    private func clampTree(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 60), size.width - 60),
                y: min(max(p.y, groundY + 16), size.height - topInset - 140))
    }
}
