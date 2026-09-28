import AppKit

func icon(size: CGFloat) -> CGImage {
    let pixels = Int(size)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    func p(_ v: CGFloat) -> CGFloat { v * size }
    func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
    }

    let inset = p(0.055)
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = CGPath(roundedRect: body, cornerWidth: p(0.205), cornerHeight: p(0.205),
                       transform: nil)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(gradient([
        (CGColor(red: 0.20, green: 0.21, blue: 0.26, alpha: 1), 0),
        (CGColor(red: 0.09, green: 0.09, blue: 0.12, alpha: 1), 1),
    ]), start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY),
        options: [])

    let centre = CGPoint(x: p(0.655), y: p(0.5))
    let radius = p(0.245)
    let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                      width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: disc)
    ctx.clip()
    ctx.drawRadialGradient(gradient([
        (CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1), 0),
        (CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), 0.75),
        (CGColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1), 1),
    ]), startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
    if size >= 64 {
        var r = radius * 0.42
        ctx.setLineWidth(max(0.5, size / 380))
        while r < radius * 0.95 {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.07))
            ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r,
                                         width: r * 2, height: r * 2))
            r += max(1, size / 90)
        }
    }
    ctx.restoreGState()
    ctx.setLineWidth(max(0.6, size / 200))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
    ctx.strokeEllipse(in: disc.insetBy(dx: p(0.006), dy: p(0.006)))

    let labelR = radius * 0.33
    ctx.setFillColor(CGColor(red: 0.93, green: 0.91, blue: 0.86, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: centre.x - labelR, y: centre.y - labelR,
                               width: labelR * 2, height: labelR * 2))
    if size >= 32 {
        let hole = radius * 0.055
        ctx.setFillColor(CGColor(gray: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: centre.x - hole, y: centre.y - hole,
                                   width: hole * 2, height: hole * 2))
    }

    let sleeve = CGRect(x: p(0.155), y: p(0.235), width: p(0.53), height: p(0.53))
    ctx.setShadow(offset: CGSize(width: p(0.012), height: p(-0.012)), blur: p(0.05),
                  color: CGColor(gray: 0, alpha: 0.55))
    ctx.setFillColor(CGColor(red: 0.86, green: 0.24, blue: 0.18, alpha: 1))
    ctx.fill(sleeve)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.saveGState()
    ctx.clip(to: sleeve)
    ctx.drawLinearGradient(gradient([
        (CGColor(red: 1.00, green: 0.42, blue: 0.24, alpha: 1), 0),
        (CGColor(red: 0.62, green: 0.12, blue: 0.14, alpha: 1), 1),
    ]), start: CGPoint(x: sleeve.minX, y: sleeve.maxY),
        end: CGPoint(x: sleeve.maxX, y: sleeve.minY), options: [])
    ctx.setLineWidth(max(0.7, size / 110))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.30))
    let ring = sleeve.width * 0.27
    ctx.strokeEllipse(in: CGRect(x: sleeve.midX - ring, y: sleeve.midY - ring,
                                 width: ring * 2, height: ring * 2))
    ctx.restoreGState()
    ctx.setLineWidth(max(0.5, size / 300))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.stroke(sleeve)

    ctx.restoreGState()
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (size, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
                     (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
                     (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
                     (1024, "icon_512x512@2x")] {
    let image = icon(size: CGFloat(size))
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: out.appendingPathComponent("\(name).png"))
}
print("wrote iconset to \(out.path)")
