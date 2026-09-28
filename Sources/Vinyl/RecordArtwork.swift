import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

enum RecordArtwork {

    enum Ratio {
        static let grooveOuter = 0.965
        static let grooveInner = 0.40
        static let label = 0.325
        static let hole = 0.028
    }

    enum Side: String, CaseIterable {
        case right, left, up, down

        var name: String {
            switch self {
            case .right: return L.t("Вправо", "Right")
            case .left: return L.t("Влево", "Left")
            case .up: return L.t("Вверх", "Up")
            case .down: return L.t("Вниз", "Down")
            }
        }

        var isVertical: Bool { self == .up || self == .down }

        func fraction(atAngle angle: CGFloat) -> CGFloat {
            var a = angle
            switch self {
            case .right: return (.pi / 2 - a) / .pi
            case .left:
                if a < .pi / 2 { a += 2 * .pi }
                return (a - .pi / 2) / .pi
            case .up: return a / .pi
            case .down: return -a / .pi
            }
        }

        var visibleArc: (start: CGFloat, end: CGFloat, clockwise: Bool) {
            switch self {
            case .right: return (.pi / 2, -.pi / 2, true)
            case .left: return (.pi / 2, .pi * 1.5, false)
            case .up: return (0, .pi, false)
            case .down: return (0, -.pi, true)
            }
        }
    }

    struct Layout {
        private(set) var canvas: CGSize
        private(set) var sleeve: CGRect
        let recordDiameter: CGFloat
        private(set) var tucked: CGPoint
        private(set) var extended: CGPoint
        let side: Side
        let arrivalOffset: CGSize
        let crateStep: CGSize

        init(sleeveSide length: CGFloat, side: Side = .right, crateDepth: Int = 0) {
            self.side = side
            let margin = length * 0.045
            let along = length * 1.57
            let across = length * 1.50
            canvas = side.isVertical ? CGSize(width: across, height: along)
                                     : CGSize(width: along, height: across)
            recordDiameter = length * 0.92

            let origin: CGPoint
            switch side {
            case .right, .up: origin = CGPoint(x: margin, y: margin)
            case .left: origin = CGPoint(x: canvas.width - margin - length, y: margin)
            case .down: origin = CGPoint(x: margin, y: canvas.height - margin - length)
            }
            let frame = CGRect(origin: origin, size: CGSize(width: length, height: length))
            sleeve = frame

            func centre(_ reach: CGFloat) -> CGPoint {
                switch side {
                case .right: return CGPoint(x: frame.minX + reach, y: frame.midY)
                case .left: return CGPoint(x: frame.maxX - reach, y: frame.midY)
                case .up: return CGPoint(x: frame.midX, y: frame.minY + reach)
                case .down: return CGPoint(x: frame.midX, y: frame.maxY - reach)
                }
            }
            tucked = centre(length * 0.74)
            extended = centre(length * 1.02)

            arrivalOffset = side.isVertical ? CGSize(width: length * 0.42, height: 0)
                                            : CGSize(width: 0, height: length * 0.42)

            let d = length * 0.024
            let step: CGSize
            switch side {
            case .right: step = CGSize(width: -d, height: -d * 0.55)
            case .left: step = CGSize(width: d, height: -d * 0.55)
            case .up: step = CGSize(width: -d * 0.55, height: -d)
            case .down: step = CGSize(width: -d * 0.55, height: d)
            }
            crateStep = step
            guard crateDepth > 0 else { return }

            let room = CGSize(width: abs(step.width) * CGFloat(crateDepth),
                              height: abs(step.height) * CGFloat(crateDepth))
            let shift = CGPoint(x: step.width < 0 ? room.width : 0,
                                y: step.height < 0 ? room.height : 0)
            canvas = CGSize(width: canvas.width + room.width,
                            height: canvas.height + room.height)
            sleeve = sleeve.offsetBy(dx: shift.x, dy: shift.y)
            tucked = CGPoint(x: tucked.x + shift.x, y: tucked.y + shift.y)
            extended = CGPoint(x: extended.x + shift.x, y: extended.y + shift.y)
        }

