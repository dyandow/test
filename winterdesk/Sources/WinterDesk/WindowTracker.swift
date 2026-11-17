import AppKit
import CoreGraphics

struct TrackedWindow: Equatable {
    let id: CGWindowID
    /// In scene coordinates (origin bottom-left of the main screen).
    let frame: CGRect
}

/// Finds the other apps' windows on screen (front to back) and notices
/// when one is being shaken back and forth.
@MainActor
final class WindowTracker {
    private struct Sample { let t: TimeInterval; let p: CGPoint }

    private(set) var windows: [TrackedWindow] = []
    /// Whether the system menu bar is on screen right now (it hides in full-screen apps).
    private(set) var menuBarVisible = false
    /// Whether we've ever been able to see the menu bar in the window list at all.
    private(set) var menuBarEverSeen = false
    /// Whether the desktop wallpaper is on screen (full-screen Spaces have none).
    private(set) var wallpaperVisible = false
    private(set) var wallpaperEverSeen = false
    private var samples: [CGWindowID: [Sample]] = [:]
    private var lastShake: [CGWindowID: TimeInterval] = [:]
    private let ownPID = getpid()
    var onShake: ((CGWindowID) -> Void)?
    /// How fast each window is moving, in scene points per second (y up).
    private(set) var velocities: [CGWindowID: CGVector] = [:]

    /// Returns true when any window moved, resized, appeared, vanished or changed order.
    @discardableResult
    func refresh(screenHeight: CGFloat, now: TimeInterval) -> Bool {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return false }
        var found: [TrackedWindow] = []
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        var sawMenuBar = false
        let wallpaperLevel = Int(CGWindowLevelForKey(.desktopWindow))
        var sawWallpaper = false
        for info in raw {
            if let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == wallpaperLevel,
               (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownPID {
                sawWallpaper = true
            }
            if let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == menuLevel,
               let bd = info[kCGWindowBounds as String] as? NSDictionary,
               let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
               r.minY <= 1, r.height >= 15, r.height <= 80 {
                sawMenuBar = true
            }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha < 0.05 { continue }
            if r.width < 80 || r.height < 50 { continue }
            // Window server coordinates have y going down from the top of the main screen.
            found.append(TrackedWindow(id: id, frame: CGRect(x: r.minX, y: screenHeight - r.maxY,
                                                             width: r.width, height: r.height)))
            record(id: id, position: r.origin, now: now)
        }
        let ids = Set(found.map(\.id))
        samples = samples.filter { ids.contains($0.key) }
        velocities = velocities.filter { ids.contains($0.key) }
        menuBarVisible = sawMenuBar
        wallpaperVisible = sawWallpaper
        if sawWallpaper { wallpaperEverSeen = true }
        if sawMenuBar { menuBarEverSeen = true }
        let changed = found != windows
        windows = found
        return changed
    }

    private func record(id: CGWindowID, position: CGPoint, now: TimeInterval) {
        var s = samples[id, default: []]
        if let last = s.last, now - last.t > 0.001 {
            let dt = CGFloat(now - last.t)
            let raw = CGVector(dx: (position.x - last.p.x) / dt, dy: -(position.y - last.p.y) / dt)
            let old = velocities[id] ?? .zero
            velocities[id] = CGVector(dx: old.dx * 0.5 + raw.dx * 0.5, dy: old.dy * 0.5 + raw.dy * 0.5)
        } else if s.isEmpty {
            velocities[id] = .zero
        }
        s.append(Sample(t: now, p: position))
        s.removeAll { now - $0.t > 0.9 }
        samples[id] = s
        if isShake(s), now - (lastShake[id] ?? -10) > 1.0 {
            lastShake[id] = now
            samples[id] = []
            onShake?(id)
        }
    }

    /// A shake = quick back-and-forth: several direction reversals and enough travel within ~1s.
    private func isShake(_ s: [Sample]) -> Bool {
        guard s.count >= 5 else { return false }
        var reversalsX = 0, reversalsY = 0
        var lastDX: CGFloat = 0, lastDY: CGFloat = 0
        var travel: CGFloat = 0
        for i in 1..<s.count {
            let dx = s[i].p.x - s[i - 1].p.x
            let dy = s[i].p.y - s[i - 1].p.y
            travel += hypot(dx, dy)
            if abs(dx) > 4 {
                if lastDX != 0 && (dx > 0) != (lastDX > 0) { reversalsX += 1 }
                lastDX = dx
            }
            if abs(dy) > 4 {
                if lastDY != 0 && (dy > 0) != (lastDY > 0) { reversalsY += 1 }
                lastDY = dy
            }
        }
        return travel > 110 && max(reversalsX, reversalsY) >= 2
    }
}
