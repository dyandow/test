import AppKit
import ServiceManagement
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var overlay: OverlayPanel?
    private var backdrop: BackdropWindow?
    private var scene: WinterScene?
    private var statusItem: NSStatusItem?
    private var mouseTimer: Timer?
    private let menu = NSMenu()

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
        backView.presentScene(BackdropScene(size: frame.size))
        back.contentView = backView
        backdrop = back
        if settings.dimBackground { back.orderFrontRegardless() }

        let panel = OverlayPanel(frame: frame)
        let view = OverlaySKView(frame: local)
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        let groundY = screen.visibleFrame.minY - frame.minY
        let topInset = frame.maxY - screen.visibleFrame.maxY
        let s = WinterScene(size: frame.size, groundY: groundY, topInset: topInset)
        view.presentScene(s)
        panel.contentView = view
        panel.orderFrontRegardless()
        overlay = panel
        scene = s
    }

    /// Make the overlay clickable only where there's something to click.
    @objc private func pollMouse() {
        guard let panel = overlay, let scene = scene else { return }
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x - panel.frame.minX, y: m.y - panel.frame.minY)
        let hit = panel.frame.contains(m) && scene.isInteractive(at: p)
        if panel.ignoresMouseEvents == hit { panel.ignoresMouseEvents = !hit }
    }

    // MARK: - Menu bar

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "WinterDesk") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "❄︎"
            }
        }
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        func toggle(_ title: String, _ on: Bool, _ action: Selector) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            i.state = on ? .on : .off
            menu.addItem(i)
        }
        func button(_ title: String, _ action: Selector, key: String = "") {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            menu.addItem(i)
        }

        toggle("Snowfall", settings.snowEnabled, #selector(toggleSnow))
        let amount = NSMenuItem(title: "Snow Amount", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for a in SnowAmount.allCases {
            let i = NSMenuItem(title: a.title, action: #selector(setAmount(_:)), keyEquivalent: "")
            i.target = self
            i.tag = a.rawValue
            i.state = settings.snowAmount == a ? .on : .off
            sub.addItem(i)
        }
        amount.submenu = sub
        menu.addItem(amount)
        toggle("Snow Piles on Windows", settings.snowOnWindows, #selector(toggleWindowSnow))
        toggle("Dim Background", settings.dimBackground, #selector(toggleDim))
        toggle("Train", settings.showTrain, #selector(toggleTrain))
        toggle("Christmas Tree", settings.showTree, #selector(toggleTree))
        menu.addItem(.separator())
        button("Shake Snow Off All Windows", #selector(shakeAll))
        button("Clear Tree Lights", #selector(clearLights))
        button("Remove Tram Lines", #selector(removeTrams))
        menu.addItem(.separator())
        toggle("Open at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin))
        button("How to Play…", #selector(showHelp))
        button("Quit WinterDesk", #selector(quit), key: "q")
    }

    @objc private func toggleSnow() { settings.snowEnabled.toggle() }
    @objc private func setAmount(_ sender: NSMenuItem) {
        settings.snowAmount = SnowAmount(rawValue: sender.tag) ?? .medium
    }
    @objc private func toggleWindowSnow() { settings.snowOnWindows.toggle(); scene?.applySettings() }
    @objc private func toggleDim() {
        settings.dimBackground.toggle()
        if settings.dimBackground { backdrop?.orderFrontRegardless() } else { backdrop?.orderOut(nil) }
    }
    @objc private func toggleTrain() { settings.showTrain.toggle(); scene?.applySettings() }
    @objc private func toggleTree() { settings.showTree.toggle(); scene?.applySettings() }
    @objc private func shakeAll() { scene?.shakeAllWindows() }
    @objc private func clearLights() { scene?.clearTreeLights() }
    @objc private func removeTrams() { scene?.removeTramLines() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change Open at Login",
                  "This works when WinterDesk is run as WinterDesk.app (see the README).\n\n\(error.localizedDescription)")
        }
    }

    @objc private func showHelp() {
        alert("How to play", """
        • Snow settles on top of your windows. Shake a window quickly back and forth to knock it off.
        • The train plows the snow along the bottom. Click it to blow the whistle.
        • Drag the tree anywhere. Click its branches to hang lights; click a light to take it off.
        • Drag from the little station at the top of the screen and let go anywhere to string a cable. A red tram rides it.
        • Drag a cable's end post to move it; right-click it to remove the cable.
        """)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
