import Foundation
import ImageIO
import CoreGraphics
import CryptoKit
import UniformTypeIdentifiers

public struct PreparedImageAsset: Equatable, Sendable {
    public let pngData: Data
    public let width: Int
    public let height: Int
    public let sha256: String
    public let assetFileName: String

    public var metadata: ClipImageMetadata {
        ClipImageMetadata(
            assetFileName: assetFileName,
            width: width,
            height: height,
            byteSize: pngData.count,
            sha256: sha256,
            mimeType: "image/png"
        )
    }
}

public enum ImageValidationError: Error, LocalizedError, Equatable, Sendable {
    case emptyData
    case inputTooLarge(maxBytes: Int)
    case unreadableImage
    case dimensionsOutOfBounds(width: Int, height: Int)
    case encodedPNGTooLarge(maxBytes: Int)
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "Image data is empty."
        case .inputTooLarge(let maxBytes):
            return "Compressed image exceeds limit of \(maxBytes) bytes."
        case .unreadableImage:
            return "Could not decode image data."
        case .dimensionsOutOfBounds(let width, let height):
            return "Image dimensions \(width)x\(height) exceed allowed bounds."
        case .encodedPNGTooLarge(let maxBytes):
            return "Canonical PNG exceeds limit of \(maxBytes) bytes."
        case .persistenceFailed(let msg):
            return "Failed to store image asset: \(msg)"
        }
    }
}

/// Manages bounded image decoding, canonical PNG encoding, SHA-256 content addressing, and safe private storage.
public final class ImageAssetStore: @unchecked Sendable {
    public static let maxCompressedInputBytes = 16 * 1024 * 1024 // 16 MB
    public static let maxCanonicalPNGBytes = 12 * 1024 * 1024    // 12 MB
    public static let maxPixelDimension = 8192
    public static let maxTotalPixels = 33_554_432                 // ~33 MP

    public let directoryURL: URL

    /// Deterministic store-scoped asset directory name derived from the standardized history file identity.
    public static func assetDirectoryName(for storeFileURL: URL) -> String {
        let standardized = storeFileURL.standardizedFileURL
        let rawStem = standardized.deletingPathExtension().lastPathComponent
        let sanitizedScalars = rawStem.unicodeScalars.filter { scalar in
            let v = scalar.value
            return (48...57).contains(v) || (65...90).contains(v) || (97...122).contains(v) || v == 95 || v == 45
        }
        let trimmedStem = String(String.UnicodeScalarView(sanitizedScalars).prefix(24))
        let safeStem = trimmedStem.isEmpty ? "store" : trimmedStem
        let hashPrefix = String(sha256Hex(of: Data(standardized.path.utf8)).prefix(16))
        return "images-\(safeStem)-\(hashPrefix)"
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public init(storeFileURL: URL) {
        let standardized = storeFileURL.standardizedFileURL
        self.directoryURL = standardized
            .deletingLastPathComponent()
            .appendingPathComponent(Self.assetDirectoryName(for: standardized), isDirectory: true)
    }

    /// Strict allowlist preventing path traversal or arbitrary path injection from malformed JSON.
    public static func isSafeAssetFileName(_ fileName: String) -> Bool {
        guard fileName.count == 68, fileName.hasSuffix(".png") else { return false }
        let hexPart = fileName.dropLast(4)
        return hexPart.allSatisfy { ch in
            ("0"..."9").contains(ch) || ("a"..."f").contains(ch)
        }
    }

    public func resolveAssetURL(for metadata: ClipImageMetadata) -> URL? {
        guard Self.isSafeAssetFileName(metadata.assetFileName) else {
            return nil
        }
        return directoryURL.appendingPathComponent(metadata.assetFileName, isDirectory: false)
    }

    public func readPNGData(for metadata: ClipImageMetadata) -> Data? {
        guard let url = resolveAssetURL(for: metadata) else {
            return nil
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let fileSize = (attrs[.size] as? NSNumber)?.int64Value,
              fileSize > 0,
              fileSize <= Int64(Self.maxCanonicalPNGBytes),
              let data = try? Data(contentsOf: url),
              data.count <= Self.maxCanonicalPNGBytes else {
            return nil
        }
        let actualSHA = Self.sha256Hex(of: data)
        let expectedFromName = String(metadata.assetFileName.dropLast(4))
        guard actualSHA == expectedFromName,
              metadata.sha256.isEmpty || actualSHA == metadata.sha256.lowercased() else {
            return nil
        }
        return data
    }

    /// Validates header dimensions BEFORE decoding full pixel buffers, then normalizes to canonical PNG.
    public static func prepareCanonicalPNG(from rawData: Data) -> Result<PreparedImageAsset, ImageValidationError> {
        guard !rawData.isEmpty else {
            return .failure(.emptyData)
        }
        guard rawData.count <= maxCompressedInputBytes else {
            return .failure(.inputTooLarge(maxBytes: maxCompressedInputBytes))
        }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(rawData as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions as CFDictionary) as? [CFString: Any] else {
            return .failure(.unreadableImage)
        }

        guard let rawWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0,
              rawHeight > 0 else {
            return .failure(.unreadableImage)
        }

        guard rawWidth <= maxPixelDimension,
              rawHeight <= maxPixelDimension,
              Int64(rawWidth) * Int64(rawHeight) <= Int64(maxTotalPixels) else {
            return .failure(.dimensionsOutOfBounds(width: rawWidth, height: rawHeight))
        }

        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false
        ]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            return .failure(.unreadableImage)
        }

        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientedImage = applyEXIFOrientationIfNeeded(cgImage, orientation: orientation) ?? cgImage

        let width = orientedImage.width
        let height = orientedImage.height
        guard width > 0,
              height > 0,
              width <= maxPixelDimension,
              height <= maxPixelDimension,
              Int64(width) * Int64(height) <= Int64(maxTotalPixels) else {
            return .failure(.dimensionsOutOfBounds(width: width, height: height))
        }

        let outData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return .failure(.unreadableImage)
        }

