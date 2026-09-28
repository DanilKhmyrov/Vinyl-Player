import AppKit

enum EqualizerMode: String, CaseIterable {
    case level
    case spectrum

    var name: String {
        switch self {
        case .level: return L.t("Громкость (L/R)", "Level (L/R)")
        case .spectrum: return L.t("Спектр", "Spectrum")
        }
    }
}

enum EqualizerStyle: String, CaseIterable {
    case hifi
    case minimal
    case bar
    case dots
    case needle

    var name: String {
        switch self {
        case .hifi: return L.t("Хай-фай", "Hi-fi")
        case .minimal: return L.t("Минимал", "Minimal")
        case .bar: return L.t("Полоса", "Bar")
        case .dots: return L.t("Точки", "Dots")
        case .needle: return L.t("Стрелка", "Needle")
        }
    }

    var usesAccent: Bool {
        switch self {
        case .bar, .dots: return true
        case .hifi, .minimal, .needle: return false
        }
    }

    var housingPadding: CGFloat {
        switch self {
        case .hifi: return 4
        case .minimal, .bar, .dots, .needle: return 0
        }
    }
}

final class EqualizerView: NSView {

    static let glowMargin: CGFloat = 6
    private static let columnGap: CGFloat = 3

    static func windowSize(for visible: CGSize) -> CGSize {
        CGSize(width: visible.width + glowMargin * 2, height: visible.height + glowMargin * 2)
    }

