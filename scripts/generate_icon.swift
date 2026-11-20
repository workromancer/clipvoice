import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
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
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let corner = size * 0.22
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: corner, yRadius: corner)

    // Background gradient (deep slate-indigo to vibrant teal)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.34, alpha: 1.0),
        NSColor(calibratedRed: 0.19, green: 0.34, blue: 0.72, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.68, alpha: 1.0)
    ])
    gradient?.draw(in: cardPath, angle: -45)

    // Subtle inner highlight border
    NSColor.white.withAlphaComponent(0.22).setStroke()
    cardPath.lineWidth = max(1.0, size * 0.015)
    cardPath.stroke()

    // Clipboard top clip bar
    let clipW = size * 0.30
    let clipH = size * 0.09
    let clipRect = NSRect(
        x: (size - clipW) / 2,
        y: cardRect.maxY - clipH * 0.65,
        width: clipW,
        height: clipH
    )
    let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: clipH * 0.4, yRadius: clipH * 0.4)
    NSColor.white.withAlphaComponent(0.92).setFill()
    clipPath.fill()

    // Voice waveform bars inside the card
    let barHeights: [CGFloat] = [0.16, 0.30, 0.44, 0.24, 0.36, 0.18]
    let barCount = CGFloat(barHeights.count)
    let totalWidth = size * 0.50
    let barWidth = totalWidth / (barCount * 1.65)
    let spacing = barWidth * 0.65
    let startX = (size - (barCount * barWidth + (barCount - 1) * spacing)) / 2
    let centerY = size * 0.47

    NSColor.white.setFill()
    for (idx, hRatio) in barHeights.enumerated() {
        let h = size * hRatio
        let x = startX + CGFloat(idx) * (barWidth + spacing)
        let barRect = NSRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        barPath.fill()
    }

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
    guard let data = renderIcon(pixelSize: px) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }
    try data.write(to: iconsetURL.appendingPathComponent(filename))
}
print("Generated iconset at \(iconsetURL.path)")
