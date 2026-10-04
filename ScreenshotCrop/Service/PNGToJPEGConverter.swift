import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum PNGToJPEGConverter {
    nonisolated static func pngFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ).filter {
            guard $0.pathExtension.lowercased() == "png" else { return false }
            return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// The PNG is removed only after the JPEG has been encoded and written successfully.
    nonisolated static func convert(_ url: URL, quality: Double) throws -> URL {
        guard url.pathExtension.lowercased() == "png",
              quality.isFinite, (0...1).contains(quality),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // JPEG cannot preserve transparency; composite transparent pixels over white.
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let opaqueImage = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientation = metadata[kCGImagePropertyOrientation] {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, opaqueImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

        let output = url.deletingPathExtension().appendingPathExtension("jpg")
        try (data as Data).write(to: output, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: url)
        return output
    }
}
