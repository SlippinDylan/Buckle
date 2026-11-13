import AppKit

// Draw the same buckle mark at every required icon size; no external image assets.
let directory = URL(fileURLWithPath: "build/Buckle.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            fatalError("Cannot create icon drawing context")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.67, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 210, yRadius: 210).fill()
        NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
        let buckle = NSBezierPath(
            roundedRect: NSRect(x: 225, y: 315, width: 574, height: 394), xRadius: 90, yRadius: 90)
        buckle.lineWidth = 64
        buckle.stroke()
        let pin = NSBezierPath()
        pin.move(to: NSPoint(x: 512, y: 315))
        pin.line(to: NSPoint(x: 512, y: 709))
        pin.lineWidth = 64
        pin.lineCapStyle = .round
        pin.stroke()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
