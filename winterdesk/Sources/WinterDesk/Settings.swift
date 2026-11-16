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
    var dimBackground: Bool {
        get { bool("dimBackground", true) }
        set { defaults.set(newValue, forKey: "dimBackground") }
    }
    var snowOnWindows: Bool {
        get { bool("snowOnWindows", true) }
        set { defaults.set(newValue, forKey: "snowOnWindows") }
    }
    var showTrain: Bool {
        get { bool("showTrain", true) }
        set { defaults.set(newValue, forKey: "showTrain") }
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
