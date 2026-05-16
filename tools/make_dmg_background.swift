// Generates the DMG window background (1x + 2x) into tools/dmg/.
// Run:  swift tools/make_dmg_background.swift
//
// Window is 600×400. Finder draws the app icon (~x150) and the Applications
// drop-link (~x450) on top of this image at y≈205 (from top). We paint the
// branding and a guiding arrow; the icon slots are left clear.

import AppKit

let W: CGFloat = 600
let H: CGFloat = 400
let outDir = URL(fileURLWithPath: "tools/dmg")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(scale: CGFloat) -> Data {
    let pxW = Int(W * scale), pxH = Int(H * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // --- Background gradient (light, neutral) ---
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.972, green: 0.975, blue: 0.984, alpha: 1).cgColor,
        NSColor(srgbRed: 0.918, green: 0.925, blue: 0.941, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // --- Faint brand wash, top-left ---
    let wash = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.30, green: 0.42, blue: 0.85, alpha: 0.10).cgColor,
        NSColor(srgbRed: 0.30, green: 0.42, blue: 0.85, alpha: 0.0).cgColor,
    ] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(wash,
        startCenter: CGPoint(x: 90, y: H - 40), startRadius: 0,
        endCenter:   CGPoint(x: 90, y: H - 40), endRadius: 320, options: [])

    // --- Text helper (top-origin Y) ---
    func drawCentered(_ s: String, font: NSFont, color: NSColor, topY: CGFloat) {
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let sz = attr.size()
        attr.draw(at: NSPoint(x: (W - sz.width) / 2, y: H - topY - sz.height))
    }

    drawCentered("MUBAR",
                 font: .systemFont(ofSize: 36, weight: .heavy),
                 color: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
                 topY: 46)
    drawCentered("Live system stats, right in your menu bar.",
                 font: .systemFont(ofSize: 13, weight: .regular),
                 color: NSColor(srgbRed: 0.52, green: 0.52, blue: 0.56, alpha: 1),
                 topY: 90)
    drawCentered("Drag MUBAR onto the Applications folder to install",
                 font: .systemFont(ofSize: 11, weight: .medium),
                 color: NSColor(srgbRed: 0.58, green: 0.58, blue: 0.62, alpha: 1),
                 topY: 320)

    // --- Guiding arrow between the two icon slots (y≈205 from top) ---
    let arrowY = H - 205
    let arrowColor = NSColor(srgbRed: 0.62, green: 0.65, blue: 0.72, alpha: 1)
    arrowColor.setStroke()
    arrowColor.setFill()

    let shaft = NSBezierPath()
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 247, y: arrowY))
    shaft.line(to: NSPoint(x: 343, y: arrowY))
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 365, y: arrowY))
    head.line(to: NSPoint(x: 341, y: arrowY + 13))
    head.line(to: NSPoint(x: 341, y: arrowY - 13))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
print("wrote tools/dmg/background.png + @2x")
