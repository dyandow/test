import Foundation

/// How a snowman is dressed. New snowmen copy the last style you picked.
struct SnowmanStyle: Equatable {
    enum Hat: String, CaseIterable { case topHat, santa, beanie, earmuffs, bucket, none }
    enum Face: String, CaseIterable { case classic, happy, wink, cool, surprised, sleepy, grumpy, inLove }
    enum Outfit: String, CaseIterable { case redScarf, greenScarf, stripedScarf, bowTie, none }
    enum Arms: String, CaseIterable { case sticks, waving, mittens, none }

    var hat: Hat = .topHat
    var face: Face = .classic
    var outfit: Outfit = .redScarf
    var arms: Arms = .sticks

    static func random() -> SnowmanStyle {
        SnowmanStyle(hat: Hat.allCases.filter { $0 != .none }.randomElement()!,
                     face: Face.allCases.randomElement()!,
                     outfit: Outfit.allCases.filter { $0 != .none }.randomElement()!,
                     arms: Arms.allCases.filter { $0 != .none }.randomElement()!)
    }

    var dictionary: [String: String] {
        ["hat": hat.rawValue, "face": face.rawValue, "outfit": outfit.rawValue, "arms": arms.rawValue]
    }

    init(hat: Hat = .topHat, face: Face = .classic, outfit: Outfit = .redScarf, arms: Arms = .sticks) {
        self.hat = hat; self.face = face; self.outfit = outfit; self.arms = arms
    }

    init(dictionary d: [String: String]) {
        hat = Hat(rawValue: d["hat"] ?? "") ?? .topHat
        face = Face(rawValue: d["face"] ?? "") ?? .classic
        outfit = Outfit(rawValue: d["outfit"] ?? "") ?? .redScarf
        arms = Arms(rawValue: d["arms"] ?? "") ?? .sticks
    }
}

extension SnowmanStyle.Hat {
    var title: String {
        switch self {
        case .topHat: return "Top Hat"
        case .santa: return "Santa"
        case .beanie: return "Beanie"
        case .earmuffs: return "Earmuffs"
        case .bucket: return "Bucket"
        case .none: return "None"
        }
    }
    var icon: String {
        switch self {
        case .topHat: return "🎩"
        case .santa: return "🎅"
        case .beanie: return "🧶"
        case .earmuffs: return "🎧"
        case .bucket: return "🪣"
        case .none: return "⛄️"
        }
    }
}

extension SnowmanStyle.Face {
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .happy: return "Happy"
        case .wink: return "Wink"
        case .cool: return "Cool"
        case .surprised: return "Surprised"
        case .sleepy: return "Sleepy"
        case .grumpy: return "Grumpy"
        case .inLove: return "In Love"
        }
    }
    var icon: String {
        switch self {
        case .classic: return "🙂"
        case .happy: return "😄"
        case .wink: return "😉"
        case .cool: return "😎"
        case .surprised: return "😮"
        case .sleepy: return "😴"
        case .grumpy: return "😠"
        case .inLove: return "😍"
        }
    }
}

extension SnowmanStyle.Outfit {
    var title: String {
        switch self {
        case .redScarf: return "Red Scarf"
        case .greenScarf: return "Green Scarf"
        case .stripedScarf: return "Striped"
        case .bowTie: return "Bow Tie"
        case .none: return "None"
        }
    }
    var icon: String {
        switch self {
        case .redScarf: return "🧣"
        case .greenScarf: return "💚"
        case .stripedScarf: return "🍬"
        case .bowTie: return "🎀"
        case .none: return "⚪️"
        }
    }
}

extension SnowmanStyle.Arms {
    var title: String {
        switch self {
        case .sticks: return "Sticks"
        case .waving: return "Waving"
        case .mittens: return "Mittens"
        case .none: return "None"
        }
    }
    var icon: String {
        switch self {
        case .sticks: return "🌿"
        case .waving: return "👋"
        case .mittens: return "🧤"
        case .none: return "⚪️"
        }
    }
}