        var glowCentre: CGPoint {
            CGPoint(x: (sleeve.midX + extended.x) / 2, y: (sleeve.midY + extended.y) / 2)
        }
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private struct CoverKey: Hashable {
        let token: Int
        let side: CGFloat
        let scale: CGFloat
        let theme: String
    }
    private struct SheenKey: Hashable {
        let diameter: CGFloat
        let scale: CGFloat
        let theme: String
    }
    private static let cacheLock = NSLock()
    private static var coverCache: [CoverKey: CGImage] = [:]
    private static var coverOrder: [CoverKey] = []
    private static var sheenCache: [SheenKey: CGImage] = [:]
    private struct RecordKey: Hashable {
        let token: Int
        let diameter: CGFloat
        let scale: CGFloat
        let theme: String
        let accent: [Int]
    }
    private static var recordCache: [RecordKey: CGImage] = [:]
    private static var recordOrder: [RecordKey] = []
    private static var noiseCache: [Int: CGImage] = [:]

    private static func bitmap(size: CGSize, scale: CGFloat) -> CGContext? {
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        return context
    }

    private static func bitmap(side: CGFloat, scale: CGFloat) -> CGContext? {
        bitmap(size: CGSize(width: side, height: side), scale: scale)
    }

    private static func gradient(_ stops: [(color: CGColor, location: CGFloat)]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: stops.map(\.color) as CFArray,
                   locations: stops.map(\.location))
    }

