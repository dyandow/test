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
    /// Set by the app when it sees a full-screen Space is showing.
    var systemFullScreen = false {
        didSet { if systemFullScreen != oldValue { updateFullScreen() } }
    }
    private var geometryFullScreen = false
    /// When the window server can tell us directly, ignore the guesswork.
    var trustsSystemFullScreen = false
    private var windowByID: [CGWindowID: TrackedWindow] = [:]
    private let sled = Sled()
    private var snowmen: [Snowman] = []
    private var rollingBall: SKShapeNode?
    private var rollingRadius: CGFloat = 0
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
        case body(Body)
    }

    private static let maxFalling = 1400
    private static let maxTotal = 2100

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

        sled.node.zPosition = 31
        sled.node.position = CGPoint(x: 140, y: groundY + ground.surface(atLocalX: 140) - 3)
        sled.body.support = .ground
        sled.body.localX = 140
        props.addChild(sled.node)

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
        matchSnowToSetting()
        let mode = settings.fullScreenMode
        props.isHidden = fullScreen && mode != .keepAll
        snowLayer.isHidden = fullScreen && mode == .hideAll
        train.setWedding(settings.weddingTrain)
        train.node.isHidden = !settings.showTrain
        tree.node.isHidden = !settings.showTree
        sled.node.isHidden = !settings.showSled
        if !settings.showSnowmen {
            snowmen.forEach { $0.node.removeFromParent(); $0.body.snowman = nil }
            snowmen.removeAll()
            rollingBall?.removeFromParent()
            rollingBall = nil
        }
        station.node.isHidden = !settings.showTramStation
        tramLines.forEach { $0.setHidden(!settings.showTramStation) }
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
        if settings.showTramStation && station.hitTest(p) { return true }
        if settings.showTramStation && tramLines.contains(where: { $0.endHitTest(p) || $0.carHitTest(p) }) { return true }
        if tree.hitTest(p) { return true }
        if settings.showSled && sled.body.hitTest(p) { return true }
        if settings.showSnowmen && snowmen.contains(where: { $0.body.hitTest(p) }) { return true }
        if train.hitTest(p) { return true }
        return false
    }

    private func updateFullScreen() {
        let isFull = trustsSystemFullScreen ? systemFullScreen : (geometryFullScreen || systemFullScreen)
        guard isFull != fullScreen else { return }
        fullScreen = isFull
        if isFull { drag = nil }
        applySettings()
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastUpdate)
        lastUpdate = currentTime
        clock += dt
        frameCount += 1

        refreshWindows()
        spawnSnow(dt)
        stepFlakes(dt)
        if settings.showTrain {
            train.step(dt) { [weak self] p, big in self?.puff(at: p, big: big) }
            plow()
        }
        if settings.showTramStation { for line in tramLines { line.step(dt) } }
        if settings.showSled { stepBody(sled.body, CGFloat(dt)) }
        if settings.showSnowmen { for man in snowmen { stepBody(man.body, CGFloat(dt)) } }
        if tramLines.contains(where: { $0.finished }) {
            tramLines.removeAll { $0.finished }
            saveLines()
        }

        ground.relax(maxSlope: 3)
        ground.redrawIfNeeded()
        for pile in windowPiles.values where !pile.node.isHidden {
            pile.relax(maxSlope: 0.8)
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

    private var snowTarget: Int {
        guard settings.snowEnabled else { return 0 }
        return Int(min(Double(Self.maxFalling) * 0.8, settings.snowAmount.flakesPerSecond * Double(size.height) / 45))
    }

    /// When the snow setting changes, add or melt away flakes right now instead of waiting for them to fall.
    private func matchSnowToSetting() {
        let drifting = flakes.indices.filter { !flakes[$0].ballistic }
        let target = snowTarget
        if drifting.count > target {
            let extra = drifting.shuffled().prefix(drifting.count - target)
            for i in extra.sorted(by: >) {
                let f = flakes[i]
                f.sprite.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
                flakes.remove(at: i)
            }
        } else if drifting.count < target {
            for _ in 0..<(target - drifting.count) { spawnFlake(y: .random(in: groundY...size.height)) }
        }
    }

    private func spawnFlake(y: CGFloat? = nil) {
        // Three depths: tiny far-away flakes, mid flakes that settle on windows, and big soft near ones.
        let roll = Double.random(in: 0..<1)
        let layer = roll < 0.3 ? 0 : (roll < 0.85 ? 1 : 2)
        let catchable = layer == 1
        let s: CGFloat = [CGFloat.random(in: 1.2...2.0), .random(in: 2.0...3.4), .random(in: 4.0...6.5)][layer]
        let sprite = SKSpriteNode(texture: layer == 2 ? Textures.softDot : Textures.flake, size: CGSize(width: s, height: s))
        sprite.alpha = [CGFloat.random(in: 0.4...0.6), .random(in: 0.7...0.95), .random(in: 0.55...0.8)][layer]
        sprite.position = CGPoint(x: .random(in: -30...(size.width + 30)), y: y ?? size.height + 8)
        sprite.zPosition = [CGFloat(9), 36, 40][layer]
        snowLayer.addChild(sprite)
        let speed: CGFloat = [CGFloat(22), 34, 52][layer] * .random(in: 0.8...1.2)
        flakes.append(Flake(sprite: sprite, vx: .random(in: -6...10), vy: -speed,
                            phase: .random(in: 0...(2 * .pi)), sway: .random(in: 6...18) * (layer == 2 ? 1.5 : 1),
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
        let wind = 7 * sin(t * 0.05) + 4 * sin(t * 0.17 + 1)
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
                p.x += (f.vx + wind + sin(t * (0.6 + f.phase * 0.12) + f.phase) * f.sway) * d
                p.y += f.vy * d
            }

            var landed = false
            if f.catchable && settings.snowOnWindows {
                landed = landOnWindow(from: p0, to: p, amount: f.size * 0.45)
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
            let surface = w.frame.maxY + pile.surfaceOffset(b)
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

        // Full screen = a window covering the entire screen, or (on Macs with a notch, where
        // full-screen apps stop below the notch) a screen-wide window while the menu bar is hidden.
        // A merely maximized window doesn't count: the menu bar is still showing.
        let spansWidth: (TrackedWindow) -> Bool = { $0.frame.minX <= 2 && $0.frame.maxX >= self.size.width - 2 && $0.frame.minY <= 2 }
        let coversAll = tracker.windows.contains { spansWidth($0) && $0.frame.maxY >= self.size.height - 1 }
        let coversBelowNotch = tracker.windows.contains { spansWidth($0) && $0.frame.maxY >= self.size.height - max(self.topInset, 24) - 30 }
        geometryFullScreen = coversAll ||
            (tracker.menuBarEverSeen && !tracker.menuBarVisible && coversBelowNotch)
        updateFullScreen()

        windowByID = Dictionary(uniqueKeysWithValues: tracker.windows.map { ($0.id, $0) })
        for line in tramLines {
            if let id = line.attachedWindow, let w = windowByID[id] {
                let p = CGPoint(x: w.frame.minX + line.attachOffset.x, y: w.frame.maxY + line.attachOffset.y)
                if p != line.end { line.setEnd(p) }
            }
        }

        guard settings.snowOnWindows else { return }
        var seen = Set<CGWindowID>()
        for w in tracker.windows {
            seen.insert(w.id)
            let pile: SnowPile
            if let existing = windowPiles[w.id] {
                pile = existing
            } else {
                pile = SnowPile(width: w.frame.width, binWidth: 4, maxHeight: 20, baseHeight: 0, taperEdges: true)
                pile.node.zPosition = 10
                pile.cornerRadius = 12
                props.addChild(pile.node)
                windowPiles[w.id] = pile
            }
            if abs(pile.width - w.frame.width) > 0.5 { pile.resize(width: w.frame.width) }
            pile.node.position = CGPoint(x: w.frame.minX, y: w.frame.maxY)
            pile.node.isHidden = false
            shedIfMovingFast(pile, window: w)
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

    /// Loose snow: a window moved quickly leaves some of its snow behind; yanked down, it loses more.
    private func shedIfMovingFast(_ pile: SnowPile, window w: TrackedWindow) {
        let v = tracker.velocities[w.id] ?? .zero
        let speed = max(abs(v.dx) - 600, 0) / 5000 + max(-v.dy - 500, 0) / 2500
        guard speed > 0 else { return }
        let fraction = min(0.3, speed)
        var budget = 40
        for b in stride(from: Int.random(in: 0..<3), to: pile.binCount, by: 3) where pile.heights[b] > 0.6 && pile.isVisible(b) {
            let lost = pile.heights[b] * fraction
            pile.heights[b] -= lost
            if budget > 0 && Double.random(in: 0..<1) < Double(lost) * 0.6 {
                budget -= 1
                spawnThrown(at: CGPoint(x: w.frame.minX + (CGFloat(b) + 0.5) * pile.binWidth,
                                        y: w.frame.maxY + pile.surfaceOffset(b)),
                            vx: -v.dx * 0.15 + .random(in: -40...40), vy: .random(in: 0...60))
            }
        }
        pile.dirty = true
    }

    /// Sweeping the pointer quickly across the snow on a window brushes it off.
    private var lastBrushPoint: CGPoint?
    private var lastBrushTime: TimeInterval = 0

    func brush(at p: CGPoint) {
        defer { lastBrushPoint = p; lastBrushTime = clock }
        guard settings.snowOnWindows, !fullScreen, drag == nil, let last = lastBrushPoint else { return }
        let dt = max(clock - lastBrushTime, 1.0 / 120)
        let vx = (p.x - last.x) / CGFloat(dt), vy = (p.y - last.y) / CGFloat(dt)
        guard hypot(vx, vy) > 350 else { return }
        for (i, w) in tracker.windows.enumerated() where p.x >= w.frame.minX - 10 && p.x <= w.frame.maxX + 10 {
            guard let pile = windowPiles[w.id], !pile.node.isHidden else { continue }
            let top = w.frame.maxY
            guard p.y >= top - 6, p.y <= top + pile.maxHeight + 14 else { continue }
            guard windowTopVisible(index: i, x: min(max(p.x, w.frame.minX), w.frame.maxX)) else { continue }
            // sweep along the path the pointer took this tick
            let lo = min(last.x, p.x) - 16, hi = max(last.x, p.x) + 16
            var removed: CGFloat = 0
            for b in 0..<pile.binCount {
                let x = w.frame.minX + (CGFloat(b) + 0.5) * pile.binWidth
                guard x >= lo, x <= hi, pile.heights[b] > 0.2 else { continue }
                let take = pile.heights[b] * 0.85
                pile.heights[b] -= take
                removed += take
                if Double.random(in: 0..<1) < Double(take) * 0.45 {
                    spawnThrown(at: CGPoint(x: x, y: top + pile.surfaceOffset(b) + .random(in: 0...take)),
                                vx: vx * 0.35 + .random(in: -50...50), vy: .random(in: 40...170))
                }
            }
            if removed > 0 { pile.dirty = true }
            break
        }
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
        // The plow shoves the sled along and bowls snowmen over.
        if sled.body.support == .ground, !sled.body.dragging,
           sled.node.position.x - sled.body.halfWidth < front, sled.node.position.x > train.rearX {
            sled.body.localX = front + sled.body.halfWidth + 1
            sled.body.velocity.dx = max(sled.body.velocity.dx, train.speed)
        }
        for man in snowmen where man.body.support == .ground && !man.body.dragging {
            let x = man.node.position.x
            if x > front - 6 && x < front + 14 { crumble(man, at: man.node.position, on: .ground) }
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
        let trams = settings.showTramStation
        if trams, let line = tramLines.last(where: { $0.endHitTest(p) }) {
            drag = .lineEnd(line)
        } else if trams, !station.hitTest(p), let line = tramLines.last(where: { $0.carHitTest(p) }) {
            line.retract()
        } else if trams, station.hitTest(p) {
            let preview = SKShapeNode()
            preview.strokeColor = Art.color(0.95, 0.95, 1.0, 0.85)
            preview.lineWidth = 2
            preview.zPosition = 24
            preview.path = TramLine.previewPath(from: station.anchor, to: p)
            props.addChild(preview)
            drag = .newLine(preview: preview)
        } else if let b = draggableBody(at: p) {
            b.dragging = true
            b.grab = CGPoint(x: b.node.position.x - p.x, y: b.node.position.y - p.y)
            b.lastDragPoint = b.node.position
            b.lastDragTime = event.timestamp
            b.dragVelocity = .zero
            if b.kind == .snowman { b.support = nil }
            drag = .body(b)
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
        case .body(let b):
            dragBody(b, to: p, time: event.timestamp)
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
                if let line = tramLines.last { hook(line) }
                saveLines()
            } else if station.hitTest(p) {
                // A plain click on the station (no drag) opens the settings window.
                onMenuRequest?()
            }
        case .lineEnd(let line):
            hook(line)
            saveLines()
        case .body(let b):
            releaseBody(b)
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

    // MARK: - Cable cars hooked onto windows

    /// If a cable end was dropped on a window, hook it there so it follows the window.
    private func hook(_ line: TramLine) {
        let p = line.end
        if let w = tracker.windows.first(where: { $0.frame.insetBy(dx: 0, dy: -20).contains(p) }) {
            line.attachedWindow = w.id
            line.attachOffset = CGPoint(x: p.x - w.frame.minX, y: min(0, p.y - w.frame.maxY))
            line.setEnd(CGPoint(x: w.frame.minX + line.attachOffset.x, y: w.frame.maxY + line.attachOffset.y))
        } else {
            line.attachedWindow = nil
        }
    }

    // MARK: - Snowmen (hold Option and sweep through the ground snow)

    /// Called ~30 times a second with the pointer position while Option is held (nil otherwise).
    func optionSweep(at p: CGPoint?) {
        guard settings.showSnowmen, !fullScreen, let p else { finishBall(); return }
        let groundTop = groundY + ground.surface(atLocalX: p.x)
        if rollingBall == nil {
            // Start a ball only when sweeping low, through the snow along the bottom.
            guard p.y < groundTop + 60, p.x > 10, p.x < size.width - 10 else { return }
            rollingRadius = 5
            let ball = makeSnowball(radius: 1)
            ball.zPosition = 34
            ball.position = CGPoint(x: p.x, y: groundTop + rollingRadius)
            ball.setScale(rollingRadius)
            ball.lineWidth = 1.2 / rollingRadius
            props.addChild(ball)
            rollingBall = ball
            return
        }
        guard let ball = rollingBall else { return }
        if p.y > groundTop + 160 { finishBall(); return }
        let x = min(max(p.x, 10), size.width - 10)
        let dx = x - ball.position.x
        // Grow by picking up the snow it rolls over.
        if rollingRadius < 30 {
            var grow = abs(dx) * 0.03
            if let b = ground.bin(atLocalX: x), ground.heights[b] > 0.3 {
                let take = min(ground.heights[b], abs(dx) * 0.08)
                ground.heights[b] -= take
                ground.dirty = true
                grow += take * 0.3
            }
            rollingRadius = min(30, rollingRadius + grow)
        }
        ball.setScale(rollingRadius)
        ball.lineWidth = 1.2 / rollingRadius
        ball.zRotation -= dx / max(rollingRadius, 1)
        ball.position = CGPoint(x: x, y: groundY + ground.surface(atLocalX: x) + rollingRadius - 2)
    }

    private func finishBall() {
        guard let ball = rollingBall else { return }
        rollingBall = nil
        let x = ball.position.x
        let r = rollingRadius
        ball.removeFromParent()
        guard r >= 7 else { return }
        if let man = snowmen.first(where: { !$0.isComplete && !$0.body.dragging && $0.body.support != nil
                                            && abs($0.node.position.x - x) < $0.baseRadius + r + 12 }) {
            man.add(radius: r)
        } else {
            let man = Snowman(at: CGPoint(x: x, y: groundY + ground.surface(atLocalX: x) - 3))
            man.node.zPosition = 34
            props.addChild(man.node)
            man.add(radius: r)
            man.body.support = .ground
            man.body.localX = x
            snowmen.append(man)
        }
    }

    // MARK: - Sled and snowmen physics

    private func draggableBody(at p: CGPoint) -> Body? {
        if settings.showSnowmen, let man = snowmen.last(where: { $0.body.hitTest(p) }) { return man.body }
        if settings.showSled, sled.body.hitTest(p) { return sled.body }
        return nil
    }

    private func windowTopVisible(index i: Int, x: CGFloat) -> Bool {
        let w = tracker.windows[i]
        let p = CGPoint(x: x, y: w.frame.maxY + 2)
        return !tracker.windows[..<i].contains { $0.frame.contains(p) }
    }

    private func pileHeight(_ id: CGWindowID, atSceneX x: CGFloat) -> CGFloat {
        guard let w = windowByID[id], let pile = windowPiles[id], !pile.node.isHidden,
              let b = pile.bin(atLocalX: x - w.frame.minX), pile.isVisible(b) else { return 0 }
        return pile.surfaceOffset(b)
    }

    /// Top of a surface at x, or nil if x is off its edge.
    private func surfaceTop(_ s: Body.Support, x: CGFloat) -> CGFloat? {
        switch s {
        case .ground:
            return groundY + ground.surface(atLocalX: min(max(x, 0), size.width - 1)) - 3
        case .window(let id):
            guard let w = windowByID[id], x >= w.frame.minX - 2, x <= w.frame.maxX + 2 else { return nil }
            return w.frame.maxY + pileHeight(id, atSceneX: x) * 0.85
        }
    }

    /// The highest surface at x whose top is at or below y.
    private func supportBelow(x: CGFloat, y: CGFloat) -> (Body.Support, CGFloat) {
        var best: (Body.Support, CGFloat) = (.ground, surfaceTop(.ground, x: x) ?? groundY)
        for (i, w) in tracker.windows.enumerated() where x >= w.frame.minX && x <= w.frame.maxX {
            guard let top = surfaceTop(.window(w.id), x: x), top <= y + 3, top > best.1,
                  windowTopVisible(index: i, x: x) else { continue }
            best = (.window(w.id), top)
        }
        return best
    }

    private func setSupport(_ b: Body, _ s: Body.Support, x: CGFloat) {
        b.support = s
        switch s {
        case .ground: b.localX = x
        case .window(let id): b.localX = x - (windowByID[id]?.frame.minX ?? 0)
        }
    }

    private func liftOff(_ b: Body) {
        b.support = nil
        b.highestPoint = b.node.position.y
    }

    private func stepBody(_ b: Body, _ dt: CGFloat) {
        guard !b.dragging, dt > 0 else { return }
        var p = b.node.position
        if let s = b.support {
            switch s {
            case .window(let id):
                guard let w = windowByID[id] else { liftOff(b); return }
                let wv = tracker.velocities[id] ?? .zero
                if wv.dy < -900 {
                    // The window was yanked down: whatever's on top is left hanging in the air.
                    liftOff(b)
                    b.velocity = CGVector(dx: b.velocity.dx + wv.dx * 0.3, dy: 0)
                    return
                }
                if b.kind == .sled && (wv.dy > 650 || abs(wv.dx) > 1600) {
                    // Flicked: the sled gets launched.
                    liftOff(b)
                    b.velocity = CGVector(dx: b.velocity.dx + wv.dx * 0.85, dy: max(wv.dy, 0) + 160)
                    return
                }
                b.localX += b.velocity.dx * dt
                p.x = w.frame.minX + b.localX
            case .ground:
                b.localX += b.velocity.dx * dt
                p.x = b.localX
            }
            // Sliding friction: a sled glides on a window top, a bit less on snow; snowmen don't slide.
            let friction: CGFloat = b.kind == .snowman ? 12 : (s == .ground ? 1.3 : 0.55)
            b.velocity.dx *= exp(-friction * dt)
            if abs(b.velocity.dx) < 4 { b.velocity.dx = 0 }
            if p.x < b.halfWidth || p.x > size.width - b.halfWidth {
                p.x = min(max(p.x, b.halfWidth), size.width - b.halfWidth)
                b.velocity.dx = -b.velocity.dx * 0.5
                setSupport(b, s, x: p.x)
            }
            guard let top = surfaceTop(s, x: p.x) else {
                // Slid off the end of a window.
                liftOff(b)
                b.velocity.dy = 0
                b.node.position = p
                return
            }
            p.y = top
            b.node.position = p
            b.node.zRotation += (0 - b.node.zRotation) * min(1, dt * 12)
            if b.kind == .sled, b.velocity.dx != 0 { b.node.xScale = b.velocity.dx < 0 ? -1 : 1 }
        } else {
            let p0 = p
            b.velocity.dy -= 1500 * dt
            p.x += b.velocity.dx * dt
            p.y += b.velocity.dy * dt
            if p.x < b.halfWidth || p.x > size.width - b.halfWidth {
                p.x = min(max(p.x, b.halfWidth), size.width - b.halfWidth)
                b.velocity.dx = -b.velocity.dx * 0.5
            }
            b.highestPoint = max(b.highestPoint, p.y)
            if b.velocity.dy <= 0 {
                let (s, top) = supportBelow(x: p.x, y: p0.y)
                if p.y <= top {
                    land(b, on: s, at: CGPoint(x: p.x, y: top))
                    return
                }
            }
            b.node.position = p
            let target: CGFloat = b.kind == .sled
                ? max(-0.5, min(0.5, b.velocity.dy / 2600)) * (b.velocity.dx >= 0 ? 1 : -1)
                : max(-0.25, min(0.25, -b.velocity.dx / 3000))
            b.node.zRotation += (target - b.node.zRotation) * min(1, dt * 8)
        }
    }

    private func land(_ b: Body, on s: Body.Support, at p: CGPoint) {
        let fell = b.highestPoint - p.y
        if b.kind == .snowman, !b.gentleLanding, fell > 220, let man = b.snowman {
            crumble(man, at: p, on: s)
            return
        }
        b.gentleLanding = false
        setSupport(b, s, x: p.x)
        b.velocity.dy = 0
        b.velocity.dx = b.kind == .snowman ? 0 : b.velocity.dx * 0.85
        b.node.position = p
        b.node.removeAction(forKey: "squash")
        b.node.run(.sequence([.scaleY(to: 0.88, duration: 0.06), .scaleY(to: 1, duration: 0.12)]), withKey: "squash")
    }

    private func dragBody(_ b: Body, to p: CGPoint, time: TimeInterval) {
        var target = CGPoint(x: p.x + b.grab.x, y: p.y + b.grab.y)
        target.x = min(max(target.x, b.halfWidth), size.width - b.halfWidth)
        let dt = time - b.lastDragTime
        if dt > 0.004 {
            let v = CGVector(dx: (target.x - b.lastDragPoint.x) / CGFloat(dt), dy: (target.y - b.lastDragPoint.y) / CGFloat(dt))
            b.dragVelocity = CGVector(dx: b.dragVelocity.dx * 0.4 + v.dx * 0.6, dy: b.dragVelocity.dy * 0.4 + v.dy * 0.6)
            b.lastDragPoint = target
            b.lastDragTime = time
        }
        if b.kind == .sled {
            // Pushing the sled keeps it on the surface under the pointer unless you lift it well clear.
            let (s, top) = supportBelow(x: target.x, y: target.y + 40)
            if target.y - top < 45 {
                setSupport(b, s, x: target.x)
                b.node.position = CGPoint(x: target.x, y: top)
                if b.dragVelocity.dx != 0 { b.node.xScale = b.dragVelocity.dx < 0 ? -1 : 1 }
                return
            }
            b.support = nil
        }
        b.node.position = target
    }

    private func releaseBody(_ b: Body) {
        b.dragging = false
        let v = CGVector(dx: max(-2600, min(2600, b.dragVelocity.dx)), dy: max(-2600, min(2600, b.dragVelocity.dy)))
        if b.kind == .sled, b.support != nil {
            b.velocity = CGVector(dx: v.dx, dy: 0)
        } else {
            liftOff(b)
            b.velocity = b.kind == .snowman ? CGVector(dx: v.dx * 0.3, dy: max(-300, min(300, v.dy * 0.3))) : v
        }
    }

    /// A snowman that falls too far breaks apart into a little pile of snow.
    private func crumble(_ man: Snowman, at p: CGPoint, on s: Body.Support) {
        let size = man.radii.reduce(0, +)
        for _ in 0..<min(240, Int(size * 4)) {
            spawnThrown(at: CGPoint(x: p.x + .random(in: -size * 0.4...size * 0.4), y: p.y + .random(in: 0...size * 1.3)),
                        vx: .random(in: -170...170), vy: .random(in: 40...280))
        }
        let spread = max(12, size * 0.5)
        let amount = size * 0.5
        switch s {
        case .ground:
            for b in 0..<ground.binCount {
                let d = (CGFloat(b) + 0.5) * ground.binWidth - p.x
                guard abs(d) < spread * 2.5 else { continue }
                ground.heights[b] = min(ground.cap(b), ground.heights[b] + amount * exp(-(d * d) / (spread * spread)))
            }
            ground.dirty = true
        case .window(let id):
            if let pile = windowPiles[id], let w = windowByID[id] {
                for b in 0..<pile.binCount {
                    let d = w.frame.minX + (CGFloat(b) + 0.5) * pile.binWidth - p.x
                    guard abs(d) < spread * 2.5 else { continue }
                    pile.heights[b] = min(pile.cap(b), pile.heights[b] + amount * 0.6 * exp(-(d * d) / (spread * spread)))
                }
                pile.dirty = true
            }
        }
        man.node.removeFromParent()
        man.body.snowman = nil
        snowmen.removeAll { $0 === man }
    }

    /// "Build a Snowman" from the settings window: a finished snowman drops onto the front window.
    func dropSnowman() {
        guard settings.showSnowmen, !fullScreen else { return }
        let target = tracker.windows.first(where: { $0.frame.maxY < size.height - topInset - 60 })
        let x = target.map { $0.frame.minX + $0.frame.width * .random(in: 0.25...0.75) } ?? .random(in: size.width * 0.3...size.width * 0.7)
        let man = Snowman(at: CGPoint(x: x, y: size.height - topInset - 70))
        man.node.zPosition = 34
        props.addChild(man.node)
        man.add(radius: 19, chime: false)
        man.add(radius: 14, chime: false)
        man.add(radius: 10, chime: true)
        man.body.support = nil
        man.body.gentleLanding = true
        man.body.highestPoint = man.node.position.y
        snowmen.append(man)
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
