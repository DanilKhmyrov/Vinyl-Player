import AppKit
import QuartzCore

final class RecordView: NSView {

    struct Configuration: Equatable {
        var sleeveSide: CGFloat
        var themeID: String
        var showsCaption: Bool
        var showsProgress: Bool
        var showsTime: Bool
        var sideID: String
        var accentID: String

        var side: RecordArtwork.Side { RecordArtwork.Side(rawValue: sideID) ?? .right }

        var theme: Theme { Theme.named(themeID) }
    }

    var onToggle: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onOpenPlayer: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    private let glow = CALayer()
    private let holder = CALayer()
    private let spin = CALayer()
    private let sheen = CALayer()
    private let progressTrack = CAShapeLayer()
    private let progressArc = CAShapeLayer()
    private let sleeveOutgoing = CALayer()
    private let sleeve = CALayer()
    private let timeLabel = CATextLayer()

    private var isSpinning = false
    private var progress: Double?
    private var trackDuration: Double?
    private var ticker: Timer?
    private var artwork: NSImage?
    private var swapGeneration = 0
    private var artworkToken = 0
    private var renderGeneration = 0
    private var title: String?
    private var artist: String?
    private var accent: CGColor
    private var layout: RecordArtwork.Layout

    private static let rotationKey = "vinyl.rotation"
    private static let progressKey = "vinyl.progress"
    private static let swapDuration: CFTimeInterval = 1.1
    private static let rampKey = "vinyl.ramp"
    private static let easeInQuad = CAMediaTimingFunction(controlPoints: 0.333, 0, 0.666, 0.333)
    private static let easeOutQuad = CAMediaTimingFunction(controlPoints: 0.333, 0.666, 0.666, 1)
    private static let spinUpDuration = 1.0

    var configuration: Configuration {
        didSet {
            guard configuration != oldValue else { return }
            layout = RecordArtwork.Layout(sleeveSide: configuration.sleeveSide,
                                          side: configuration.side,
                                          crateDepth: 0)
            setFrameSize(layout.canvas)
            rebuild()
        }
    }

    var canvasSize: CGSize { layout.canvas }
    var artworkRect: CGRect { layout.sleeve }
    var fullExtentRect: CGRect {
        let radius = layout.recordDiameter / 2
        let disc = CGRect(x: layout.extended.x - radius, y: layout.extended.y - radius,
                          width: layout.recordDiameter, height: layout.recordDiameter)
        return layout.sleeve.union(disc)
    }
    var currentAccentColor: NSColor { NSColor(cgColor: accent) ?? .white }

