import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: build_iconset.swift <source-icon.png> <output.iconset>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Error: could not load source icon PNG at \(sourceURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderResizedPNG(from image: NSImage, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    ctx?.imageInterpolation = .high
    NSGraphicsContext.current = ctx

    let fullRect = NSRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize))
    let inset = CGFloat(pixelSize) * 0.06
    let iconRect = fullRect.insetBy(dx: inset, dy: inset)
    let corner = iconRect.width * 0.225
    let squircle = NSBezierPath(roundedRect: iconRect, xRadius: corner, yRadius: corner)
    squircle.addClip()
    image.draw(in: iconRect, from: .zero, operation: .copy, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    guard let data = renderResizedPNG(from: sourceImage, pixelSize: px) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }
    try data.write(to: iconsetURL.appendingPathComponent(filename))
}
print("Built iconset from \(sourceURL.path) at \(iconsetURL.path)")
