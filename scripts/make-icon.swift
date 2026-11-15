// Peeky 앱 아이콘을 그려 Resources/AppIcon.icns와 docs/images/icon.png를 만든다.
// 실행: swift scripts/make-icon.swift
import AppKit

func draw(in size: CGFloat) {
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // 배경: macOS 아이콘 격자에 맞춘 둥근 사각형
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.36, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.16, green: 0.72, blue: 0.80, alpha: 1))!.draw(in: tile, angle: -60)

    // 위쪽: 노치가 있는 메뉴 막대
    context.saveGState()
    tile.addClip()
    NSColor(srgbRed: 0.08, green: 0.09, blue: 0.16, alpha: 0.85).setFill()
    NSBezierPath(rect: NSRect(x: 100, y: 760, width: 824, height: 164)).fill()
    let notch = NSBezierPath(roundedRect: NSRect(x: 402, y: 690, width: 220, height: 160), xRadius: 46, yRadius: 46)
    NSColor.black.setFill()
    notch.fill()
    // 노치 오른쪽의 메뉴 막대 아이콘들
    NSColor.white.withAlphaComponent(0.85).setFill()
    for x in [668.0, 732, 796] {
        NSBezierPath(ovalIn: NSRect(x: x, y: 820, width: 34, height: 34)).fill()
    }
    context.restoreGState()

    // 아래로 내려온 Peeky 바
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24 * scale), blur: 50 * scale,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
    let bar = NSBezierPath(roundedRect: NSRect(x: 170, y: 420, width: 684, height: 190), xRadius: 64, yRadius: 64)
    NSColor.white.setFill()
    bar.fill()
    context.restoreGState()

    // 바 안의 숨어 있던 아이콘들
    let colors: [NSColor] = [
        NSColor(srgbRed: 0.98, green: 0.45, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.99, green: 0.76, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.24, green: 0.78, blue: 0.47, alpha: 1),
        NSColor(srgbRed: 0.33, green: 0.36, blue: 0.95, alpha: 1),
    ]
    for (i, color) in colors.enumerated() {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 318 + CGFloat(i) * 104, y: 470, width: 76, height: 90),
                     xRadius: 22, yRadius: 22).fill()
    }

    // 좌우 화살표
    NSColor(srgbRed: 0.45, green: 0.47, blue: 0.58, alpha: 1).setStroke()
    for (x, dir) in [(262.0, -1.0), (762.0, 1.0)] {
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: x - dir * 18, y: 555))
        chevron.line(to: NSPoint(x: x + dir * 18, y: 515))
        chevron.line(to: NSPoint(x: x - dir * 18, y: 475))
        chevron.lineWidth = 22
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()
    }
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PeekyIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try png(512).write(to: URL(fileURLWithPath: "docs/images/icon.png"))
