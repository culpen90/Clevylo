#!/usr/bin/env swift
import AppKit

// Original Clevylo artwork. Rebuild from the repository root with:
//   swift scripts/make-icon.swift
// No fonts, downloaded images, or third-party assets are used.
let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = workspace.appendingPathComponent("Clevylo/Assets.xcassets", isDirectory: true)
let output = assets.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: pixels * 4, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ClevyloIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.imageInterpolation = .high
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    let background = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 188, yRadius: 188)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.28, green: 0.27, blue: 0.65, alpha: 1).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Two open pages share a quiet central spine. The bowed left edge and open
    // inner space recall a C without adding a separate letter or decorative badge.
    let leftPage = NSBezierPath()
    leftPage.move(to: NSPoint(x: 493, y: 657))
    leftPage.curve(to: NSPoint(x: 283, y: 712), controlPoint1: NSPoint(x: 426, y: 703), controlPoint2: NSPoint(x: 346, y: 725))
    leftPage.curve(to: NSPoint(x: 258, y: 683), controlPoint1: NSPoint(x: 266, y: 709), controlPoint2: NSPoint(x: 258, y: 698))
    leftPage.line(to: NSPoint(x: 258, y: 386))
    leftPage.curve(to: NSPoint(x: 283, y: 359), controlPoint1: NSPoint(x: 258, y: 369), controlPoint2: NSPoint(x: 268, y: 358))
    leftPage.curve(to: NSPoint(x: 493, y: 306), controlPoint1: NSPoint(x: 369, y: 359), controlPoint2: NSPoint(x: 433, y: 340))
    leftPage.close()

    let rightPage = leftPage.copy() as! NSBezierPath
    let mirror = AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: 1024, tY: 0)
    rightPage.transform(using: mirror)
    NSColor(srgbRed: 0.98, green: 0.98, blue: 1, alpha: 1).setFill()
    leftPage.fill()
    rightPage.fill()

    if pixels >= 64 {
        // At small Dock sizes, the silhouette carries the mark on its own.
        NSColor(srgbRed: 0.28, green: 0.27, blue: 0.65, alpha: 0.5).setStroke()
        for row in 0..<2 {
            let line = NSBezierPath()
            line.lineWidth = 23
            line.lineCapStyle = .round
            let y = 607 - CGFloat(row) * 82
            line.move(to: NSPoint(x: 320, y: y))
            line.curve(to: NSPoint(x: 433, y: y - 29), controlPoint1: NSPoint(x: 360, y: y - 2), controlPoint2: NSPoint(x: 400, y: y - 13))
            line.stroke()
            let reflected = line.copy() as! NSBezierPath
            reflected.transform(using: mirror)
            reflected.stroke()
        }
    }
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ClevyloIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG."])
    }
    return data
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try renderIcon(pixels: points * scale).write(to: output.appendingPathComponent(filename), options: .atomic)
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let metadata: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"), options: .atomic)
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
    .write(to: assets.appendingPathComponent("Contents.json"), options: .atomic)
print("Wrote \(images.count) macOS app icons to \(output.path)")
