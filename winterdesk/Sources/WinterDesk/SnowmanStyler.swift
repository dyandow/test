import AppKit
import SwiftUI

@MainActor
final class StylerModel: ObservableObject {
    enum Tab: String, CaseIterable { case hat = "Hat", face = "Face", outfit = "Outfit", arms = "Arms" }
    @Published var tab: Tab = .face
    @Published var style = SnowmanStyle() {
        didSet { onChange(style) }
    }
    var onChange: (SnowmanStyle) -> Void = { _ in }
}

private struct OptionButton: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(icon).font(.system(size: 26))
                Text(title).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(selected ? 0.18 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

struct StylerView: View {
    @ObservedObject var model: StylerModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fashion week, but colder.").font(.headline)
                Spacer()
                Button {
                    model.style = SnowmanStyle()
                } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Back to the classic look")
                Button {
                    model.style = .random()
                } label: { Image(systemName: "dice") }
                .help("Surprise me")
            }
            Picker("", selection: $model.tab) {
                ForEach(StylerModel.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LazyVGrid(columns: columns, spacing: 8) {
                switch model.tab {
                case .hat:
                    ForEach(SnowmanStyle.Hat.allCases, id: \.self) { h in
                        OptionButton(icon: h.icon, title: h.title, selected: model.style.hat == h) { model.style.hat = h }
                    }
                case .face:
                    ForEach(SnowmanStyle.Face.allCases, id: \.self) { f in
                        OptionButton(icon: f.icon, title: f.title, selected: model.style.face == f) { model.style.face = f }
                    }
                case .outfit:
                    ForEach(SnowmanStyle.Outfit.allCases, id: \.self) { o in
                        OptionButton(icon: o.icon, title: o.title, selected: model.style.outfit == o) { model.style.outfit = o }
                    }
                case .arms:
                    ForEach(SnowmanStyle.Arms.allCases, id: \.self) { a in
                        OptionButton(icon: a.icon, title: a.title, selected: model.style.arms == a) { model.style.arms = a }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// Small floating window for dressing up the snowman you clicked.
@MainActor
final class SnowmanStyler {
    let model = StylerModel()
    private var window: NSPanel?
    private weak var current: AnyObject?

    func show(for man: Snowman) {
        current = man
        model.onChange = { _ in }
        model.style = man.style
        model.onChange = { [weak man] style in
            man?.apply(style)
            Settings.shared.snowmanStyle = style
        }
        let panel: NSPanel
        if let w = window {
            panel = w
        } else {
            panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Dress Up"
            panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: StylerView(model: model))
            window = panel
        }
        let m = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = CGPoint(x: m.x + 30, y: m.y - size.height / 2)
        if let vf = NSScreen.screens.first?.visibleFrame {
            if origin.x + size.width > vf.maxX - 10 { origin.x = m.x - size.width - 30 }
            origin.x = min(max(origin.x, vf.minX + 10), vf.maxX - size.width - 10)
            origin.y = min(max(origin.y, vf.minY + 10), vf.maxY - size.height - 10)
        }
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
