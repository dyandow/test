import AppKit
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var overlay: OverlayPanel?
    private var backdrop: BackdropWindow?
    private var backdropView: SKView?
    private var scene: WinterScene?
    private var statusItem: NSStatusItem?
    private var mouseTimer: Timer?
    /// A tiny invisible window that is NOT allowed on full-screen Spaces.
    /// When it stops being visible, another app is full screen.
    private var probe: NSWindow?
    /// Only trust the probe once it has been seen visible at least once.
    private var probeWorks = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindows()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(pollMouse),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    /// Opening the app again while it's running pops up the menu right at the pointer,
    /// in case the menu bar icon is hidden (e.g. behind the camera notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMenuAtPointer()
        return false
    }

    func showMenuAtPointer() { controls.show() }

    // MARK: - Windows

    @objc private func screensChanged() { buildWindows() }

    private func buildWindows() {
        overlay?.orderOut(nil)
        backdrop?.orderOut(nil)
        overlay = nil
        backdrop = nil
        scene = nil

        // The main screen (the one with the menu bar).
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let local = NSRect(origin: .zero, size: frame.size)

        let back = BackdropWindow(frame: frame)
        let backView = SKView(frame: local)
        backView.allowsTransparency = true
        backView.preferredFramesPerSecond = 30
        back.contentView = backView
        backdrop = back
        backdropView = backView
        showBackdrop(animated: false)

        let panel = OverlayPanel(frame: frame)
        let view = OverlaySKView(frame: local)
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        let groundY = screen.visibleFrame.minY - frame.minY
        let topInset = frame.maxY - screen.visibleFrame.maxY
        let s = WinterScene(size: frame.size, groundY: groundY, topInset: topInset)
        s.onMenuRequest = { [weak self] in self?.showMenuAtPointer() }
        view.presentScene(s)
        panel.contentView = view
        panel.orderFrontRegardless()
        overlay = panel
        scene = s

        let probeWin = NSWindow(contentRect: NSRect(x: frame.maxX - 2, y: frame.minY, width: 2, height: 2),
                                styleMask: .borderless, backing: .buffered, defer: false)
        probeWin.isOpaque = false
        probeWin.backgroundColor = NSColor(white: 0, alpha: 0.01)
        probeWin.ignoresMouseEvents = true
        probeWin.level = .statusBar
        probeWin.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        probeWin.isReleasedWhenClosed = false
        probeWin.orderFrontRegardless()
        probe?.orderOut(nil)
        probe = probeWin
    }

    private func showBackdrop(animated: Bool) {
        guard let back = backdrop, let view = backdropView else { return }
        let theme = settings.backdrop
        if theme == .off {
            back.orderOut(nil)
            view.presentScene(nil)
            return
        }
        let scene = BackdropScene(size: back.frame.size, theme: theme)
        if animated && back.isVisible {
            view.presentScene(scene, transition: .crossFade(withDuration: 0.8))
        } else {
            view.presentScene(scene)
        }
        back.orderFrontRegardless()
    }

    /// Make the overlay clickable only where there's something to click.
    @objc private func pollMouse() {
        guard let panel = overlay, let scene = scene else { return }
        if let probe {
            let visible = probe.occlusionState.contains(.visible)
            if visible { probeWorks = true }
            let onFullScreenSpace = probeWorks && !visible
            if scene.systemFullScreen != onFullScreenSpace { scene.systemFullScreen = onFullScreenSpace }
        }
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x - panel.frame.minX, y: m.y - panel.frame.minY)
        let hit = panel.frame.contains(m) && scene.isInteractive(at: p)
        if panel.ignoresMouseEvents == hit { panel.ignoresMouseEvents = !hit }
    }

    // MARK: - Menu bar icon and controls window

    private let controls = ControlsWindow()

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "WinterDesk") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "❄︎"
            }
            button.target = self
            button.action = #selector(openControls)
        }
        statusItem = item

        let m = controls.model
        m.applyScene = { [weak self] in self?.scene?.applySettings() }
        m.applyBackdrop = { [weak self] in self?.showBackdrop(animated: true) }
        m.reelInTrams = { [weak self] in self?.scene?.removeTramLines() }
        m.shakeSnow = { [weak self] in self?.scene?.shakeAllWindows() }
        m.clearLights = { [weak self] in self?.scene?.clearTreeLights() }
    }

    @objc private func openControls() { controls.show() }

}