    init(configuration: Configuration) {
        self.configuration = configuration
        layout = RecordArtwork.Layout(sleeveSide: configuration.sleeveSide,
                                      side: configuration.side,
                                      crateDepth: 0)
        accent = Accent.named(configuration.accentID).color ?? configuration.theme.accent
        super.init(frame: NSRect(origin: .zero, size: layout.canvas))
        wantsLayer = true
        layer?.masksToBounds = false

        for shaped in [progressTrack, progressArc] {
            shaped.fillColor = nil
            shaped.lineCap = .round
        }
        timeLabel.alignmentMode = .right
        timeLabel.truncationMode = .none

        holder.addSublayer(spin)
        holder.addSublayer(sheen)
        holder.addSublayer(progressTrack)
        holder.addSublayer(progressArc)
        for sublayer in [glow, holder, sleeveOutgoing, sleeve, timeLabel] {
            layer?.addSublayer(sublayer)
        }

        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var hoverArea: NSTrackingArea?

    private func refreshHoverArea() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let radius = layout.recordDiameter / 2
        let sweep = CGRect(x: layout.extended.x - radius, y: layout.extended.y - radius,
                           width: radius * 2, height: radius * 2)
        let area = NSTrackingArea(rect: layout.sleeve.union(sweep),
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        holder.transform = CATransform3DMakeScale(1.035, 1.035, 1)
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.28)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        holder.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    private func rebuild() {
        let theme = configuration.theme
        let scale = window?.backingScaleFactor ?? 2
        let diameter = layout.recordDiameter
        let radius = diameter / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        glow.frame = CGRect(origin: .zero, size: layout.canvas)
        glow.contentsScale = scale

        let coverSide = layout.sleeve.width
        let source = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let cover = RecordArtwork.cover(from: source, token: artworkToken, side: coverSide,
                                        theme: theme, scale: scale)

        for card in [sleeve, sleeveOutgoing] {
            card.frame = layout.sleeve
            card.contentsScale = scale
        }
        sleeveOutgoing.isHidden = true

        sleeve.contents = RecordArtwork.sleeve(
            layout: layout, cover: cover, theme: theme,
            title: configuration.showsCaption ? title : nil,
            artist: configuration.showsCaption ? artist : nil, scale: scale)
        if showingBack, let back = backImage(scale: scale) { sleeve.contents = back }

        let discBounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        holder.bounds = discBounds
        holder.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        holder.zPosition = -2
        holder.position = isSpinning ? layout.extended : layout.tucked

        for sublayer in [spin, sheen] {
            sublayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            sublayer.bounds = discBounds
            sublayer.position = CGPoint(x: radius, y: radius)
            sublayer.contentsScale = scale
        }
        spin.contents = RecordArtwork.record(diameter: diameter, cover: cover, token: artworkToken,
                                             theme: theme, accent: accent, scale: scale)
        sheen.contents = RecordArtwork.recordSheen(diameter: diameter, theme: theme, scale: scale)

        let ringRadius = radius * 1.045
        let centre = CGPoint(x: radius, y: radius)
        let visible = layout.side.visibleArc
        let arc = CGMutablePath()
        arc.addArc(center: centre, radius: ringRadius, startAngle: visible.start,
                   endAngle: visible.end, clockwise: visible.clockwise)
        for shaped in [progressTrack, progressArc] {
            shaped.frame = discBounds
            shaped.path = arc
            shaped.lineWidth = max(1, diameter * 0.014)
            shaped.contentsScale = scale
        }
        progressTrack.strokeColor = CGColor(gray: 1, alpha: 0.14)
        progressArc.strokeColor = accent
        progressArc.strokeEnd = CGFloat(progress ?? 0)

        let inset = layout.sleeve.width * 0.055
        let height = layout.sleeve.width * 0.075
        timeLabel.frame = CGRect(x: layout.sleeve.minX + inset,
                                 y: layout.sleeve.minY + inset * 0.7,
                                 width: layout.sleeve.width - inset * 2, height: height)
        timeLabel.fontSize = layout.sleeve.width * 0.060
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: timeLabel.fontSize,
                                                          weight: .medium)
        timeLabel.foregroundColor = theme.captionTitle
        timeLabel.shadowColor = CGColor(gray: 0, alpha: 1)
        timeLabel.shadowOpacity = 0.55
        timeLabel.shadowRadius = layout.sleeve.width * 0.012
        timeLabel.shadowOffset = .zero
        timeLabel.contentsScale = scale

        applyGlow(animated: false)
        updateProgressVisibility()
        updateTimeLabel()
        refreshHoverArea()

        CATransaction.commit()

        if isSpinning {
            let angle = currentAngle()
            settle(at: angle)
            attachSteadySpin(from: angle, startingIn: 0)
        }
    }

    func setNowPlaying(title: String?, artist: String?, artwork: NSImage?) {
        let changed = self.title != nil && title != self.title
        let isSwap = changed && window != nil
        let previousSleeve = sleeve.contents as! CGImage?
        let previousRecord = spin.contents as! CGImage?

        if changed {
            showingBack = false
        }
        self.title = title
        self.artist = artist
        if artwork !== self.artwork {
            self.artwork = artwork
            artworkToken += 1
        }

        let side = layout.sleeve.width
        let scale = window?.backingScaleFactor ?? 2
        let theme = configuration.theme
        let token = artworkToken
        let source = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        renderGeneration += 1
        let generation = renderGeneration

        let fixedAccent = Accent.named(configuration.accentID).color
        let prepare = {
            _ = RecordArtwork.cover(from: source, token: token, side: side,
                                    theme: theme, scale: scale)
            return fixedAccent ?? RecordArtwork.accentColor(of: source, theme: theme)
        }
        let apply: (CGColor) -> Void = { [weak self] accent in
            guard let self, self.renderGeneration == generation else { return }
            self.accent = accent
            self.rebuild()
            self.applyGlow(animated: true)

            if isSwap {
                self.playSwap(previousSleeve: previousSleeve, previousRecord: previousRecord)
            } else {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.5
                self.sleeve.add(fade, forKey: "contents")
                self.spin.add(fade, forKey: "contents")
            }
        }

        guard window != nil else {
            apply(prepare())
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let accent = prepare()
            DispatchQueue.main.async { apply(accent) }
        }
    }