    var style: EqualizerStyle
    var accentColor: NSColor
    private let columnCount: Int
    private let standalone: Bool
    var isDraggable: Bool { standalone }
    var onMoved: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard isDraggable else { return }
        window?.performDrag(with: event)
        onMoved?()
    }

    private var hoverArea: NSTrackingArea?
    private var housing: CALayer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard standalone else { return }
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    private func setHovered(_ hovered: Bool) {
        guard standalone, let housing else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        housing.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.30 : 0.10).cgColor
        housing.backgroundColor = NSColor.black.withAlphaComponent(
            hovered ? 0.52 : (style == .hifi ? 0.55 : 0.42)).cgColor
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private struct Column {
        var dark: [CALayer] = []
        var lit: [CALayer] = []
        var fill: CALayer?
        var marker: CALayer?
        var peakMarker: CALayer?
        var rect: CGRect = .zero
        var peak: Float = 0
    }
    private var columns: [Column] = []
    private static let peakFall: Float = 0.012

    init(frame: NSRect, style: EqualizerStyle, accentColor: NSColor, columns: Int,
         standalone: Bool = false) {
        self.style = style
        self.accentColor = accentColor
        self.columnCount = max(1, columns)
        self.standalone = standalone
        super.init(frame: frame)
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    private var panel: CGRect { bounds.insetBy(dx: Self.glowMargin, dy: Self.glowMargin) }

    private var tint: NSColor {
        switch style {
        case .hifi: return NSColor(red: 1.00, green: 0.72, blue: 0.28, alpha: 1)
        case .minimal, .needle: return .white
        case .bar, .dots: return accentColor
        }
    }

    private func build() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        columns.removeAll()
        guard let root = layer, panel.width > 0, panel.height > 0 else { return }

        let housed = style == .hifi || standalone
        if housed {
            let glass = CALayer()
            glass.frame = panel
            glass.backgroundColor = NSColor.black.withAlphaComponent(
                style == .hifi ? 0.55 : 0.42).cgColor
            glass.cornerRadius = standalone ? 8 : 4
            glass.borderWidth = 1
            glass.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
            root.addSublayer(glass)
            housing = glass
        } else {
            housing = nil
        }

        let pad = housed ? max(style.housingPadding, standalone ? 8 : 4) : 0
        let inner = panel.insetBy(dx: pad, dy: pad)
        let gap = columnCount > 1 ? Self.columnGap : 0
        let width = (inner.width - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        guard width > 0 else { return }

        for i in 0..<columnCount {
            let rect = CGRect(x: inner.minX + CGFloat(i) * (width + gap), y: inner.minY,
                              width: width, height: inner.height)
            var column = Column()
            column.rect = rect
            switch style {
            case .hifi:
                ladder(root, &column, count: 14, gap: 2, widthFraction: 1,
                       radius: 1, offAlpha: 0.05, glow: 5)
            case .minimal:
                ladder(root, &column, count: 22, gap: 3, widthFraction: 0.64,
                       radius: nil, offAlpha: 0.06, glow: 0)
            case .bar:
                buildBar(root, &column)
            case .dots:
                buildDots(root, &column)
            case .needle:
                buildNeedle(root, &column)
            }
            columns.append(column)
        }
    }

    private func ladder(_ root: CALayer, _ column: inout Column, count: Int, gap: CGFloat,
                        widthFraction: CGFloat, radius: CGFloat?, offAlpha: CGFloat, glow: CGFloat) {
        let rect = column.rect
        let h = (rect.height - gap * CGFloat(count - 1)) / CGFloat(count)
        guard h > 0 else { return }
        let w = rect.width * widthFraction
        let x = rect.midX - w / 2
        let colour = tint

        for i in 0..<count {
            let cell = CGRect(x: x, y: rect.minY + CGFloat(i) * (h + gap), width: w, height: h)
            let r = radius ?? min(2, h * 0.3)

            let off = CALayer()
            off.frame = cell
            off.cornerRadius = r
            off.backgroundColor = NSColor.white.withAlphaComponent(offAlpha).cgColor
            root.addSublayer(off)
            column.dark.append(off)

            let on = CALayer()
            on.frame = cell
            on.cornerRadius = r
            on.backgroundColor = colour.cgColor
            if glow > 0 {
                on.shadowColor = colour.cgColor
                on.shadowRadius = glow
                on.shadowOpacity = 1
                on.shadowOffset = .zero
                on.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: cell.size),
                                       cornerWidth: r, cornerHeight: r, transform: nil)
            }
            on.opacity = 0
            root.addSublayer(on)
            column.lit.append(on)
        }
    }

    private func buildBar(_ root: CALayer, _ column: inout Column) {
        let rect = column.rect
        let rail = CALayer()
        rail.frame = rect
        rail.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        rail.cornerRadius = rect.width / 2
        rail.masksToBounds = true
        root.addSublayer(rail)

        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        gradient.colors = [(tint.blended(withFraction: 0.5, of: .black) ?? tint).cgColor,
                           tint.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.anchorPoint = CGPoint(x: 0.5, y: 0)
        gradient.position = CGPoint(x: rect.width / 2, y: 0)
        gradient.transform = CATransform3DMakeScale(1, 0.001, 1)
        rail.addSublayer(gradient)
        column.fill = gradient

        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: rect.width, height: 2)
        line.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        line.opacity = 0
        rail.addSublayer(line)
        column.peakMarker = line
    }

    private func buildDots(_ root: CALayer, _ column: inout Column) {
        let rect = column.rect
        let d = rect.width * 0.74
        let gap: CGFloat = max(3, d * 0.30)
        let count = max(4, Int((rect.height + gap) / (d + gap)))
        let total = CGFloat(count) * d + CGFloat(count - 1) * gap
        let start = rect.minY + (rect.height - total) / 2
        let x = rect.midX - d / 2
        let colour = tint

        for i in 0..<count {
            let cell = CGRect(x: x, y: start + CGFloat(i) * (d + gap), width: d, height: d)

            let off = CALayer()
            off.frame = cell
            off.cornerRadius = d / 2
            off.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            root.addSublayer(off)
            column.dark.append(off)

            let on = CALayer()
            on.frame = cell
            on.cornerRadius = d / 2
            on.backgroundColor = colour.cgColor
            on.shadowColor = colour.cgColor
            on.shadowRadius = d * 0.45
            on.shadowOpacity = 1
            on.shadowOffset = .zero
            on.shadowPath = CGPath(ellipseIn: CGRect(origin: .zero, size: cell.size), transform: nil)
            on.opacity = 0
            root.addSublayer(on)
            column.lit.append(on)
        }
    }

    private func buildNeedle(_ root: CALayer, _ column: inout Column) {
        let rect = column.rect
        let trackWidth = max(1.5, rect.width * 0.10)
        let track = CALayer()
        track.frame = CGRect(x: rect.midX - trackWidth / 2, y: rect.minY,
                             width: trackWidth, height: rect.height)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        track.cornerRadius = trackWidth / 2
        root.addSublayer(track)

        let height: CGFloat = 3
        let pointer = CALayer()
        pointer.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
        pointer.cornerRadius = height / 2
        pointer.backgroundColor = tint.cgColor
        pointer.shadowColor = tint.cgColor
        pointer.shadowRadius = 4
        pointer.shadowOpacity = 1
        pointer.shadowOffset = .zero
        pointer.shadowPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: rect.width, height: height),
                                    cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
        root.addSublayer(pointer)
        column.marker = pointer

        let hold = CALayer()
        hold.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1.5)
        hold.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        root.addSublayer(hold)
        column.peakMarker = hold
    }

    override func layout() {
        super.layout()
        build()
    }

    func refreshColors() {
        let colour = tint.cgColor
        for column in columns {
            for segment in column.lit {
                segment.backgroundColor = colour
                segment.shadowColor = colour
            }
            if let gradient = column.fill as? CAGradientLayer {
                gradient.colors = [(tint.blended(withFraction: 0.5, of: .black) ?? tint).cgColor,
                                   colour]
            }
            column.marker?.backgroundColor = colour
            column.marker?.shadowColor = colour
        }
    }

    func update(levels: [Float]) {
        guard !columns.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for i in columns.indices {
            let level = i < levels.count ? levels[i] : 0
            columns[i].peak = max(level, columns[i].peak - Self.peakFall)
            drive(columns[i], level: level)
        }
    }

    private func drive(_ column: Column, level: Float) {
        switch style {
        case .hifi, .minimal, .dots:
            guard !column.lit.isEmpty else { return }
            let reach = level * Float(column.lit.count)
            for (i, segment) in column.lit.enumerated() {
                let index = Float(i)
                if index + 1 <= reach { segment.opacity = 1 }
                else if index < reach { segment.opacity = reach - index }
                else { segment.opacity = 0 }
            }
        case .bar:
            column.fill?.transform = CATransform3DMakeScale(1, max(0.001, CGFloat(level)), 1)
            column.peakMarker?.opacity = column.peak > 0.02 ? 1 : 0
            column.peakMarker?.frame.origin.y = column.rect.height * CGFloat(column.peak) - 2
        case .needle:
            let travel = column.rect.height - 3
            column.marker?.frame.origin.y = column.rect.minY + travel * CGFloat(level)
            column.peakMarker?.frame.origin.y = column.rect.minY + travel * CGFloat(column.peak)
            column.peakMarker?.opacity = column.peak > 0.02 ? 1 : 0
        }
    }
}
