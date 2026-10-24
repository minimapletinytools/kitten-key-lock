import AppKit
import Foundation

// Renders AppIcon.iconset for iconutil.
// Usage: swift Tools/make-icon.swift <output-directory>

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: outputDirectory,
                                         withIntermediateDirectories: true)

let orange = NSColor(calibratedRed: 0.99, green: 0.66, blue: 0.28, alpha: 1)
let coral = NSColor(calibratedRed: 0.93, green: 0.29, blue: 0.38, alpha: 1)

func renderIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels,
                                     pixelsHigh: pixels,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        return nil
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context

    let size = CGFloat(pixels)
    let inset = size * 0.055
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let background = NSBezierPath(roundedRect: rect,
                                  xRadius: size * 0.21,
                                  yRadius: size * 0.21)
    if let gradient = NSGradient(colors: [orange, coral]) {
        gradient.draw(in: background, angle: -90)
    }

    if let symbol = NSImage(systemSymbolName: "pawprint.fill",
                            accessibilityDescription: nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.50,
                                                        weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let image = symbol.withSymbolConfiguration(configuration) {
            let symbolSize = image.size
            let origin = NSPoint(x: (size - symbolSize.width) / 2,
                                 y: (size - symbolSize.height) / 2)
            image.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

var cache: [Int: Data] = [:]
for variant in variants {
    let data: Data
    if let cached = cache[variant.pixels] {
        data = cached
    } else if let rendered = renderIcon(pixels: variant.pixels) {
        cache[variant.pixels] = rendered
        data = rendered
    } else {
        FileHandle.standardError.write("could not render \(variant.pixels)px icon\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(variant.name)
    do {
        try data.write(to: url)
    } catch {
        FileHandle.standardError.write("could not write \(url.path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

print("wrote \(variants.count) icon images to \(outputDirectory)")