    private func playSwap(previousSleeve: CGImage?, previousRecord: CGImage?) {
        let duration: CFTimeInterval = 0.95
        let start = CACurrentMediaTime()
        let settle = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

        swapGeneration += 1
        let generation = swapGeneration

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        sleeveOutgoing.contents = previousSleeve
        sleeveOutgoing.isHidden = false
        sleeveOutgoing.opacity = 1

        let centre = CGPoint(x: layout.sleeve.midX, y: layout.sleeve.midY)
        let arrival = layout.arrivalOffset
        let drop = CABasicAnimation(keyPath: "position")
        drop.fromValue = NSValue(point: CGPoint(x: centre.x + arrival.width,
                                                y: centre.y + arrival.height))
        drop.toValue = NSValue(point: centre)
        drop.beginTime = start + duration * 0.22
        drop.duration = duration * 0.56
        drop.timingFunction = settle
        drop.fillMode = .backwards
        sleeve.add(drop, forKey: "vinyl.drop")

        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.beginTime = start + duration * 0.22
        appear.duration = duration * 0.18
        appear.fillMode = .backwards
        sleeve.add(appear, forKey: "vinyl.appear")

        let target = isSpinning ? layout.extended : layout.tucked
        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.values = [
            NSValue(point: (holder.presentation() ?? holder).position),
            NSValue(point: layout.tucked),
            NSValue(point: layout.tucked),
            NSValue(point: target),
        ]
        travel.keyTimes = [0, 0.30, 0.76, 1]
        travel.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut),
                                  CAMediaTimingFunction(name: .linear), settle]
        travel.duration = duration
        holder.position = target
        holder.add(travel, forKey: "vinyl.slide")

        let newFace = spin.contents
        if let previousRecord {
            spin.contents = previousRecord
        }

        CATransaction.commit()

        if previousRecord != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.38) { [weak self] in
                guard let self, self.swapGeneration == generation else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.spin.contents = newFace
                CATransaction.commit()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self, self.swapGeneration == generation else { return }
            self.sleeveOutgoing.isHidden = true
            self.sleeveOutgoing.removeAllAnimations()
        }
    }

    private func applyGlow(animated: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        let contents = RecordArtwork.glow(layout: layout, color: accent,
                                          theme: configuration.theme, scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.8
            glow.add(fade, forKey: "contents")
        }
        glow.contents = contents
        CATransaction.commit()
    }

    func setProgress(_ fraction: Double?, duration: Double?, playing: Bool) {
        progress = fraction
        trackDuration = duration
        let remaining = (duration).map { $0 * (1 - (fraction ?? 0)) }
        progressArc.removeAnimation(forKey: Self.progressKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressArc.strokeEnd = CGFloat(fraction ?? 0)
        CATransaction.commit()

        if playing, let fraction, let remaining, remaining > 0.5 {
            let run = CABasicAnimation(keyPath: "strokeEnd")
            run.fromValue = fraction
            run.toValue = 1.0
            run.duration = remaining
            run.timingFunction = CAMediaTimingFunction(name: .linear)
            run.fillMode = .forwards
            run.isRemovedOnCompletion = false
            progressArc.add(run, forKey: Self.progressKey)
        }
        updateProgressVisibility()
    }

    private func updateProgressVisibility() {
        let shown: Float = configuration.showsProgress && isSpinning && progress != nil ? 1 : 0
        progressTrack.opacity = shown * 0.85
        progressArc.opacity = shown
        timeLabel.isHidden = !showsTimeNow
        startTimeTicker(configuration.showsTime && isSpinning && trackDuration != nil)
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private func updateTimeLabel() {
        guard configuration.showsTime, let duration = trackDuration else {
            timeLabel.string = ""
            return
        }
        let live = (progressArc.presentation() ?? progressArc).strokeEnd
        timeLabel.string = Self.clock(Double(live) * duration) + " / " + Self.clock(duration)
    }

    private func startTimeTicker(_ running: Bool) {
        if running, ticker == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateTimeLabel()
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !running {
            ticker?.invalidate()
            ticker = nil
            updateTimeLabel()
        }
    }

    var secondsPerRevolution: Double = 1.8 {
        didSet {
            guard isSpinning else { return }
            let angle = currentAngle()
            settle(at: angle)
            attachSteadySpin(from: angle, startingIn: 0)
        }
    }

    func setSpinning(_ shouldSpin: Bool) {
        guard shouldSpin != isSpinning else { return }
        isSpinning = shouldSpin
        if shouldSpin { startSpin() } else { stopSpin() }

        slideRecord(out: shouldSpin)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        updateProgressVisibility()
        CATransaction.commit()
    }

    private func slideRecord(out: Bool) {
        let target = out ? layout.extended : layout.tucked
        let current = (holder.presentation() ?? holder).position

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.position = target
        CATransaction.commit()

        let slide = CASpringAnimation(keyPath: "position")
        slide.fromValue = NSValue(point: current)
        slide.toValue = NSValue(point: target)
        slide.mass = 1
        slide.stiffness = 110
        slide.damping = 17
        slide.duration = slide.settlingDuration
        holder.add(slide, forKey: "vinyl.slide")
    }

    private var rampAngle: Double {
        -(2 * .pi / secondsPerRevolution) * Self.spinUpDuration / 2
    }

    private func settle(at angle: CGFloat) {
        spin.removeAnimation(forKey: Self.rotationKey)
        spin.removeAnimation(forKey: Self.rampKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spin.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
    }

    private func startSpin() {
        let from = currentAngle()
        let to = from + CGFloat(rampAngle)
        settle(at: to)

        let ramp = CABasicAnimation(keyPath: "transform.rotation.z")
        ramp.fromValue = from
        ramp.toValue = to
        ramp.duration = Self.spinUpDuration
        ramp.timingFunction = Self.easeInQuad
        ramp.fillMode = .forwards
        ramp.isRemovedOnCompletion = false
        spin.add(ramp, forKey: Self.rampKey)

        attachSteadySpin(from: to, startingIn: Self.spinUpDuration)
    }

    private func stopSpin() {
        let from = currentAngle()
        let to = from + CGFloat(rampAngle)
        settle(at: to)

        let ramp = CABasicAnimation(keyPath: "transform.rotation.z")
        ramp.fromValue = from
        ramp.toValue = to
        ramp.duration = Self.spinUpDuration
        ramp.timingFunction = Self.easeOutQuad
        spin.add(ramp, forKey: Self.rampKey)
    }

    private func attachSteadySpin(from angle: CGFloat, startingIn delay: CFTimeInterval) {
        let steady = CABasicAnimation(keyPath: "transform.rotation.z")
        steady.fromValue = angle
        steady.byValue = -Double.pi * 2
        steady.duration = secondsPerRevolution
        steady.repeatCount = .infinity
        steady.isRemovedOnCompletion = false
        if delay > 0 { steady.beginTime = CACurrentMediaTime() + delay }
        spin.add(steady, forKey: Self.rotationKey)
    }

    private func currentAngle() -> CGFloat {
        (spin.presentation() ?? spin).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
    }

    private enum Gesture { case none, window, seek, scratch, label }

    private var gesture: Gesture = .none
    private var didDrag = false
    private var scratchAnchor: CGFloat = 0
    private var scratchStartAngle: CGFloat = 0
    private var scratchTotal: CGFloat = 0
    private var scratchLastMoment: CFTimeInterval = 0

    private func local(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }

    private static let flipKey = "vinyl.flip"
    private var showingBack = false
    var backSideProvider: (() -> [String])?

    func flipSleeve() {
        guard sleeve.animation(forKey: Self.flipKey) == nil else { return }
        let scale = window?.backingScaleFactor ?? 2
        let toBack = !showingBack
        guard let previous = sleeve.contents,
              let target = toBack ? backImage(scale: scale) : frontImage(scale: scale)
        else { return }

        func turned(_ angle: CGFloat) -> CATransform3D {
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 900
            return CATransform3DRotate(perspective, angle, 0, 1, 0)
        }

        let duration: CFTimeInterval = 0.55
        let turn = CAKeyframeAnimation(keyPath: "transform")
        turn.values = [turned(0), turned(-.pi / 2), turned(.pi / 2), turned(0)]
        turn.keyTimes = [0, 0.5, 0.5, 1]
        turn.timingFunctions = [CAMediaTimingFunction(name: .easeIn),
                                CAMediaTimingFunction(name: .linear),
                                CAMediaTimingFunction(name: .easeOut)]
        turn.duration = duration

        let swap = CAKeyframeAnimation(keyPath: "contents")
        swap.values = [previous, target]
        swap.keyTimes = [0, 0.5, 1]
        swap.calculationMode = .discrete
        swap.duration = duration

        sleeve.contents = target
        showingBack = toBack
        timeLabel.isHidden = !showsTimeNow
        sleeve.add(turn, forKey: Self.flipKey)
        sleeve.add(swap, forKey: "vinyl.flip.contents")
    }

    private var showsTimeNow: Bool {
        configuration.showsTime && trackDuration != nil && !showingBack
    }

    private func frontImage(scale: CGFloat) -> CGImage? {
        let source = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let cover = RecordArtwork.cover(from: source, token: artworkToken,
                                        side: layout.sleeve.width,
                                        theme: configuration.theme, scale: scale)
        return RecordArtwork.sleeve(layout: layout, cover: cover, theme: configuration.theme,
                                    title: configuration.showsCaption ? title : nil,
                                    artist: configuration.showsCaption ? artist : nil, scale: scale)
    }

    private func backImage(scale: CGFloat) -> CGImage? {
        RecordArtwork.sleeveBack(layout: layout, theme: configuration.theme,
                                 lines: backSideProvider?() ?? [], scale: scale)
    }

    private var recordCentre: CGPoint { (holder.presentation() ?? holder).position }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let spot = local(point)
        if layout.sleeve.contains(spot) { return self }
        let dx = spot.x - recordCentre.x, dy = spot.y - recordCentre.y
        return sqrt(dx * dx + dy * dy) <= layout.recordDiameter * 0.56 ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        let spot = local(convert(event.locationInWindow, from: nil))
        let dx = spot.x - recordCentre.x, dy = spot.y - recordCentre.y
        let distance = sqrt(dx * dx + dy * dy)
        let radius = layout.recordDiameter / 2
        let angle = atan2(dy, dx)
        let along = layout.side.fraction(atAngle: angle)

        if event.clickCount == 2, layout.sleeve.contains(spot) {
            gesture = .none
            flipSleeve()
            return
        }

        if configuration.showsProgress, progress != nil, trackDuration != nil,
           abs(distance - radius * 1.045) < radius * 0.12, along >= -0.02, along <= 1.02 {
            gesture = .seek
        } else if distance <= radius * RecordArtwork.Ratio.label, !layout.sleeve.contains(spot) {
            gesture = .label
        } else if distance <= radius, !layout.sleeve.contains(spot) {
            gesture = .scratch
            scratchAnchor = angle
            scratchStartAngle = currentAngle()
            scratchTotal = 0
            scratchLastMoment = CACurrentMediaTime()
            settle(at: scratchStartAngle)
            Sounds.shared.beginScratch()
        } else {
            gesture = .window
        }
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        switch gesture {
        case .window, .none:
            window?.performDrag(with: event)
            Preferences.origin = window?.frame.origin
        case .seek:
            previewSeek(at: event)
        case .scratch, .label:
            dragPlatter(to: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch gesture {
        case .seek where didDrag:
            if let duration = trackDuration {
                onSeek?(Double(seekFraction(at: event)) * duration)
            }
        case .scratch:
            Sounds.shared.endScratch()
            let seconds = -Double(scratchTotal / (2 * .pi)) * secondsPerRevolution
            if let duration = trackDuration, let now = progress, abs(seconds) > 0.25 {
                onSeek?(min(max(now * duration + seconds, 0), duration))
            }
            if isSpinning {
                attachSteadySpin(from: currentAngle(), startingIn: 0)
            }
            if !didDrag { onToggle?() }
        case .label:
            if !didDrag { onOpenPlayer?() }
        default:
            if !didDrag { onToggle?() }
        }
        gesture = .none
        didDrag = false
    }

    private func seekFraction(at event: NSEvent) -> CGFloat {
        let spot = local(convert(event.locationInWindow, from: nil))
        let angle = atan2(spot.y - recordCentre.y, spot.x - recordCentre.x)
        return min(max(layout.side.fraction(atAngle: angle), 0), 1)
    }

    private func previewSeek(at event: NSEvent) {
        let fraction = seekFraction(at: event)
        progressArc.removeAnimation(forKey: Self.progressKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressArc.strokeEnd = fraction
        CATransaction.commit()
        updateTimeLabel()
    }

    private func dragPlatter(to event: NSEvent) {
        let spot = local(convert(event.locationInWindow, from: nil))
        let angle = atan2(spot.y - recordCentre.y, spot.x - recordCentre.x)
        var delta = angle - scratchAnchor
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        scratchAnchor = angle
        scratchTotal += delta

        let now = CACurrentMediaTime()
        let elapsed = max(now - scratchLastMoment, 1.0 / 120)
        scratchLastMoment = now
        Sounds.shared.updateScratch(turnsPerSecond: Double(delta) / (2 * .pi) / elapsed)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spin.transform = CATransform3DMakeRotation(scratchStartAngle + scratchTotal, 0, 0, 1)
        CATransaction.commit()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private var lastSkip = Date.distantPast

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > 8, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              Date().timeIntervalSince(lastSkip) > 0.8 else { return }
        lastSkip = Date()
        if event.scrollingDeltaX < 0 { onNext?() } else { onPrevious?() }
    }
}
