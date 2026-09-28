import AppKit

struct Theme {
    let id: String
    let name: String

    var localizedName: String {
        guard Preferences.language == .en else { return name }
        switch id {
        case "sleeve": return "Sleeve"
        case "wax": return "Colored Vinyl"
        case "picture": return "Picture Disc"
        case "marble": return "Marble"
        case "shellac": return "Shellac"
        case "splatter": return "Splatter"
        case "clear": return "Clear"
        case "galaxy": return "Galaxy"
        case "gold": return "Gold"
        default: return name
        }
    }

    enum Pressing {
        case black
        case wax
        case picture
        case marble
        case shellac
        case splatter
        case clear
        case galaxy
        case gold
    }
    let pressing: Pressing

    let sleeveBoard: CGColor
    let sleeveEdge: CGColor?
    let sleeveWear: CGFloat

    let captionScrim: CGColor
    let captionTitle: CGColor
    let captionArtist: CGColor

    let vinylCentre: CGColor
    let vinylRim: CGColor
    let secondary: CGColor
    let grooveContrast: CGFloat
    let grooveScale: CGFloat
    let sheenStrength: CGFloat
    let labelPaper: CGColor

    let accentFromArtwork: Bool
    let accent: CGColor
    let glowStrength: CGFloat

    static let all: [Theme] = [.sleeve, .wax, .picture, .marble, .splatter,
                               .clear, .galaxy, .gold, .shellac]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .sleeve
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

extension Theme {

    static let sleeve = Theme(
        id: "sleeve",
        name: "Конверт",
        pressing: .black,
        sleeveBoard: rgb(0.10, 0.10, 0.11),
        sleeveEdge: rgb(1, 1, 1, 0.14),
        sleeveWear: 0.5,
        captionScrim: rgb(0, 0, 0, 0.72),
        captionTitle: rgb(1, 1, 1, 0.94),
        captionArtist: rgb(1, 1, 1, 0.58),
        vinylCentre: rgb(0.085, 0.085, 0.093),
        vinylRim: rgb(0.105, 0.105, 0.115),
        secondary: rgb(0.92, 0.92, 0.94),
        grooveContrast: 1.0,
        grooveScale: 1.0,
        sheenStrength: 1.0,
        labelPaper: rgb(0.86, 0.84, 0.78),
        accentFromArtwork: true,
        accent: rgb(0.62, 0.22, 0.18),
        glowStrength: 1.0
    )

    static let wax = Theme(
        id: "wax",
        name: "Цветной винил",
        pressing: .wax,
        sleeveBoard: rgb(0.94, 0.92, 0.88),
        sleeveEdge: rgb(0, 0, 0, 0.18),
        sleeveWear: 0.9,
        captionScrim: rgb(0.06, 0.05, 0.05, 0.66),
        captionTitle: rgb(1, 0.99, 0.97, 0.95),
        captionArtist: rgb(1, 0.99, 0.97, 0.62),
        vinylCentre: rgb(0.30, 0.10, 0.08),
        vinylRim: rgb(0.66, 0.26, 0.17),
        secondary: rgb(0.98, 0.92, 0.86),
        grooveContrast: 1.05,
        grooveScale: 1.0,
        sheenStrength: 1.45,
        labelPaper: rgb(0.96, 0.94, 0.90),
        accentFromArtwork: true,
        accent: rgb(0.85, 0.35, 0.20),
        glowStrength: 1.5
    )

    static let picture = Theme(
        id: "picture",
        name: "Пикчер-диск",
        pressing: .picture,
        sleeveBoard: rgb(0.07, 0.07, 0.08),
        sleeveEdge: nil,
        sleeveWear: 0.2,
        captionScrim: rgb(0, 0, 0, 0.70),
        captionTitle: rgb(1, 1, 1, 0.94),
        captionArtist: rgb(1, 1, 1, 0.56),
        vinylCentre: rgb(0.09, 0.09, 0.10),
        vinylRim: rgb(0.13, 0.13, 0.15),
        secondary: rgb(0.90, 0.92, 0.96),
        grooveContrast: 0.85,
        grooveScale: 1.0,
        sheenStrength: 1.25,
        labelPaper: rgb(0.10, 0.10, 0.12),
        accentFromArtwork: true,
        accent: rgb(0.30, 0.55, 0.85),
        glowStrength: 1.2
    )

    static let marble = Theme(
        id: "marble",
        name: "Мрамор",
        pressing: .marble,
        sleeveBoard: rgb(0.11, 0.12, 0.14),
        sleeveEdge: rgb(1, 1, 1, 0.13),
        sleeveWear: 0.6,
        captionScrim: rgb(0, 0, 0, 0.72),
        captionTitle: rgb(1, 1, 1, 0.94),
        captionArtist: rgb(1, 1, 1, 0.58),
        vinylCentre: rgb(0.16, 0.17, 0.21),
        vinylRim: rgb(0.30, 0.32, 0.38),
        secondary: rgb(0.96, 0.95, 0.92),
        grooveContrast: 0.9,
        grooveScale: 1.0,
        sheenStrength: 1.25,
        labelPaper: rgb(0.93, 0.92, 0.88),
        accentFromArtwork: true,
        accent: rgb(0.45, 0.50, 0.70),
        glowStrength: 1.1
    )

