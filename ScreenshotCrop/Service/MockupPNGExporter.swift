import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct MockupBatchResult: Sendable {
    var saved: [URL] = []
    var skipped: [String] = []
    var failed: [String] = []
}

enum MockupPNGExporter {
    nonisolated static func orientedSize(url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        return CGSize(width: rotated ? height.doubleValue : width.doubleValue,
                      height: rotated ? width.doubleValue : height.doubleValue)
    }

    nonisolated static func saveBatch(
        urls: [URL], referenceURL: URL, points: [CGPoint], folderName: String, fileNameBase: String,
        progress: @Sendable (Int) async -> Void
    ) async throws -> MockupBatchResult {
        let expectedSize = try orientedSize(url: referenceURL)
        var result = await MockupBatchResult()
        var nextNumber = 1
        for (index, url) in urls.enumerated() {
            do {
                let size = try orientedSize(url: url)
                if size != expectedSize {
                    result.skipped.append(url.lastPathComponent)
                } else {
                    let output = try autoreleasepool {
                        try save(url: url, points: points, folderName: folderName,
                                 fileNameBase: fileNameBase, startingNumber: nextNumber)
                    }
                    result.saved.append(output)
                    if let suffix = output.deletingPathExtension().lastPathComponent.split(separator: "_").last,
                       let number = Int(suffix) { nextNumber = number + 1 }
                }
            } catch {
                result.failed.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            await progress(index + 1)
        }
        return result
    }

    /// Uses the same lower-left normalized contour as Vision, at source resolution.
    nonisolated static func render(url: URL, points: [CGPoint]) throws -> CGImage {
        guard points.count >= 3,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let image = CIContext().createCGImage(source, from: source.extent) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let path = CGMutablePath()
        let width = CGFloat(image.width), height = CGFloat(image.height)
        path.move(to: CGPoint(x: points[0].x * width, y: points[0].y * height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * width, y: point.y * height))
        }
        path.closeSubpath()
        let bounds = path.boundingBoxOfPath.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !bounds.isEmpty, !bounds.isNull,
              let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.setShouldAntialias(true)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.addPath(path)
        context.clip()
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return result
    }

    nonisolated static func save(url: URL, points: [CGPoint], folderName: String, fileNameBase: String, startingNumber: Int = 1) throws -> URL {
        let names = [folderName, fileNameBase]
        guard names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains(":") }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let image = try render(url: url, points: points)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let folder = url.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var number = max(1, startingNumber)
        while true {
            let output = folder.appendingPathComponent(String(format: "%@_mockup_%03d.png", fileNameBase, number))
            do {
                try (data as Data).write(to: output, options: .withoutOverwriting)
                return output
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                number += 1
            }
        }
    }
}
