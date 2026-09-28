import Foundation
import ImageIO
import Vision

/// Normalized Vision coordinates (origin at the lower left).
struct MockupContourResult: Sendable {
    let contours: [[CGPoint]]
    let topLevelContours: [[CGPoint]]
    let bodyCandidateIndices: [Int]
}

/// Detection only: no image pixels are changed and no files are written.
enum MockupContourDetector {
    nonisolated static func detect(
        url: URL,
        contrast: Float,
        contrastPivot: Float?,
        detectsDarkOnLight: Bool,
        maximumImageDimension: Int
    ) throws -> MockupContourResult {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = contrast
        request.contrastPivot = contrastPivot.map { NSNumber(value: $0) }
        request.detectsDarkOnLight = detectsDarkOnLight
        request.maximumImageDimension = maximumImageDimension
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first else {
            return MockupContourResult(contours: [], topLevelContours: [], bodyCandidateIndices: [])
        }
        var contours: [[CGPoint]] = []
        for index in 0..<observation.contourCount {
            try Task.checkCancellation()
            let contour = try observation.contour(at: index)
            contours.append(contour.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        }
        let topLevelContours = observation.topLevelContours.map { contour in
            contour.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        }
        let isRotated = [5, 6, 7, 8].contains(Int(orientation.rawValue))
        let imageSize = CGSize(width: isRotated ? image.height : image.width,
                               height: isRotated ? image.width : image.height)
        return MockupContourResult(contours: contours, topLevelContours: topLevelContours,
                                   bodyCandidateIndices: bodyCandidates(in: contours, imageSize: imageSize))
    }

    /// A geometric shortlist, not semantic recognition or a confirmed cutout.
    /// Prefer the largest phone- or tablet-shaped silhouette, retaining the original points
    /// so small protrusions such as side buttons are not simplified away.
    nonisolated static func bodyCandidates(in contours: [[CGPoint]], imageSize: CGSize) -> [Int] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        var candidates: [(index: Int, area: CGFloat)] = []
        for (index, points) in contours.enumerated() {
            guard points.count >= 4 else { continue }
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { continue }
            let width = maxX - minX, height = maxY - minY
            // Reject image borders, tiny controls and cropped-off devices.
            guard minX > 0.002, minY > 0.002, maxX < 0.998, maxY < 0.998,
                  width * height >= 0.025 else { continue }
            let pixelWidth = width * imageSize.width
            let pixelHeight = height * imageSize.height
            let aspect = min(pixelWidth, pixelHeight) / max(pixelWidth, pixelHeight)
            // Include wider iPad bodies in either orientation while rejecting square controls.
            guard (0.35...0.85).contains(aspect) else { continue }
            var twiceArea: CGFloat = 0
            for i in points.indices {
                let next = points[(i + 1) % points.count]
                twiceArea += points[i].x * next.y - next.x * points[i].y
            }
            let area = abs(twiceArea) / 2
            // Broken fragments and irregular wallpaper regions are poor candidates.
            guard area / (width * height) >= 0.8 else { continue }
            candidates.append((index, area))
        }
        return candidates.sorted {
            $0.area == $1.area ? $0.index < $1.index : $0.area > $1.area
        }.map(\.index)
    }

}
