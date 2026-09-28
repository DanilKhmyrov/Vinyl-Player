import AppKit

struct Accent {
    let id: String
    let name: String
    let color: CGColor?

    var localizedName: String {
        guard Preferences.language == .en else { return name }
        switch id {
        case "artwork": return "From cover"
        case "amber": return "Amber"
        case "crimson": return "Crimson"
        case "cyan": return "Cyan"
        case "lime": return "Lime"
        case "violet": return "Violet"
        default: return name
        }
    }

    static let all: [Accent] = [
        Accent(id: "artwork", name: "По обложке", color: nil),
        Accent(id: "amber", name: "Янтарь", color: CGColor(red: 1.00, green: 0.68, blue: 0.24, alpha: 1)),
        Accent(id: "crimson", name: "Малиновый", color: CGColor(red: 0.92, green: 0.20, blue: 0.34, alpha: 1)),
        Accent(id: "cyan", name: "Бирюза", color: CGColor(red: 0.24, green: 0.84, blue: 0.94, alpha: 1)),
        Accent(id: "lime", name: "Лайм", color: CGColor(red: 0.56, green: 0.86, blue: 0.28, alpha: 1)),
        Accent(id: "violet", name: "Фиолетовый", color: CGColor(red: 0.62, green: 0.40, blue: 0.96, alpha: 1)),
    ]

    static func named(_ id: String) -> Accent {
        all.first { $0.id == id } ?? all[0]
    }
}
