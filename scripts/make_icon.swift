#!/usr/bin/env swift
// 生成 AppIcon.iconset：紫渐变圆角方块 + 白色对话气泡 + A/文
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func makeIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let s = size / 1024.0

    // 底板
    let inset = 76 * s
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = 214 * s
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.60, green: 0.42, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.30, green: 0.15, blue: 0.72, alpha: 1),
        NSColor(srgbRed: 0.14, green: 0.06, blue: 0.36, alpha: 1)
    ], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    gradient.draw(in: bodyPath, angle: -72)

    // 顶部高光
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    let gloss = NSBezierPath(ovalIn: NSRect(x: body.minX - 60 * s,
                                            y: body.midY + 40 * s,
                                            width: body.width + 120 * s,
                                            height: body.height * 0.85))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16),
                        NSColor.white.withAlphaComponent(0.0)])?
        .draw(in: gloss, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 对话气泡
    let bubble = NSRect(x: 236 * s, y: 352 * s, width: 552 * s, height: 330 * s)
    let bubblePath = NSBezierPath(roundedRect: bubble, xRadius: 96 * s, yRadius: 96 * s)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 330 * s, y: 372 * s))
    tail.line(to: NSPoint(x: 330 * s, y: 236 * s))
    tail.line(to: NSPoint(x: 470 * s, y: 366 * s))
    tail.close()
    bubblePath.append(tail)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 26 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor.white.setFill()
    bubblePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 气泡里的字
    let dark = NSColor(srgbRed: 0.17, green: 0.08, blue: 0.40, alpha: 1)
    let fontA = NSFont.systemFont(ofSize: 208 * s, weight: .bold)
    let fontHan = NSFont.systemFont(ofSize: 214 * s, weight: .semibold)

    func draw(_ text: String, font: NSFont, centerX: CGFloat, baseline: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dark]
        let str = NSAttributedString(string: text, attributes: attrs)
        let bounds = str.size()
        str.draw(at: NSPoint(x: centerX - bounds.width / 2,
                             y: baseline - bounds.height / 2))
    }

    draw("A", font: fontA, centerX: 404 * s, baseline: 520 * s)
    draw("文", font: fontHan, centerX: 616 * s, baseline: 520 * s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, px) in variants {
    let rep = makeIcon(pixels: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

// 顺便存一张预览图
let preview = makeIcon(pixels: 512)
if let data = preview.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/../icon-preview.png"))
}
print("iconset 已生成: \(outDir)")
