import AppKit
import ServiceManagement
import SwiftUI

enum SnowChoice: String, CaseIterable, Identifiable {
    case off, light, medium, blizzard
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The settings shown in the little WinterDesk window. Changes save and apply right away.
@MainActor
final class ControlsModel: ObservableObject {
    private let s = Settings.shared
    var applyScene: () -> Void = {}
    var applyBackdrop: () -> Void = {}
    var reelInTrams: () -> Void = {}
    var shakeSnow: () -> Void = {}
    var clearLights: () -> Void = {}
    var buildSnowman: () -> Void = {}

    @Published var backdrop: Backdrop { didSet { s.backdrop = backdrop; applyBackdrop() } }
    @Published var snow: SnowChoice {
        didSet {
            s.snowEnabled = snow != .off
            switch snow {
            case .off: break
            case .light: s.snowAmount = .light
            case .medium: s.snowAmount = .medium
            case .blizzard: s.snowAmount = .blizzard
            }
            applyScene()
        }
    }
    @Published var snowOnWindows: Bool { didSet { s.snowOnWindows = snowOnWindows; applyScene() } }
    @Published var showTrain: Bool { didSet { s.showTrain = showTrain; applyScene() } }
    @Published var weddingTrain: Bool { didSet { s.weddingTrain = weddingTrain; applyScene() } }
    @Published var showTree: Bool { didSet { s.showTree = showTree; applyScene() } }
    @Published var showSnowmen: Bool { didSet { s.showSnowmen = showSnowmen; applyScene() } }
    @Published var showSled: Bool { didSet { s.showSled = showSled; applyScene() } }
    @Published var showTramStation: Bool { didSet { s.showTramStation = showTramStation; applyScene() } }
    @Published var fullScreenMode: FullScreenMode { didSet { s.fullScreenMode = fullScreenMode; applyScene() } }
    @Published var openAtLogin: Bool {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                loginError = "Open at Login works when WinterDesk is in your Applications folder."
            }
        }
    }
    @Published var loginError: String?

    init() {
        backdrop = s.backdrop
        if !s.snowEnabled {
            snow = .off
        } else {
            switch s.snowAmount {
            case .light: snow = .light
            case .medium: snow = .medium
            case .blizzard: snow = .blizzard
            }
        }
        snowOnWindows = s.snowOnWindows
        showTrain = s.showTrain
        weddingTrain = s.weddingTrain
        showTree = s.showTree
        showTramStation = s.showTramStation
        showSnowmen = s.showSnowmen
        showSled = s.showSled
        fullScreenMode = s.fullScreenMode
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Pick up changes made elsewhere (e.g. clicking the train toggles the wedding train).
    func refresh() {
        if weddingTrain != s.weddingTrain { weddingTrain = s.weddingTrain }
    }
}

struct ControlsView: View {
    @ObservedObject var model: ControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                Picker("Background", selection: $model.backdrop) {
                    ForEach(Backdrop.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Snow", selection: $model.snow) {
                    ForEach(SnowChoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Full-screen apps", selection: $model.fullScreenMode) {
                    ForEach(FullScreenMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Snow piles on windows", isOn: $model.snowOnWindows)
                Toggle("Train", isOn: $model.showTrain)
                Toggle("Wedding train", isOn: $model.weddingTrain)
                Toggle("Christmas tree", isOn: $model.showTree)
                Toggle("Tram station", isOn: $model.showTramStation)
                Toggle("Snowmen (hold ⌥ Option, sweep along the bottom of the screen)", isOn: $model.showSnowmen)
                Toggle("Sled", isOn: $model.showSled)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button("Build a Snowman") { model.buildSnowman() }
                    Button("Shake Off Snow") { model.shakeSnow() }
                }
                HStack(spacing: 8) {
                    Button("Reel In Trams") { model.reelInTrams() }
                    Button("Clear Lights") { model.clearLights() }
                }
            }
            .controlSize(.small)

            Divider()

            HStack {
                Toggle("Open at login", isOn: $model.openAtLogin)
                Spacer()
                Button("Quit WinterDesk") { NSApp.terminate(nil) }
            }
            if let err = model.loginError {
                Text(err).font(.caption).foregroundStyle(.secondary)
            }
            Text("Open this window again by clicking the tree's star or the tram station at the top of the screen, or from Spotlight (⌘ Space, type WinterDesk).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 360)
    }
}

/// A small floating window holding the controls.
@MainActor
final class ControlsWindow {
    let model = ControlsModel()
    private var window: NSPanel?

    func show() {
        model.refresh()
        let panel: NSPanel
        if let w = window {
            panel = w
        } else {
            panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "WinterDesk"
            panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: ControlsView(model: model))
            window = panel
        }
        // Open near the pointer, kept on screen.
        let m = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = CGPoint(x: m.x - size.width / 2, y: m.y - size.height - 20)
        if let vf = NSScreen.screens.first?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 10), vf.maxX - size.width - 10)
            origin.y = min(max(origin.y, vf.minY + 10), vf.maxY - size.height - 10)
        }
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