    static let shellac = Theme(
        id: "shellac",
        name: "Шеллак",
        pressing: .shellac,
        sleeveBoard: rgb(0.63, 0.52, 0.38),
        sleeveEdge: rgb(0.22, 0.15, 0.09, 0.55),
        sleeveWear: 1.6,
        captionScrim: rgb(0.10, 0.07, 0.04, 0.70),
        captionTitle: rgb(1, 0.97, 0.92, 0.95),
        captionArtist: rgb(1, 0.97, 0.92, 0.62),
        vinylCentre: rgb(0.135, 0.098, 0.076),
        vinylRim: rgb(0.205, 0.150, 0.112),
        secondary: rgb(0.62, 0.13, 0.11),
        grooveContrast: 1.3,
        grooveScale: 2.3,
        sheenStrength: 0.85,
        labelPaper: rgb(0.93, 0.89, 0.78),
        accentFromArtwork: true,
        accent: rgb(0.72, 0.46, 0.22),
        glowStrength: 0.8
    )

    static let splatter = Theme(
        id: "splatter",
        name: "Брызги",
        pressing: .splatter,
        sleeveBoard: rgb(0.10, 0.11, 0.12),
        sleeveEdge: rgb(1, 1, 1, 0.13),
        sleeveWear: 0.6,
        captionScrim: rgb(0, 0, 0, 0.72),
        captionTitle: rgb(1, 1, 1, 0.94),
        captionArtist: rgb(1, 1, 1, 0.58),
        vinylCentre: rgb(0.14, 0.15, 0.18),
        vinylRim: rgb(0.26, 0.28, 0.33),
        secondary: rgb(0.97, 0.96, 0.92),
        grooveContrast: 1.0,
        grooveScale: 1.0,
        sheenStrength: 1.15,
        labelPaper: rgb(0.94, 0.93, 0.89),
        accentFromArtwork: true,
        accent: rgb(0.40, 0.52, 0.72),
        glowStrength: 1.1
    )

    static let clear = Theme(
        id: "clear",
        name: "Прозрачный",
        pressing: .clear,
        sleeveBoard: rgb(0.09, 0.10, 0.12),
        sleeveEdge: rgb(1, 1, 1, 0.15),
        sleeveWear: 0.4,
        captionScrim: rgb(0, 0, 0, 0.72),
        captionTitle: rgb(1, 1, 1, 0.94),
        captionArtist: rgb(1, 1, 1, 0.58),
        vinylCentre: rgb(0.72, 0.80, 0.88),
        vinylRim: rgb(0.86, 0.92, 1.00),
        secondary: rgb(1, 1, 1),
        grooveContrast: 1.6,
        grooveScale: 1.0,
        sheenStrength: 1.5,
        labelPaper: rgb(0.95, 0.94, 0.90),
        accentFromArtwork: true,
        accent: rgb(0.55, 0.75, 0.95),
        glowStrength: 1.0
    )

    static let galaxy = Theme(
        id: "galaxy",
        name: "Галактика",
        pressing: .galaxy,
        sleeveBoard: rgb(0.055, 0.055, 0.075),
        sleeveEdge: rgb(0.55, 0.60, 1.00, 0.22),
        sleeveWear: 0.3,
        captionScrim: rgb(0, 0, 0, 0.74),
        captionTitle: rgb(1, 1, 1, 0.95),
        captionArtist: rgb(0.78, 0.80, 1.00, 0.62),
        vinylCentre: rgb(0.055, 0.045, 0.105),
        vinylRim: rgb(0.105, 0.085, 0.185),
        secondary: rgb(0.60, 0.42, 0.95),
        grooveContrast: 0.6,
        grooveScale: 1.0,
        sheenStrength: 1.2,
        labelPaper: rgb(0.10, 0.09, 0.16),
        accentFromArtwork: true,
        accent: rgb(0.45, 0.35, 0.90),
        glowStrength: 1.4
    )

    static let gold = Theme(
        id: "gold",
        name: "Золото",
        pressing: .gold,
        sleeveBoard: rgb(0.085, 0.082, 0.078),
        sleeveEdge: rgb(1, 0.86, 0.55, 0.28),
        sleeveWear: 0.5,
        captionScrim: rgb(0.06, 0.05, 0.03, 0.72),
        captionTitle: rgb(1, 0.98, 0.94, 0.95),
        captionArtist: rgb(1, 0.90, 0.68, 0.66),
        vinylCentre: rgb(0.42, 0.31, 0.11),
        vinylRim: rgb(0.86, 0.68, 0.30),
        secondary: rgb(1.00, 0.93, 0.72),
        grooveContrast: 0.85,
        grooveScale: 1.0,
        sheenStrength: 1.7,
        labelPaper: rgb(0.11, 0.10, 0.09),
        accentFromArtwork: false,
        accent: rgb(0.95, 0.76, 0.34),
        glowStrength: 1.3
    )
}