        CGImageDestinationAddImage(destination, orientedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return .failure(.unreadableImage)
        }

        let pngData = outData as Data
        guard pngData.count <= maxCanonicalPNGBytes else {
            return .failure(.encodedPNGTooLarge(maxBytes: maxCanonicalPNGBytes))
        }

        let digest = SHA256.hash(data: pngData)
        let shaHex = digest.map { String(format: "%02x", $0) }.joined()
        return .success(PreparedImageAsset(
            pngData: pngData,
            width: width,
            height: height,
            sha256: shaHex,
            assetFileName: "\(shaHex).png"
        ))
    }

    public func saveAssetIfNeeded(_ asset: PreparedImageAsset) throws {
        guard Self.isSafeAssetFileName(asset.assetFileName) else {
            throw ImageValidationError.persistenceFailed("Invalid asset filename")
        }
        let fm = FileManager.default
        try fm.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let targetURL = directoryURL.appendingPathComponent(asset.assetFileName, isDirectory: false)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: targetURL.path, isDirectory: &isDir), !isDir.boolValue,
           let attrs = try? fm.attributesOfItem(atPath: targetURL.path),
           (attrs[.type] as? FileAttributeType) == .typeRegular,
           let existingSize = (attrs[.size] as? NSNumber)?.intValue,
           existingSize == asset.pngData.count,
           let existingData = try? Data(contentsOf: targetURL),
           Self.sha256Hex(of: existingData) == asset.sha256 {
            // Content-addressed file already present with matching SHA-256 bytes.
            return
        }
        try asset.pngData.write(to: targetURL, options: [.atomic])
        try? fm.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: targetURL.path
        )
    }

    /// Removes unreferenced managed image files safely under caller's store flock.
    public func removeOrphanedAssets(retaining referencedItems: [ClipItem]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path),
              let entries = try? fm.contentsOfDirectory(atPath: directoryURL.path) else {
            return
        }
        let referencedNames = Set(referencedItems.compactMap { $0.image?.assetFileName })
        for name in entries where Self.isSafeAssetFileName(name) && !referencedNames.contains(name) {
            try? fm.removeItem(at: directoryURL.appendingPathComponent(name, isDirectory: false))
        }
    }

    private static func applyEXIFOrientationIfNeeded(_ image: CGImage, orientation: UInt32) -> CGImage? {
        guard orientation > 1 && orientation <= 8 else { return nil }
        let width = image.width
        let height = image.height
        let swapAxes = orientation >= 5 && orientation <= 8
        let targetWidth = swapAxes ? height : width
        let targetHeight = swapAxes ? width : height

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        var transform = CGAffineTransform.identity
        switch orientation {
        case 2:
            transform = CGAffineTransform(translationX: CGFloat(width), y: 0).scaledBy(x: -1, y: 1)
        case 3:
            transform = CGAffineTransform(translationX: CGFloat(width), y: CGFloat(height)).rotated(by: .pi)
        case 4:
            transform = CGAffineTransform(translationX: 0, y: CGFloat(height)).scaledBy(x: 1, y: -1)
        case 5:
            transform = CGAffineTransform(translationX: CGFloat(height), y: 0).rotated(by: .pi / 2).scaledBy(x: 1, y: -1)
        case 6:
            transform = CGAffineTransform(translationX: CGFloat(height), y: 0).rotated(by: .pi / 2)
        case 7:
            transform = CGAffineTransform(translationX: 0, y: CGFloat(width)).rotated(by: -.pi / 2).scaledBy(x: 1, y: -1)
        case 8:
            transform = CGAffineTransform(translationX: 0, y: CGFloat(width)).rotated(by: -.pi / 2)
        default:
            break
        }

        ctx.concatenate(transform)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
