import AppKit
import ImageIO
import UniformTypeIdentifiers

/// File-backed stage-logo persistence. Imported images are inspected without a
/// full-size decode, downsampled to a bounded pixel size, encoded as PNG, and
/// written atomically under Application Support.
struct StageLogoStore {
    static let storageVersion = 1
    static let maximumInputDataSize = 10 * 1_024 * 1_024
    static let maximumSourceDimension = 8_192
    static let maximumSourcePixelCount = 32_000_000
    static let maximumStoredDimension = 2_048
    static let maximumStoredDataSize = 16 * 1_024 * 1_024

    private static let fileName = "stage-logo.png"

    let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) -> StageLogoStore {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return StageLogoStore(
            directoryURL:
                applicationSupport
                .appendingPathComponent("BetterMeets", isDirectory: true)
                .appendingPathComponent("StageAssets", isDirectory: true),
            fileManager: fileManager
        )
    }

    var fileURL: URL {
        directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    func load() -> NSImage? {
        guard
            let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
            data.count <= Self.maximumStoredDataSize
        else { return nil }
        return NSImage(data: data)
    }

    func save(importedData: Data) throws -> NSImage {
        let normalizedData = try Self.normalizedPNG(from: importedData)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try normalizedData.write(to: fileURL, options: .atomic)
        guard let image = NSImage(data: normalizedData), image.isValid else {
            throw StageLogoStoreError.encodingFailed
        }
        return image
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    static func normalizedPNG(from importedData: Data) throws -> Data {
        guard importedData.count <= maximumInputDataSize else {
            throw StageLogoStoreError.inputTooLarge
        }
        guard
            let source = CGImageSourceCreateWithData(importedData as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0,
            width <= maximumSourceDimension,
            height <= maximumSourceDimension,
            !width.multipliedReportingOverflow(by: height).overflow,
            width * height <= maximumSourcePixelCount
        else {
            throw StageLogoStoreError.invalidImageDimensions
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maximumStoredDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw StageLogoStoreError.decodingFailed
        }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw StageLogoStoreError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StageLogoStoreError.encodingFailed
        }

        let data = output as Data
        guard !data.isEmpty, data.count <= maximumStoredDataSize else {
            throw StageLogoStoreError.outputTooLarge
        }
        return data
    }
}

enum StageLogoStoreError: Error, Equatable {
    case inputTooLarge
    case invalidImageDimensions
    case decodingFailed
    case encodingFailed
    case outputTooLarge
}
