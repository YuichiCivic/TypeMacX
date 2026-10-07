// TypeMacX branding renderer.
//
// Draws every TypeMacX mark with CoreGraphics so the assets are reproducible
// from source (no downloaded or hand-edited art). Run via tools/branding/build.sh.
//
//   render <out-dir>
//
// Writes into <out-dir>:
//   AppIcon.iconset/icon_*.png   full-color app icon, 16...1024 px (for iconutil)
//   TypeMacX-1024.png            1024 px app icon (landing page)
//   glyph.png, glyph@2x.png      input-menu template glyph (16 px @1x / 32 px @2x)
//
// Design: the mark is a "T" whose stem ends in a text-cursor (I-beam) foot —
// the letter of the product and the caret you type with, in one shape.
//   App icon: Big Sur-style superellipse (squircle) tile, indigo -> violet
//             gradient, soft top sheen, white I-beam "T" with a cyan caret-blink
//             accent bar to its right.
//   Template glyph: solid rounded square with the I-beam "T" knocked out,
//             hand-placed on the pixel grid at 16 px and 32 px so it stays crisp.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a,
    ])!
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// `dpi` 144 marks an image as a @2x representation (tiffutil -cathidpicheck keeps it).
func writePNG(_ image: CGImage, _ path: String, dpi: Int = 72) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    let props = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
    CGImageDestinationAddImage(dest, image, props)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

/// Big Sur icon tile outline: a superellipse |x/a|^n + |y/b|^n = 1, which has the
/// continuous (curvature-matched) corners of Apple's icon shape.
func superellipse(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2
    let steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

/// The I-beam "T" in a 100x100 design space (y up). Returns rounded rect parts.
/// Crossbar on top, stem down the middle, short foot at the bottom (the I-beam serif).
func tMarkPath(in box: CGRect) -> CGPath {
    let s = box.width / 100
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: box.minX + x * s, y: box.minY + y * s, width: w * s, height: h * s)
    }
    let p = CGMutablePath()
    let rr = 4.5 * s
    p.addRoundedRect(in: R(14, 73, 72, 16), cornerWidth: rr, cornerHeight: rr)  // crossbar
    p.addRoundedRect(in: R(41.5, 16, 17, 66), cornerWidth: rr, cornerHeight: rr) // stem
    p.addRoundedRect(in: R(32, 11, 36, 11), cornerWidth: rr, cornerHeight: rr)  // I-beam foot
    return p
}

// MARK: - App icon

func renderAppIcon(_ px: Int) -> CGImage {
    let ctx = makeContext(px, px)
    let S = CGFloat(px) / 1024
    ctx.scaleBy(x: S, y: S)

    // Big Sur grid: 824 pt body centered on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = superellipse(body)

    // Drop shadow beneath the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.30))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x3A2BB8))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: indigo (top-left) -> violet -> magenta hint (bottom-right).
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb,
                        colors: [color(0x4F7BFF), color(0x5B4BF5), color(0x8A3CF0), color(0xB43BD9)] as CFArray,
                        locations: [0, 0.38, 0.78, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 180, y: 924), end: CGPoint(x: 844, y: 100), options: [])

    // Soft radial glow behind the glyph.
    let glow = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 480, y: 580), startRadius: 0,
                           endCenter: CGPoint(x: 480, y: 580), endRadius: 460, options: [])

    // Top sheen.
    let sheen = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Hairline inner stroke for definition on light backgrounds.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // Glyph: white I-beam "T", slightly left of center to balance the caret accent.
    let glyphBox = CGRect(x: 210, y: 222, width: 520, height: 520)
    let t = tMarkPath(in: glyphBox)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x1B0E6B, 0.38))
    ctx.addPath(t)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    // Subtle vertical tint on the glyph so it isn't flat paper-white.
    ctx.saveGState()
    ctx.addPath(t)
    ctx.clip()
    let gtint = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF), color(0xE6E4FF)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gtint, start: CGPoint(x: 0, y: 742), end: CGPoint(x: 0, y: 222), options: [])
    ctx.restoreGState()

    // Caret accent: a cyan blinking-cursor bar to the lower right of the T.
    let caret = CGRect(x: 702, y: 280, width: 40, height: 210)
    let caretPath = CGPath(roundedRect: caret, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0x5CF2FF, 0.85))
    ctx.addPath(caretPath)
    ctx.setFillColor(color(0x7DF9FF))
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Input-menu template glyph (pixel-fitted)

/// Hand-fitted on the pixel grid. Coordinates are in pixels, y measured from the top.
func renderGlyph(_ px: Int) -> CGImage {
    let ctx = makeContext(px, px)
    // Flip to top-left origin so the pixel tables below read naturally.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(color(0x000000))

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    let body: CGRect, radius: CGFloat
    let cuts: [CGRect]
    if px == 16 {
        body = rect(1, 1, 14, 14); radius = 3
        cuts = [
            rect(4, 4, 8, 2),   // crossbar
            rect(7, 6, 2, 5),   // stem
            rect(6, 11, 4, 1),  // I-beam foot
        ]
    } else {
        body = rect(2, 2, 28, 28); radius = 6
        cuts = [
            rect(8, 8, 16, 4),   // crossbar
            rect(14, 12, 4, 10), // stem
            rect(11, 21, 10, 3), // I-beam foot
        ]
    }
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
    // Knock the letter out of the tile (cuts overlap, so clear rather than even-odd).
    ctx.setBlendMode(.clear)
    for c in cuts { ctx.fill(c) }
    return ctx.makeImage()!
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: render <out-dir>\n".data(using: .utf8)!)
    exit(2)
}
let out = args[1]
let iconset = out + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(renderAppIcon(base), "\(iconset)/icon_\(base)x\(base).png")
    writePNG(renderAppIcon(base * 2), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
writePNG(renderAppIcon(1024), out + "/TypeMacX-1024.png")
writePNG(renderGlyph(16), out + "/glyph.png")
writePNG(renderGlyph(32), out + "/glyph@2x.png", dpi: 144)
print("rendered to \(out)")
