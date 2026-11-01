// SPDX-License-Identifier: GPL-3.0
import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
        let base = NSBezierPath(roundedRect: NSRect(x: 38, y: 38, width: 948, height: 948), xRadius: 220, yRadius: 220)
        NSGradient(starting: NSColor(red: 0.20, green: 0.17, blue: 0.29, alpha: 1), ending: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))!.draw(in: base, angle: -60)
        let plate = NSBezierPath(roundedRect: NSRect(x: 188, y: 244, width: 648, height: 546), xRadius: 128, yRadius: 128)
        NSGradient(starting: NSColor(red: 0.75, green: 0.66, blue: 1, alpha: 1), ending: NSColor(red: 0.43, green: 0.34, blue: 0.75, alpha: 1))!.draw(in: plate, angle: -90)
        NSColor(red: 0.10, green: 0.09, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 359, y: 666, width: 306, height: 180), xRadius: 50, yRadius: 50).fill()
        NSColor.white.withAlphaComponent(0.88).setFill()
        for index in 0..<3 {
            NSBezierPath(roundedRect: NSRect(x: 290 + index * 160, y: 360, width: 118, height: 103), xRadius: 28, yRadius: 28).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
