import AppKit
import QuartzCore

enum CrateStyle: String, CaseIterable {
    case rack
    case fan
    case spines

    var name: String {
        switch self {
        case .rack: return L.t("Полка", "Shelf")
        case .fan: return L.t("Веер", "Fan")
        case .spines: return L.t("Корешки", "Spines")
        }
    }

    var usesReflections: Bool { self == .rack }
}

final class CrateView: NSView {

    var contextMenuProvider: (() -> NSMenu)?
    var onSelectCard: ((Int) -> Void)?

    private let stage = CALayer()
    private var cards: [CALayer] = []
    private var shades: [CALayer] = []
    private var mirrors: [CALayer] = []
    private let side: CGFloat
    private let depth: Int
    private let style: CrateStyle
    private let reflections: Bool
    private var covers: [CGImage] = []
    private var contentBand = CGRect.zero

    init(side: CGFloat, themeID: String, depth: Int, style: CrateStyle, reflections: Bool) {
        self.side = side
        self.depth = depth
        self.style = style
        self.reflections = reflections && style.usesReflections
        let theme = Theme.named(themeID)
        super.init(frame: NSRect(origin: .zero,
                                 size: CrateView.canvas(for: side, depth: depth, style: style,
                                                        reflections: reflections)))
        wantsLayer = true
        layer?.masksToBounds = false

        if style == .rack {
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / (side * 6.5)
            stage.sublayerTransform = perspective
        }
        stage.frame = bounds
        layer?.addSublayer(stage)

        let border = theme.sleeveEdge ?? CGColor(gray: 1, alpha: 0.28)
        let tint = theme.accent.components ?? [1, 1, 1, 1]

        for _ in 0..<depth {
            let mirror = CALayer()
            let card = CALayer()
            let shade = CALayer()
            for l in [mirror, card] {
                l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                l.contentsGravity = .resizeAspectFill
                l.masksToBounds = true
                l.cornerRadius = side * 0.012
                l.isHidden = true
            }
            card.borderWidth = max(0.5, side * 0.006)
            card.borderColor = border
            card.shadowColor = CGColor(gray: 0, alpha: 1)
            card.shadowOpacity = 0.55
            card.shadowRadius = side * 0.07
            card.shadowOffset = CGSize(width: 0, height: -side * 0.03)
            shade.backgroundColor = CGColor(gray: 0, alpha: 0)
            card.addSublayer(shade)
            mirror.opacity = 0.30
            mirror.mask = Self.fade(side: side, tint: tint)
            mirror.isHidden = true
            stage.addSublayer(mirror)
            stage.addSublayer(card)
            mirrors.append(mirror)
            cards.append(card)
            shades.append(shade)
        }
        for layer in mirrors.reversed() + cards.reversed() { stage.addSublayer(layer) }
        contentBand = Self.band(for: bounds.size, side: side, style: style)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func canvas(for side: CGFloat, depth: Int, style: CrateStyle,
                       reflections: Bool) -> CGSize {
        switch style {
        case .rack:
            return CGSize(width: side * (1.55 + 0.30 * CGFloat(depth - 1)),
                          height: side * (reflections ? 1.56 : 1.10))
        case .fan:
            let spread = 0.115 * CGFloat(max(depth - 1, 0))
            return CGSize(width: side * (1.18 + spread), height: side * 1.28)
        case .spines:
            let spineWidth = side * 0.155
            return CGSize(width: side * 1.10 + spineWidth * CGFloat(max(depth - 1, 0)),
                          height: side * 1.14)
        }
    }

    private static func band(for canvas: CGSize, side: CGFloat, style: CrateStyle) -> CGRect {
        switch style {
        case .rack:
            return CGRect(x: 0, y: canvas.height - side * 1.18, width: canvas.width,
                          height: side * 1.18)
        case .fan:
            return CGRect(x: 0, y: canvas.height - side * 1.20, width: canvas.width,
                          height: side * 1.20)
        case .spines:
            return CGRect(x: 0, y: canvas.height - side * 1.05, width: canvas.width,
                          height: side * 1.05)
        }
    }

    private static func fade(side: CGFloat, tint: [CGFloat]) -> CALayer {
        let gradient = CAGradientLayer()
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: side / 2, y: side / 2)
        gradient.colors = [
            CGColor(red: 1 * 0.55 + tint[0] * 0.45, green: 1 * 0.55 + tint[1] * 0.45,
                    blue: 1 * 0.55 + tint[2] * 0.45, alpha: 0.62),
            CGColor(gray: 1, alpha: 0),
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.72)
        return gradient
    }

    private var frontCentre: CGPoint {
        switch style {
        case .rack: return CGPoint(x: side * 0.62, y: bounds.height - side * 0.60)
        case .fan: return CGPoint(x: side * 0.58, y: bounds.height - side * 0.66)
        case .spines: return CGPoint(x: side * 0.54, y: bounds.height - side * 0.58)
        }
    }

