#!/usr/bin/env swift

import AppKit
import Foundation

private struct RGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        red = CGFloat((hex >> 16) & 0xff) / 255
        green = CGFloat((hex >> 8) & 0xff) / 255
        blue = CGFloat(hex & 0xff) / 255
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private let fileManager = FileManager.default
private let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
private let defaultProjectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let outputRoot = CommandLine.arguments.dropFirst().first.map {
    URL(fileURLWithPath: $0).standardizedFileURL
} ?? defaultProjectRoot

private let brandDirectory = outputRoot.appendingPathComponent("Brand", isDirectory: true)
private let sizeDirectory = brandDirectory.appendingPathComponent("BetterMeets-sizes", isDirectory: true)
private let resourceDirectory = outputRoot.appendingPathComponent("Resources", isDirectory: true)

private func point(_ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> CGPoint {
    CGPoint(x: x * scale, y: y * scale)
}

private func leftWindowPath(scale: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: point(0.132, 0.284, scale: scale))
    path.addCurve(
        to: point(0.108, 0.310, scale: scale),
        control1: point(0.119, 0.284, scale: scale),
        control2: point(0.108, 0.295, scale: scale)
    )
    path.addLine(to: point(0.108, 0.690, scale: scale))
    path.addCurve(
        to: point(0.135, 0.713, scale: scale),
        control1: point(0.108, 0.709, scale: scale),
        control2: point(0.122, 0.720, scale: scale)
    )
    path.addLine(to: point(0.268, 0.640, scale: scale))
    path.addCurve(
        to: point(0.281, 0.614, scale: scale),
        control1: point(0.277, 0.634, scale: scale),
        control2: point(0.281, 0.625, scale: scale)
    )
    path.addLine(to: point(0.281, 0.386, scale: scale))
    path.addCurve(
        to: point(0.268, 0.360, scale: scale),
        control1: point(0.281, 0.375, scale: scale),
        control2: point(0.277, 0.366, scale: scale)
    )
    path.closeSubpath()
    return path
}

private func mirroredPath(_ source: CGPath, scale: CGFloat) -> CGPath {
    var transform = CGAffineTransform(translationX: scale, y: 0).scaledBy(x: -1, y: 1)
    return source.copy(using: &transform) ?? source
}

private func drawIcon(size: Int) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "BetterMeetsIcon", code: 1)
    }

    let scale = CGFloat(size)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: scale, height: scale))

    let tileRect = CGRect(
        x: scale * 0.025,
        y: scale * 0.031,
        width: scale * 0.950,
        height: scale * 0.950
    )
    let tilePath = CGPath(
        roundedRect: tileRect,
        cornerWidth: scale * 0.190,
        cornerHeight: scale * 0.190,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -scale * 0.012),
        blur: scale * 0.025,
        color: RGBColor(0x151719, alpha: 0.62).cgColor
    )
    context.addPath(tilePath)
    context.setFillColor(RGBColor(0x4d4d4d).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [RGBColor(0x565656).cgColor, RGBColor(0x484848).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: scale * 0.5, y: tileRect.maxY),
        end: CGPoint(x: scale * 0.5, y: tileRect.minY),
        options: []
    )
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(RGBColor(0x747474, alpha: 0.92).cgColor)
    context.setLineWidth(scale * 0.014)
    context.strokePath()

    let paper = RGBColor(0xf4f4f4).cgColor
    let leftPath = leftWindowPath(scale: scale)
    context.addPath(leftPath)
    context.setFillColor(paper)
    context.fillPath()
    context.addPath(mirroredPath(leftPath, scale: scale))
    context.fillPath()

    let stageRect = CGRect(
        x: scale * 0.318,
        y: scale * 0.284,
        width: scale * 0.364,
        height: scale * 0.432
    )
    let stagePath = CGPath(
        roundedRect: stageRect,
        cornerWidth: scale * 0.064,
        cornerHeight: scale * 0.064,
        transform: nil
    )
    context.addPath(stagePath)
    context.setFillColor(RGBColor(0xd2d2d2).cgColor)
    context.fillPath()

    let stageInset = scale * 0.046
    let stageOpening = stageRect.insetBy(dx: stageInset, dy: stageInset)
    let stageOpeningPath = CGPath(
        roundedRect: stageOpening,
        cornerWidth: scale * 0.025,
        cornerHeight: scale * 0.025,
        transform: nil
    )
    context.addPath(stageOpeningPath)
    context.setFillColor(RGBColor(0x4d4d4d).cgColor)
    context.fillPath()

    guard let image = context.makeImage() else {
        throw NSError(domain: "BetterMeetsIcon", code: 2)
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BetterMeetsIcon", code: 3)
    }
    return data
}

private func writeIcon(size: Int, to url: URL) throws {
    try drawIcon(size: size).write(to: url, options: .atomic)
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndianValue = value.bigEndian
    withUnsafeBytes(of: &bigEndianValue) { bytes in
        data.append(contentsOf: bytes)
    }
}

private func makeICNSData(chunks: [(type: String, pixels: Int)]) throws -> Data {
    let payloads = try chunks.map { chunk -> (type: String, data: Data) in
        (chunk.type, try drawIcon(size: chunk.pixels))
    }
    let totalLength = 8 + payloads.reduce(0) { $0 + 8 + $1.data.count }

    var result = Data("icns".utf8)
    appendUInt32(UInt32(totalLength), to: &result)
    for payload in payloads {
        result.append(Data(payload.type.utf8))
        appendUInt32(UInt32(payload.data.count + 8), to: &result)
        result.append(payload.data)
    }
    return result
}

private func rebuildIconAssets() throws {
    try fileManager.createDirectory(at: sizeDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: resourceDirectory, withIntermediateDirectories: true)

    let exports: [(name: String, pixels: Int)] = [
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

    try writeIcon(size: 1024, to: brandDirectory.appendingPathComponent("BetterMeets-AppIcon-1024.png"))
    for export in exports {
        try writeIcon(size: export.pixels, to: sizeDirectory.appendingPathComponent(export.name))
    }

    let iconURL = resourceDirectory.appendingPathComponent("BetterMeets.icns")
    let icnsChunks = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024),
    ]
    try makeICNSData(chunks: icnsChunks).write(to: iconURL, options: .atomic)
}

try rebuildIconAssets()
print("Generated BetterMeets app-icon assets in \(outputRoot.path)")
