import Foundation

enum SnowAmount: Int, CaseIterable {
    case light, medium, blizzard

    var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .blizzard: return "Blizzard"
        }
    }

    var flakesPerSecond: Double {
        switch self {
        case .light: return 25
        case .medium: return 55
        case .blizzard: return 130
        }
    }
}

enum Backdrop: String, CaseIterable {
    case off, dim, cabin, fireplace, village, aurora

    var title: String {
        switch self {
        case .off: return "Off (My Wallpaper)"
        case .dim: return "Dimmed Wallpaper"
        case .cabin: return "Snowy Cabin"
        case .fireplace: return "Cozy Fireplace"
        case .village: return "Winter Village Lights"
        case .aurora: return "Northern Lights"
        }
    }
}

enum FullScreenMode: String, CaseIterable {
    case hideAll, snowOnly, keepAll

    var title: String {
        switch self {
        case .hideAll: return "Hide Everything"
        case .snowOnly: return "Keep Just the Snow"
        case .keepAll: return "Keep Everything"
        }
    }
}

/// Everything the app remembers between launches.
@MainActor
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    var snowEnabled: Bool {
        get { bool("snowEnabled", true) }
        set { defaults.set(newValue, forKey: "snowEnabled") }
    }
    var snowAmount: SnowAmount {
        get { SnowAmount(rawValue: defaults.object(forKey: "snowAmount") as? Int ?? 1) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "snowAmount") }
    }
    var backdrop: Backdrop {
        get {
            if let raw = defaults.string(forKey: "backdrop"), let b = Backdrop(rawValue: raw) { return b }
            return bool("dimBackground", true) ? .dim : .off
        }
        set { defaults.set(newValue.rawValue, forKey: "backdrop") }
    }
    var weddingTrain: Bool {
        get { bool("weddingTrain", false) }
        set { defaults.set(newValue, forKey: "weddingTrain") }
    }
    /// What to show while another app is full screen.
    var fullScreenMode: FullScreenMode {
        get { FullScreenMode(rawValue: defaults.string(forKey: "fullScreenMode") ?? "") ?? .hideAll }
        set { defaults.set(newValue.rawValue, forKey: "fullScreenMode") }
    }
    var snowOnWindows: Bool {
        get { bool("snowOnWindows", true) }
        set { defaults.set(newValue, forKey: "snowOnWindows") }
    }
    var showTrain: Bool {
        get { bool("showTrain", true) }
        set { defaults.set(newValue, forKey: "showTrain") }
    }
    var showTramStation: Bool {
        get { bool("showTramStation", true) }
        set { defaults.set(newValue, forKey: "showTramStation") }
    }
    var showSnowmen: Bool {
        get { bool("showSnowmen", true) }
        set { defaults.set(newValue, forKey: "showSnowmen") }
    }
    var showSled: Bool {
        get { bool("showSled", true) }
        set { defaults.set(newValue, forKey: "showSled") }
    }
    var santaFlies: Bool {
        get { bool("santaFlies", true) }
        set { defaults.set(newValue, forKey: "santaFlies") }
    }
    var santaPresents: Bool {
        get { bool("santaPresents", true) }
        set { defaults.set(newValue, forKey: "santaPresents") }
    }
    var snowmanStyle: SnowmanStyle {
        get { SnowmanStyle(dictionary: defaults.dictionary(forKey: "snowmanStyle") as? [String: String] ?? [:]) }
        set { defaults.set(newValue.dictionary, forKey: "snowmanStyle") }
    }
    var showTree: Bool {
        get { bool("showTree", true) }
        set { defaults.set(newValue, forKey: "showTree") }
    }

    var treePosition: CGPoint? {
        get {
            guard let a = defaults.array(forKey: "treePosition") as? [Double], a.count == 2 else { return nil }
            return CGPoint(x: a[0], y: a[1])
        }
        set {
            if let p = newValue { defaults.set([Double(p.x), Double(p.y)], forKey: "treePosition") }
            else { defaults.removeObject(forKey: "treePosition") }
        }
    }
    /// Each light is [x, y, colorIndex] in tree coordinates.
    var treeLights: [[Double]] {
        get { defaults.array(forKey: "treeLights") as? [[Double]] ?? [] }
        set { defaults.set(newValue, forKey: "treeLights") }
    }
    /// Each tram line is the [x, y] of its far end; all lines start at the station.
    var tramEnds: [[Double]] {
        get { defaults.array(forKey: "tramEnds") as? [[Double]] ?? [] }
        set { defaults.set(newValue, forKey: "tramEnds") }
    }
}