    private func frame(_ index: Int) -> (bounds: CGRect, crop: CGRect) {
        guard style == .spines, index > 0 else {
            return (CGRect(x: 0, y: 0, width: side, height: side), CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let width = side * 0.155
        return (CGRect(x: 0, y: 0, width: width, height: side * 0.92),
               CGRect(x: 0.44, y: 0, width: 0.12, height: 1))
    }

    private func slot(_ index: Int) -> CATransform3D {
        switch style {
        case .rack: return slotRack(index)
        case .fan: return slotFan(index)
        case .spines: return slotSpine(index)
        }
    }

    private func slotRack(_ index: Int) -> CATransform3D {
        var t = CATransform3DIdentity
        guard index != 0 else { return t }
        if index < 0 {
            t = CATransform3DTranslate(t, -side * 0.55, 0, side * 0.55)
            return t
        }
        let d = CGFloat(index)
        t = CATransform3DTranslate(t, side * (0.60 + 0.30 * (d - 1)), side * 0.02 * d,
                                   -side * 0.22 * d)
        t = CATransform3DRotate(t, -62 * .pi / 180, 0, 1, 0)
        return t
    }

    private func slotFan(_ index: Int) -> CATransform3D {
        if index < 0 {
            let t = CATransform3DMakeTranslation(side * 0.30, -side * 0.42, 0)
            return CATransform3DRotate(t, -22 * .pi / 180, 0, 0, 1)
        }
        guard index != 0 else { return CATransform3DIdentity }
        let d = CGFloat(index)
        var t = CATransform3DMakeTranslation(side * 0.10 * d, -side * 0.024 * d, 0)
        t = CATransform3DRotate(t, (7.2 * .pi / 180) * d, 0, 0, 1)
        return t
    }

    private func slotSpine(_ index: Int) -> CATransform3D {
        if index < 0 { return CATransform3DMakeTranslation(0, -side * 0.5, 0) }
        guard index != 0 else { return CATransform3DIdentity }
        let spineWidth = side * 0.155
        let x = side / 2 + spineWidth * (CGFloat(index) - 0.5)
        return CATransform3DMakeTranslation(x, -(side - side * 0.92) / 2, 0)
    }

    private func shadeAlpha(_ index: Int) -> CGFloat {
        switch style {
        case .spines: return min(0.30, 0.045 * CGFloat(index))
        default: return min(0.62, 0.12 * CGFloat(index))
        }
    }

    func show(_ newCovers: [CGImage], animated: Bool) {
        let arriving = animated && newCovers.count > covers.count
            || (animated && newCovers.first !== covers.first)
        covers = Array(newCovers.prefix(depth))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, card) in cards.enumerated() {
            let mirror = mirrors[index]
            let visible = index < covers.count
            card.isHidden = !visible
            mirror.isHidden = !visible || !reflections
            guard visible else { continue }
            let (cardBounds, crop) = frame(index)
            card.bounds = cardBounds
            card.contentsRect = crop
            card.contents = covers[index]
            mirror.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            mirror.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            mirror.contents = covers[index]
            card.position = frontCentre
            mirror.position = CGPoint(x: frontCentre.x, y: frontCentre.y - side)
            let from = arriving ? slot(index - 1) : slot(index)
            card.transform = from
            mirror.transform = mirrored(from)
            shades[index].backgroundColor =
                CGColor(gray: 0, alpha: arriving ? shadeAlpha(index - 1) : shadeAlpha(index))
            shades[index].frame = cardBounds
        }
        CATransaction.commit()

        guard arriving else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.62)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(controlPoints: 0.22, 1, 0.32, 1))
        for (index, card) in cards.enumerated() where index < covers.count {
            card.transform = slot(index)
            mirrors[index].transform = mirrored(slot(index))
            shades[index].backgroundColor = CGColor(gray: 0, alpha: shadeAlpha(index))
        }
        CATransaction.commit()
    }

    private func mirrored(_ transform: CATransform3D) -> CATransform3D {
        CATransform3DConcat(transform, CATransform3DMakeScale(1, -1, 1))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for l in cards + mirrors { l.contentsScale = scale }
        show(covers, animated: false)
    }

    private var didDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !covers.isEmpty else { return nil }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        return contentBand.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { didDrag = false }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        window?.performDrag(with: event)
        Preferences.crateOrigin = window?.frame.origin
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let stagePoint = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        guard let hit = stage.hitTest(stagePoint) else { return }
        for (index, card) in cards.enumerated() where index < covers.count {
            if hit === card || hit.superlayer === card {
                onSelectCard?(index)
                flash(card)
                return
            }
        }
    }

    private func flash(_ card: CALayer) {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.06
        pulse.toValue = 1.0
        pulse.duration = 0.28
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        card.add(pulse, forKey: "vinyl.tap")
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
