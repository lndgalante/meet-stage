#!/usr/bin/env swift

import AppKit
import Foundation

private enum IconGenerationError: LocalizedError {
    case missingMaster(URL)
    case image
    case bitmapContext
    case pngRepresentation

    var errorDescription: String? {
        switch self {
        case let .missingMaster(url):
            "The 1024 px master icon is missing at \(url.path)."
        case .image:
            "Could not read the master app icon."
        case .bitmapContext:
            "Could not create an app icon bitmap context."
        case .pngRepresentation:
            "Could not encode an app icon as PNG."
        }
    }
}

private let fileManager = FileManager.default
private let scriptURL = URL(
    fileURLWithPath: CommandLine.arguments.first ?? #filePath
).standardizedFileURL
private let defaultProjectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let outputRoot =
    CommandLine.arguments.dropFirst().first.map {
        URL(fileURLWithPath: $0).standardizedFileURL
    } ?? defaultProjectRoot

private let brandDirectory = outputRoot.appendingPathComponent("Brand", isDirectory: true)
private let masterURL = brandDirectory.appendingPathComponent("BetterMeets-AppIcon-1024.png")
private let sizeDirectory = brandDirectory.appendingPathComponent("BetterMeets-sizes", isDirectory: true)
private let resourceDirectory = outputRoot.appendingPathComponent("Resources", isDirectory: true)

guard fileManager.fileExists(atPath: masterURL.path) else {
    throw IconGenerationError.missingMaster(masterURL)
}
guard let sourceImage = NSImage(contentsOf: masterURL) else {
    throw IconGenerationError.image
}
var sourceRect = NSRect(origin: .zero, size: sourceImage.size)
guard let sourceCGImage = sourceImage.cgImage(forProposedRect: &sourceRect, context: nil, hints: nil) else {
    throw IconGenerationError.image
}

private func resizedPNG(size: Int) throws -> Data {
    guard
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw IconGenerationError.bitmapContext
    }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let image = context.makeImage() else {
        throw IconGenerationError.image
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.pngRepresentation
    }
    return data
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndianValue = value.bigEndian
    withUnsafeBytes(of: &bigEndianValue) { bytes in
        data.append(contentsOf: bytes)
    }
}

private func makeICNSData(chunks: [(type: String, pixels: Int)]) throws -> Data {
    let payloads = try chunks.map { chunk -> (type: String, data: Data) in
        (chunk.type, try resizedPNG(size: chunk.pixels))
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
        ("icon_512x512@2x.png", 1024)
    ]

    for export in exports {
        try resizedPNG(size: export.pixels).write(
            to: sizeDirectory.appendingPathComponent(export.name),
            options: .atomic
        )
    }

    let iconURL = resourceDirectory.appendingPathComponent("BetterMeets.icns")
    let icnsChunks = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024)
    ]
    try makeICNSData(chunks: icnsChunks).write(to: iconURL, options: .atomic)
}

try rebuildIconAssets()
print("Generated BetterMeets app-icon assets from \(masterURL.path)")
