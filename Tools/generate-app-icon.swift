#!/usr/bin/env swift
// Original Openlist artwork, generated with AppKit. Run from the repository root.
import AppKit
import Foundation

let output = URL(fileURLWithPath: "openlist/Assets.xcassets/AppIcon.appiconset")
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.76, blue: 0.65, alpha: 1),
                   ending: NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.44, alpha: 1))!.draw(in: tile, angle: -90)
        NSColor.white.setStroke()
        for y: CGFloat in [674, 512, 350] {
            let line = NSBezierPath()
            line.lineWidth = 44; line.lineCapStyle = .round
            line.move(to: NSPoint(x: 459, y: y)); line.line(to: NSPoint(x: 737, y: y)); line.stroke()
            let check = NSBezierPath()
            check.lineWidth = 36; check.lineCapStyle = .round; check.lineJoinStyle = .round
            check.move(to: NSPoint(x: 285, y: y)); check.line(to: NSPoint(x: 323, y: y - 35))
            check.line(to: NSPoint(x: 387, y: y + 39)); check.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