    static func cover(from source: CGImage?, token: Int, side: CGFloat, theme: Theme,
                      scale: CGFloat) -> CGImage? {
        let key = CoverKey(token: token, side: side, scale: scale, theme: theme.id)
        cacheLock.lock()
        let hit = coverCache[key]
        cacheLock.unlock()
        if let hit { return hit }

        guard let ctx = bitmap(side: side, scale: scale) else { return nil }
        let full = CGRect(x: 0, y: 0, width: side, height: side)

        ctx.setFillColor(theme.sleeveBoard)
        ctx.fill(full)

        guard let source else {
            drawEmptyCover(in: ctx, side: side, theme: theme)
            let blank = ctx.makeImage()
            store(blank, for: key)
            return blank
        }

        let sourceSize = CGSize(width: source.width, height: source.height)
        let targetPixels = side * scale
        let isSquarish = abs(sourceSize.width - sourceSize.height)
            / max(sourceSize.width, sourceSize.height) < 0.06

        if !isSquarish {
            let fill = targetPixels / min(sourceSize.width, sourceSize.height) * 1.2
            if let backdrop = blurredFill(source, scaledBy: fill, blur: targetPixels * 0.06) {
                let w = CGFloat(backdrop.width) / scale, h = CGFloat(backdrop.height) / scale
                ctx.draw(backdrop, in: CGRect(x: (side - w) / 2, y: (side - h) / 2,
                                              width: w, height: h))
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.28))
                ctx.fill(full)
            }
        }

        let factor = isSquarish ? targetPixels / sourceSize.width
                                : targetPixels / max(sourceSize.width, sourceSize.height)
        let front = upscaled(source, by: factor) ?? source
        let w = CGFloat(front.width) / scale, h = CGFloat(front.height) / scale
        ctx.draw(front, in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))

        if let noise = noiseTile(side: 180) {
            ctx.saveGState()
            ctx.setAlpha(0.055)
            ctx.setBlendMode(.overlay)
            ctx.draw(noise, in: full, byTiling: true)
            ctx.restoreGState()
        }

        let printed = ctx.makeImage()
        store(printed, for: key)
        return printed
    }

    private static func store(_ image: CGImage?, for key: CoverKey) {
        guard let image else { return }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        coverCache[key] = image
        coverOrder.append(key)
        while coverOrder.count > 6 {
            coverCache.removeValue(forKey: coverOrder.removeFirst())
        }
    }

    private static func drawEmptyCover(in ctx: CGContext, side: CGFloat, theme: Theme) {
        let centre = CGPoint(x: side / 2, y: side / 2)
        ctx.setLineWidth(max(1, side * 0.004))
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.16))
        let ring = side * 0.30
        ctx.strokeEllipse(in: CGRect(x: centre.x - ring, y: centre.y - ring,
                                     width: ring * 2, height: ring * 2))
    }

    private static func upscaled(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        var ci = CIImage(cgImage: image)
        let smallest = min(image.width, image.height)
        let isThumbnail = smallest < 400

        if isThumbnail {
            let extent = ci.extent
            let deblock = CIFilter.gaussianBlur()
            deblock.inputImage = ci.clampedToExtent()
            deblock.radius = 0.30
            ci = (deblock.outputImage ?? ci).cropped(to: extent)
        }

        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ci
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        ci = lanczos.outputImage ?? ci

        let enlarged = ci.extent
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ci.clampedToExtent()
        sharpen.sharpness = 0.50
        sharpen.radius = Float(max(1.2, factor * 0.7))
        ci = (sharpen.outputImage ?? ci).cropped(to: enlarged)

        let grade = CIFilter.colorControls()
        grade.inputImage = ci
        grade.saturation = 1.08
        grade.contrast = 1.05
        ci = grade.outputImage ?? ci

        return ciContext.createCGImage(ci, from: ci.extent)
    }

    private static func blurredFill(_ image: CGImage, scaledBy factor: CGFloat,
                                    blur radius: CGFloat) -> CGImage? {
        var ci = CIImage(cgImage: image)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ci
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        ci = lanczos.outputImage ?? ci

        let extent = ci.extent
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ci.clampedToExtent()
        blurFilter.radius = Float(radius)
        ci = (blurFilter.outputImage ?? ci).cropped(to: extent)

        let saturate = CIFilter.colorControls()
        saturate.inputImage = ci
        saturate.saturation = 1.4
        ci = saturate.outputImage ?? ci

        return ciContext.createCGImage(ci, from: extent)
    }

    static func sleeve(layout: Layout, cover: CGImage?, theme: Theme,
                       title: String?, artist: String?, scale: CGFloat) -> CGImage? {

        let side = layout.sleeve.width
        guard let ctx = bitmap(side: side, scale: scale) else { return nil }
        let full = CGRect(x: 0, y: 0, width: side, height: side)

        ctx.setFillColor(theme.sleeveBoard)
        ctx.fill(full)
        if let cover { ctx.draw(cover, in: full) }

        if let noise = noiseTile(side: 200) {
            ctx.saveGState()
            ctx.setAlpha(0.032 * theme.sleeveWear)
            ctx.setBlendMode(.overlay)
            ctx.draw(noise, in: full, byTiling: true)
            ctx.restoreGState()
        }
        ctx.setLineWidth(max(0.75, side * 0.003))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
        ctx.move(to: CGPoint(x: side - max(0.75, side * 0.003) / 2, y: 0))
        ctx.addLine(to: CGPoint(x: side - max(0.75, side * 0.003) / 2, y: side))
        ctx.strokePath()

        drawCaption(in: ctx, side: side, theme: theme, title: title, artist: artist)

        if let edge = theme.sleeveEdge {
            ctx.setLineWidth(max(0.75, side * 0.0035))
            ctx.setStrokeColor(edge)
            ctx.stroke(full.insetBy(dx: max(0.4, side * 0.002), dy: max(0.4, side * 0.002)))
        }

        return ctx.makeImage()
    }

    static func sleeveBack(layout: Layout, theme: Theme, lines: [String],
                           scale: CGFloat) -> CGImage? {
        let side = layout.sleeve.width
        guard let ctx = bitmap(side: side, scale: scale) else { return nil }
        let full = CGRect(x: 0, y: 0, width: side, height: side)

        ctx.setFillColor(theme.sleeveBoard)
        ctx.fill(full)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.18))
        ctx.fill(full)

        if let noise = noiseTile(side: 200) {
            ctx.saveGState()
            ctx.setAlpha(0.045 * theme.sleeveWear)
            ctx.setBlendMode(.overlay)
            ctx.draw(noise, in: full, byTiling: true)
            ctx.restoreGState()
        }

        let seam = max(0.75, side * 0.003)
        ctx.setLineWidth(seam)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
        ctx.move(to: CGPoint(x: seam / 2, y: 0))
        ctx.addLine(to: CGPoint(x: seam / 2, y: side))
        ctx.strokePath()

        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        let inset = side * 0.085
        let width = side - inset * 2
        let ink = NSColor(cgColor: theme.captionTitle) ?? .white
        let faded = NSColor(cgColor: theme.captionArtist) ?? .gray
        var cursor = side - inset

        for line in lines {
            if line.isEmpty { cursor -= side * 0.030; continue }
            let heading = line.hasPrefix("#")
            let wraps = line.hasPrefix("*")
            let text = (heading || wraps) ? String(line.dropFirst()) : line
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = heading
                ? [.font: NSFont.systemFont(ofSize: max(6, side * 0.045), weight: .semibold),
                   .foregroundColor: faded, .kern: side * 0.006, .paragraphStyle: style]
                : [.font: NSFont.systemFont(ofSize: max(6, side * 0.050),
                                            weight: wraps ? .medium : .regular),
                   .foregroundColor: ink, .paragraphStyle: style]
            let string = NSAttributedString(string: heading ? text.uppercased() : text,
                                            attributes: attributes)

            let height: CGFloat
            if wraps {
                let bounds = string.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
                height = ceil(bounds.height) + side * 0.012
            } else {
                height = side * (heading ? 0.062 : 0.068)
            }
            cursor -= height
            guard cursor > inset * 0.5 else { break }
            string.draw(with: CGRect(x: inset, y: cursor, width: width, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        if let edge = theme.sleeveEdge {
            ctx.setLineWidth(max(0.75, side * 0.0035))
            ctx.setStrokeColor(edge)
            ctx.stroke(full.insetBy(dx: max(0.4, side * 0.002), dy: max(0.4, side * 0.002)))
        }
        return ctx.makeImage()
    }

    private static func drawCaption(in ctx: CGContext, side: CGFloat, theme: Theme,
                                    title: String?, artist: String?) {
        guard let title, !title.isEmpty else { return }
        let inset = side * 0.055
        let scrimHeight = side * 0.26

        if let scrim = gradient([(theme.captionScrim, 0),
                                 (CGColor(gray: 0, alpha: 0), 1)]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: side, height: scrimHeight))
            ctx.drawLinearGradient(scrim, start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: scrimHeight), options: [])
            ctx.restoreGState()
        }

        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }

        let width = side - inset * 2 - side * 0.10
        var cursor = inset

        if let artist, !artist.isEmpty {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let text = NSAttributedString(string: artist.uppercased(), attributes: [
                .font: NSFont.systemFont(ofSize: max(5, side * 0.042), weight: .medium),
                .foregroundColor: NSColor(cgColor: theme.captionArtist) ?? .gray,
                .kern: side * 0.004,
                .paragraphStyle: style,
            ])
            text.draw(in: CGRect(x: inset, y: cursor, width: width, height: side * 0.07))
            cursor += side * 0.065
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: max(7, side * 0.062), weight: .semibold),
            .foregroundColor: NSColor(cgColor: theme.captionTitle) ?? .white,
            .paragraphStyle: style,
        ])
        text.draw(in: CGRect(x: inset, y: cursor, width: width, height: side * 0.10))
    }

    private static func noise(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }

    private static func noiseTile(side: Int) -> CGImage? {
        cacheLock.lock()
        let cached = noiseCache[side]
        cacheLock.unlock()
        if let cached { return cached }
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = ctx.data else { return nil }
        var generator = SystemRandomNumberGenerator()
        let buffer = pixels.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for i in 0..<(side * side) {
            let value = UInt8.random(in: 100...155, using: &generator)
            buffer[i * 4 + 0] = value
            buffer[i * 4 + 1] = value
            buffer[i * 4 + 2] = value
            buffer[i * 4 + 3] = 255
        }
        let tile = ctx.makeImage()
        cacheLock.lock()
        noiseCache[side] = tile
        cacheLock.unlock()
        return tile
    }

    static func record(diameter: CGFloat, cover: CGImage?, token: Int, theme: Theme,
                       accent: CGColor, scale: CGFloat) -> CGImage? {
        let components = (accent.components ?? [0, 0, 0, 0]).map { Int(($0 * 100).rounded()) }
        let key = RecordKey(token: token, diameter: diameter, scale: scale,
                            theme: theme.id, accent: components)
        cacheLock.lock()
        let hit = recordCache[key]
        cacheLock.unlock()
        if let hit { return hit }

        guard let ctx = bitmap(side: diameter, scale: scale) else { return nil }
        let radius = diameter / 2
        let centre = CGPoint(x: radius, y: radius)
        let full = CGRect(x: 0, y: 0, width: diameter, height: diameter)

        ctx.saveGState()
        ctx.addEllipse(in: full)
        ctx.clip()

        switch theme.pressing {
        case .black:
            if let base = gradient([(theme.vinylCentre, 0), (theme.vinylRim, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }
        case .wax:
            let components = accent.components ?? [1, 1, 1, 1]
            let deep = CGColor(red: components[0] * 0.34, green: components[1] * 0.34,
                               blue: components[2] * 0.34, alpha: 1)
            let lit = CGColor(red: min(1, components[0] * 1.05), green: min(1, components[1] * 0.85),
                              blue: min(1, components[2] * 0.75), alpha: 1)
            if let base = gradient([(deep, 0), (lit, 0.78), (deep, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }
        case .marble:
            let c = accent.components ?? [1, 1, 1, 1]
            let deep = CGColor(red: c[0] * 0.20, green: c[1] * 0.20, blue: c[2] * 0.24, alpha: 1)
            let mid = CGColor(red: c[0] * 0.52, green: c[1] * 0.52, blue: c[2] * 0.60, alpha: 1)
            if let base = gradient([(deep, 0), (mid, 0.75), (deep, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }
            let swirl = theme.secondary.components ?? [1, 1, 1, 1]
            for band in 0..<30 {
                let t = Double(band) / 30
                let phase = t * 2 * .pi * 3.1
                let path = CGMutablePath()
                for step in 0...72 {
                    let u = Double(step) / 72
                    let angle = u * 2 * .pi
                    let wander = 0.062 * sin(angle * 3 + phase)
                        + 0.034 * sin(angle * 7 - phase * 1.7)
                        + 0.016 * sin(angle * 13 + phase * 0.6)
                    let rr = radius * CGFloat(0.16 + 0.82 * t + wander)
                    let point = CGPoint(x: centre.x + rr * CGFloat(cos(angle)),
                                        y: centre.y + rr * CGFloat(sin(angle)))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                ctx.setLineWidth(radius * CGFloat(0.012 + 0.034 * abs(sin(t * 9.3))))
                ctx.setStrokeColor(CGColor(red: swirl[0], green: swirl[1], blue: swirl[2],
                                           alpha: CGFloat(0.05 + 0.12 * abs(sin(t * 5.7)))))
                ctx.addPath(path)
                ctx.strokePath()
            }

        case .shellac:
            if let base = gradient([(theme.vinylCentre, 0), (theme.vinylRim, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }

        case .splatter:
            let c = accent.components ?? [1, 1, 1, 1]
            let deep = CGColor(red: c[0] * 0.26, green: c[1] * 0.26, blue: c[2] * 0.30, alpha: 1)
            let mid = CGColor(red: c[0] * 0.62, green: c[1] * 0.62, blue: c[2] * 0.68, alpha: 1)
            if let base = gradient([(deep, 0), (mid, 0.8), (deep, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }
            let splash = theme.secondary.components ?? [1, 1, 1, 1]
            for blot in 0..<120 {
                let angle = noise(blot, 1) * 2 * .pi
                let distance = radius * CGFloat(sqrt(noise(blot, 2))) * 0.97
                let size = radius * CGFloat(0.012 + 0.075 * pow(noise(blot, 3), 2.6))
                let origin = CGPoint(x: centre.x + distance * CGFloat(cos(angle)),
                                     y: centre.y + distance * CGFloat(sin(angle)))
                let path = CGMutablePath()
                for step in 0...26 {
                    let u = Double(step) / 26
                    let a = u * 2 * .pi
                    let wobble = 1 + 0.34 * sin(a * 3 + noise(blot, 4) * 6.3)
                        + 0.20 * sin(a * 5 - noise(blot, 5) * 6.3)
                    let rr = size * CGFloat(wobble)
                    let point = CGPoint(x: origin.x + rr * CGFloat(cos(a)),
                                        y: origin.y + rr * CGFloat(sin(a)))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                let pale = noise(blot, 6) > 0.35
                ctx.setFillColor(pale
                    ? CGColor(red: splash[0], green: splash[1], blue: splash[2],
                              alpha: CGFloat(0.55 + 0.4 * noise(blot, 7)))
                    : CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(0.20 + 0.25 * noise(blot, 8))))
                ctx.addPath(path)
                ctx.fillPath()
            }

        case .clear:
            if let base = gradient([(theme.vinylCentre.copy(alpha: 0.22) ?? theme.vinylCentre, 0),
                                    (theme.vinylRim.copy(alpha: 0.34) ?? theme.vinylRim, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }

        case .galaxy:
            if let base = gradient([(theme.vinylCentre, 0), (theme.vinylRim, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }
            let cloudA = accent.components ?? [1, 1, 1, 1]
            let cloudB = theme.secondary.components ?? [1, 1, 1, 1]
            for cloud in 0..<14 {
                let angle = noise(cloud, 11) * 2 * .pi
                let distance = radius * CGFloat(0.15 + 0.75 * noise(cloud, 12))
                let spot = CGPoint(x: centre.x + distance * CGFloat(cos(angle)),
                                   y: centre.y + distance * CGFloat(sin(angle)))
                let reach = radius * CGFloat(0.16 + 0.30 * noise(cloud, 13))
                let tint = noise(cloud, 14) > 0.5 ? cloudA : cloudB
                var stops: [(color: CGColor, location: CGFloat)] = []
                for step in 0...10 {
                    let t = CGFloat(step) / 10
                    stops.append((CGColor(red: tint[0], green: tint[1], blue: tint[2],
                                          alpha: CGFloat(0.30 * noise(cloud, 15) + 0.10)
                                              * pow(1 - t, 2.0)), t))
                }
                if let nebula = gradient(stops) {
                    ctx.drawRadialGradient(nebula, startCenter: spot, startRadius: 0,
                                           endCenter: spot, endRadius: reach, options: [])
                }
            }
            for star in 0..<260 {
                let angle = noise(star, 21) * 2 * .pi
                let distance = radius * CGFloat(sqrt(noise(star, 22))) * 0.98
                let size = radius * CGFloat(0.002 + 0.005 * pow(noise(star, 23), 3))
                ctx.setFillColor(CGColor(gray: 1, alpha: CGFloat(0.25 + 0.7 * noise(star, 24))))
                ctx.fillEllipse(in: CGRect(x: centre.x + distance * CGFloat(cos(angle)) - size,
                                           y: centre.y + distance * CGFloat(sin(angle)) - size,
                                           width: size * 2, height: size * 2))
            }

        case .gold:
            if let base = gradient([(theme.vinylCentre, 0), (theme.vinylRim, 0.72),
                                    (theme.vinylCentre, 1)]) {
                ctx.drawRadialGradient(base, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
            }
            let sheen = theme.secondary.components ?? [1, 1, 1, 1]
            let wedges = 480
            for step in 0..<wedges {
                let a0 = Double(step) / Double(wedges) * 2 * .pi
                let a1 = Double(step + 1) / Double(wedges) * 2 * .pi
                let band = pow(max(0, cos(a0 * 2 - 0.7)), 8) * 0.5
                    + pow(max(0, cos(a0 * 6 + 1.3)), 24) * 0.3
                guard band > 0.004 else { continue }
                ctx.setFillColor(CGColor(red: sheen[0], green: sheen[1], blue: sheen[2],
                                         alpha: CGFloat(band) * 0.5))
                ctx.move(to: centre)
                ctx.addArc(center: centre, radius: radius, startAngle: a0, endAngle: a1,
                           clockwise: false)
                ctx.closePath()
                ctx.fillPath()
            }

        case .picture:
            if let cover {
                let zoom: CGFloat = 1.28
                let printed = diameter * zoom
                ctx.draw(cover, in: CGRect(x: (diameter - printed) / 2,
                                           y: (diameter - printed) / 2,
                                           width: printed, height: printed))
                ctx.setBlendMode(.saturation)
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.55))
                ctx.fill(full)
                ctx.setBlendMode(.normal)
            }
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.28))
            ctx.fill(full)
        }

        let spacing: CGFloat = max(1.0, diameter / 300) * theme.grooveScale
        var r = radius * Ratio.grooveInner
        var index = 0
        while r < radius * Ratio.grooveOuter {
            let wobble = sin(Double(index) * 1.7) * 0.5 + 0.5
            ctx.setLineWidth(spacing * 0.42)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: (0.035 + 0.035 * wobble) * theme.grooveContrast))
            ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            let dark = r + spacing * 0.5
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.34 * theme.grooveContrast))
            ctx.strokeEllipse(in: CGRect(x: centre.x - dark, y: centre.y - dark,
                                         width: dark * 2, height: dark * 2))
            r += spacing
            index += 1
        }

        for fraction in [Ratio.grooveOuter, Ratio.grooveInner] {
            let rr = radius * fraction
            ctx.setLineWidth(max(0.8, diameter / 320))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14 * theme.grooveContrast))
            ctx.strokeEllipse(in: CGRect(x: centre.x - rr, y: centre.y - rr,
                                         width: rr * 2, height: rr * 2))
        }

        if theme.pressing != .clear, let noise = noiseTile(side: 220) {
            ctx.saveGState()
            ctx.setAlpha(0.05)
            ctx.setBlendMode(.overlay)
            ctx.draw(noise, in: full, byTiling: true)
            ctx.restoreGState()
        }

        if theme.pressing != .picture {
            let labelR = radius * Ratio.label
            let labelRect = CGRect(x: centre.x - labelR, y: centre.y - labelR,
                                   width: labelR * 2, height: labelR * 2)
            if let seat = gradient([(CGColor(gray: 0, alpha: 0.5), 0),
                                    (CGColor(gray: 0, alpha: 0), 1)]) {
                ctx.drawRadialGradient(seat, startCenter: centre, startRadius: labelR,
                                       endCenter: centre, endRadius: labelR * 1.3, options: [])
            }
            ctx.saveGState()
            ctx.addEllipse(in: labelRect)
            ctx.clip()
            ctx.setFillColor(theme.labelPaper)
            ctx.fill(labelRect)
            if let cover { ctx.draw(cover, in: labelRect) }
            if let vignette = gradient([(CGColor(gray: 0, alpha: 0), 0.7),
                                        (CGColor(gray: 0, alpha: 0.35), 1)]) {
                ctx.drawRadialGradient(vignette, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: labelR, options: [])
            }
            if theme.pressing == .shellac {
                ctx.setLineWidth(max(1, labelR * 0.055))
                ctx.setStrokeColor(theme.secondary)
                ctx.strokeEllipse(in: labelRect.insetBy(dx: labelR * 0.16, dy: labelR * 0.16))
            }
            ctx.restoreGState()
        }

        let holeR = radius * Ratio.hole
        ctx.setFillColor(CGColor(gray: 0.88, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: centre.x - holeR, y: centre.y - holeR,
                                   width: holeR * 2, height: holeR * 2))
        ctx.setLineWidth(max(0.6, holeR * 0.24))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.45))
        ctx.strokeEllipse(in: CGRect(x: centre.x - holeR * 0.88, y: centre.y - holeR * 0.88,
                                     width: holeR * 1.76, height: holeR * 1.76))

        ctx.restoreGState()
        let image = ctx.makeImage()
        cacheLock.lock()
        if let image {
            recordCache[key] = image
            recordOrder.append(key)
            while recordOrder.count > 8 {
                recordCache.removeValue(forKey: recordOrder.removeFirst())
            }
        }
        cacheLock.unlock()
        return image
    }

    static func recordSheen(diameter: CGFloat, theme: Theme, scale: CGFloat) -> CGImage? {
        let key = SheenKey(diameter: diameter, scale: scale, theme: theme.id)
        cacheLock.lock()
        let cached = sheenCache[key]
        cacheLock.unlock()
        if let cached { return cached }
        guard let ctx = bitmap(side: diameter, scale: scale) else { return nil }
        let radius = diameter / 2
        let centre = CGPoint(x: radius, y: radius)

        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        ctx.clip()

        let lobe = Double.pi * 0.30
        let steps = 720
        for step in 0..<steps {
            let a0 = Double(step) / Double(steps) * 2 * .pi
            let a1 = Double(step + 1) / Double(steps) * 2 * .pi
            let wide = pow(max(0, cos(2 * (a0 - lobe))), 4)
            let tight = pow(max(0, cos(2 * (a0 - lobe))), 40)
            let alpha = (0.10 * wide + 0.13 * tight) * theme.sheenStrength
            guard alpha > 0.002 else { continue }
            ctx.setFillColor(CGColor(gray: 1, alpha: alpha))
            ctx.move(to: centre)
            ctx.addArc(center: centre, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.closePath()
            ctx.fillPath()
        }

        if let mask = gradient([(CGColor(gray: 1, alpha: 0), 0),
                                (CGColor(gray: 1, alpha: 0.25), CGFloat(Ratio.label)),
                                (CGColor(gray: 1, alpha: 1), 0.82),
                                (CGColor(gray: 1, alpha: 0.35), 1)]) {
            ctx.setBlendMode(.destinationIn)
            ctx.drawRadialGradient(mask, startCenter: centre, startRadius: 0,
                                   endCenter: centre, endRadius: radius, options: [])
        }
        ctx.restoreGState()
        let light = ctx.makeImage()
        cacheLock.lock()
        sheenCache[key] = light
        cacheLock.unlock()
        return light
    }

    static func accentColor(of source: CGImage?, theme: Theme) -> CGColor {
        guard theme.accentFromArtwork, let source else { return theme.accent }

        let average = CIFilter.areaAverage()
        let input = CIImage(cgImage: source)
        average.inputImage = input
        average.extent = input.extent
        guard let output = average.outputImage else { return theme.accent }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &pixel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        let colour = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                             blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        colour.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &saturation,
                                              brightness: &brightness, alpha: &alpha)
        let lifted = NSColor(hue: hue, saturation: min(1, saturation * 1.9 + 0.18),
                             brightness: min(1, max(brightness, 0.5) * 1.25), alpha: 1)
        return lifted.usingColorSpace(.sRGB)?.cgColor ?? theme.accent
    }

    static func glow(layout: Layout, color: CGColor, theme: Theme, scale: CGFloat) -> CGImage? {
        guard let ctx = bitmap(size: layout.canvas, scale: scale) else { return nil }
        let components = color.components ?? [1, 1, 1, 1]

        let hold: CGFloat = 0.30
        var stops: [(color: CGColor, location: CGFloat)] = []
        let count = 32
        for step in 0...count {
            let t = CGFloat(step) / CGFloat(count)
            let falloff = t <= hold ? 1 : pow(max(0, (1 - t) / (1 - hold)), 2.1)
            stops.append((CGColor(red: components[0], green: components[1], blue: components[2],
                                  alpha: 0.11 * theme.glowStrength * falloff), t))
        }
        guard let ramp = gradient(stops) else { return nil }

        let centre = layout.glowCentre
        ctx.drawRadialGradient(ramp, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: layout.sleeve.width * 0.66,
                               options: [])
        return ctx.makeImage()
    }
}
