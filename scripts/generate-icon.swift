#!/usr/bin/env swift
// Draws the app icon: a deck of glass layers, the top one carrying a sound wave that
// settles into a calm line.
// Usage: scripts/generate-icon.swift <AppIcon.appiconset folder>
import AppKit

let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawLayer(_ context: CGContext, rect: CGRect, top: CGColor, bottom: CGColor, edge: CGFloat) {
    let path = rounded(rect, 66)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: color(0x050817, 0.5))
    context.addPath(path)
    context.setFillColor(color(0x10152F, 0.35))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient([top, bottom]),
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    // A soft reflection across the upper part of the glass.
    context.drawLinearGradient(
        gradient([color(0xFFFFFF, 0.30), color(0xFFFFFF, 0)]),
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY + 20),
        options: []
    )
    context.restoreGState()

    // A bright rim that fades downward, as on real glass.
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(5)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xFFFFFF, edge), color(0xFFFFFF, 0.05)]),
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    context.restoreGState()
}

func render() -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // The tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.38))
    context.addPath(rounded(tile, tileRadius))
    context.setFillColor(color(0x151A3C))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(rounded(tile, tileRadius))
    context.clip()
    context.drawLinearGradient(
        gradient([color(0x2A3A86), color(0x1A1D4E), color(0x0F1230)]),
        start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY),
        options: []
    )
    context.drawRadialGradient(
        gradient([color(0x6B7CFF, 0.42), color(0x6B7CFF, 0)]),
        startCenter: CGPoint(x: 380, y: 700), startRadius: 0,
        endCenter: CGPoint(x: 380, y: 700), endRadius: 520,
        options: []
    )
    context.restoreGState()

    // The deck, back to front.
    let width: CGFloat = 520
    let height: CGFloat = 340
    drawLayer(
        context, rect: CGRect(x: 340, y: 500, width: width - 90, height: height - 70),
        top: color(0x8B7BFF, 0.30), bottom: color(0x4C3FC4, 0.30), edge: 0.35
    )
    drawLayer(
        context, rect: CGRect(x: 292, y: 400, width: width - 40, height: height - 30),
        top: color(0x7C9BFF, 0.42), bottom: color(0x3B48C9, 0.42), edge: 0.5
    )
    let front = CGRect(x: 252, y: 262, width: width, height: height)
    drawLayer(context, rect: front, top: color(0xA9C4FF, 0.62), bottom: color(0x4D6BE6, 0.62), edge: 0.85)

    // A sound wave on the front layer that settles into a calm line.
    context.saveGState()
    context.addPath(rounded(front, 66))
    context.clip()
    let wave = CGMutablePath()
    let startX = front.minX + 58
    let span = front.width - 116
    for step in 0...400 {
        let progress = CGFloat(step) / 400
        let amplitude = 122 * exp(-3.4 * progress) * (1 - pow(progress, 6))
        let y = front.midY + amplitude * sin(progress * .pi * 9)
        let point = CGPoint(x: startX + span * progress, y: y)
        if step == 0 {
            wave.move(to: point)
        } else {
            wave.addLine(to: point)
        }
    }
    context.addPath(wave)
    context.setLineWidth(24)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xFFFFFF, 1), color(0xFFFFFF, 0.92), color(0xFFFFFF, 0.5)]),
        start: CGPoint(x: startX, y: front.midY),
        end: CGPoint(x: startX + span, y: front.midY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    return context.makeImage()!
}

func write(_ image: CGImage, pixels: Int, to url: URL) {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    graphics.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let image = render()
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        write(image, pixels: points * scale, to: folder.appendingPathComponent(name))
        entries.append(
            #"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#
        )
    }
}
let contents = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
