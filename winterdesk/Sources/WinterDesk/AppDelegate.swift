import AppKit
import ServiceManagement
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var overlay: OverlayPanel?
    private var backdrop: BackdropWindow?
    private var backdropView: SKView?
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

    /// Opening the app again while it's running pops up the menu right at the pointer,
    /// in case the menu bar icon is hidden (e.g. behind the camera notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMenuAtPointer()
        return false
    }

    func showMenuAtPointer() {
        NSApp.activate(ignoringOtherApps: true)
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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

        func item(_ title: String, _ action: Selector?, on: Bool? = nil, key: String = "",
                  value: String? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            i.representedObject = value
            if let on { i.state = on ? .on : .off }
            return i
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            items.forEach(sub.addItem)
            parent.submenu = sub
            menu.addItem(parent)
        }

        submenu("Snow", [item("Snowfall", #selector(toggleSnow), on: settings.snowEnabled), .separator()]
            + SnowAmount.allCases.map { item($0.title, #selector(setAmount(_:)), on: settings.snowAmount == $0, value: String($0.rawValue)) }
            + [.separator(),
               item("Piles on Windows", #selector(toggleWindowSnow), on: settings.snowOnWindows),
               item("Shake Off All Windows", #selector(shakeAll))])

        submenu("Background", Backdrop.allCases.map {
            item($0.title, #selector(setBackdrop(_:)), on: settings.backdrop == $0, value: $0.rawValue)
        } + [.separator(), item("Next Background", #selector(nextBackdrop))])

        submenu("Train", [item("Show Train", #selector(toggleTrain), on: settings.showTrain),
                          item("Wedding Train", #selector(toggleWedding), on: settings.weddingTrain)])

        submenu("Tree", [item("Show Tree", #selector(toggleTree), on: settings.showTree),
                         item("Clear Lights", #selector(clearLights))])

        menu.addItem(item("Remove Tram Lines", #selector(removeTrams)))

        submenu("When an App Is Full Screen", FullScreenMode.allCases.map {
            item($0.title, #selector(setFullScreenMode(_:)), on: settings.fullScreenMode == $0, value: $0.rawValue)
        })

        menu.addItem(.separator())
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("How to Play…", #selector(showHelp)))
        menu.addItem(item("Quit WinterDesk", #selector(quit), key: "q"))
    }

    @objc private func toggleSnow() { settings.snowEnabled.toggle() }
    @objc private func setAmount(_ sender: NSMenuItem) {
        settings.snowAmount = SnowAmount(rawValue: Int(sender.representedObject as? String ?? "") ?? 1) ?? .medium
    }
    @objc private func toggleWindowSnow() { settings.snowOnWindows.toggle(); scene?.applySettings() }
    @objc private func setFullScreenMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = FullScreenMode(rawValue: raw) else { return }
        settings.fullScreenMode = m
        scene?.applySettings()
    }
    @objc private func setBackdrop(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let b = Backdrop(rawValue: raw) else { return }
        settings.backdrop = b
        showBackdrop(animated: true)
    }
    @objc private func nextBackdrop() {
        let all = Backdrop.allCases
        let i = all.firstIndex(of: settings.backdrop) ?? 0
        settings.backdrop = all[(i + 1) % all.count]
        showBackdrop(animated: true)
    }
    @objc private func toggleWedding() { settings.weddingTrain.toggle(); scene?.applySettings() }
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
        • The train plows the snow along the bottom. Click it to turn it into the wedding train (and click again to turn it back).
        • Right-click the tree (or open WinterDesk again) to get this menu anywhere.
        • Drag the tree anywhere. Click its branches to hang lights; click a light to take it off.
        • Drag from the little station at the top of the screen and let go anywhere to string a cable. A red tram rides it.
        • Click the tram car to reel it back into the station. Drag a cable's end post to move it.
        • Pick a background (fireplace, winter village, northern lights…) from the ❄ menu.
        • Choose what stays on screen when an app goes full screen from the ❄ menu.
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
