// Generates MUBAR's app icon set.
// Run:  swift tools/make_icon.swift
// Writes PNGs into MUBAR/Assets.xcassets/AppIcon.appiconset/
//
// Design: minimal macOS utility icon — a dark charcoal squircle with three
// ascending white capsule bars (a stats/monitor mark). Renders into an exact
// pixel bitmap so sizes are precise (no Retina doubling).

import AppKit

let outDir = URL(fileURLWithPath: "MUBAR/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let S = CGFloat(px)
    let space = CGColorSpaceCreateDeviceRGB()

    // --- Squircle body ---
    let inset = S * 0.092
    let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = body.width * 0.224
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Dark vertical gradient.
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.235, green: 0.235, blue: 0.275, alpha: 1).cgColor,
        NSColor(srgbRed: 0.110, green: 0.110, blue: 0.130, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(bg,
        start: CGPoint(x: 0, y: body.maxY),
        end:   CGPoint(x: 0, y: body.minY), options: [])

    // Soft top sheen.
    let sheen = CGGradient(colorsSpace: space, colors: [
        NSColor(white: 1, alpha: 0.14).cgColor,
        NSColor(white: 1, alpha: 0.0).cgColor,
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(sheen,
        start: CGPoint(x: 0, y: body.maxY),
        end:   CGPoint(x: 0, y: body.maxY - body.height * 0.42), options: [])
    cg.restoreGState()

    // Hairline edge for crispness.
    cg.addPath(squircle)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.06).cgColor)
    cg.setLineWidth(max(S * 0.004, 0.5))
    cg.strokePath()

    // --- Three ascending capsule bars ---
    let barW = S * 0.135
    let gap  = S * 0.052
    let groupW = barW * 3 + gap * 2
    let startX = (S - groupW) / 2
    let heights: [CGFloat] = [0.26, 0.38, 0.50].map { $0 * S }
    let tallest = heights.max()!
    let baseY = (S - tallest) / 2          // bottom-aligned, group centered

    cg.setFillColor(NSColor(white: 0.98, alpha: 1).cgColor)
    for (i, h) in heights.enumerated() {
        let x = startX + CGFloat(i) * (barW + gap)
        let bar = CGRect(x: x, y: baseY, width: barW, height: h)
        let r = barW / 2
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: r, cornerHeight: r, transform: nil))
    }
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]
for (name, px) in sizes {
    try render(px: px).write(to: outDir.appendingPathComponent(name))
    print("wrote \(name) (\(px)px)")
}
print("done")
