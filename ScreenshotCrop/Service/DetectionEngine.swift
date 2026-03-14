import AppKit
import Accelerate

struct DetectionEngine {
    
    func detect(in image: NSImage) -> CGRect {
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return .zero
        }
        
        let ptr = CFDataGetBytePtr(data)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        
        // グレースケール化して輝度分散を計算
        var rowVariance = [Double](repeating: 0, count: height)
        var colVariance = [Double](repeating: 0, count: width)
        
        for y in 0..<height {
            var rowPixels = [Double]()
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Double(ptr![offset])
                let g = Double(ptr![offset+1])
                let b = Double(ptr![offset+2])
                let luminance = 0.299*r + 0.587*g + 0.114*b
                rowPixels.append(luminance)
                colVariance[x] += luminance
            }
            
            let mean = rowPixels.reduce(0,+) / Double(width)
            let variance = rowPixels.map { pow($0 - mean, 2) }.reduce(0,+) / Double(width)
            rowVariance[y] = variance
        }
        
        // 縦方向平均
        for x in 0..<width {
            colVariance[x] /= Double(height)
        }
        
        // 行方向の低分散領域を探す（UIは分散大きい）
        let thresholdRow = rowVariance.max()! * 0.2
        
        let top = rowVariance.firstIndex { $0 > thresholdRow } ?? 0
        let bottom = rowVariance.lastIndex { $0 > thresholdRow } ?? height
        
        // 横方向は単純中央80%使用
        let left = Int(Double(width) * 0.05)
        let right = Int(Double(width) * 0.95)
        
        let cropWidth = right - left
        let cropHeight = bottom - top
        
        return CGRect(x: left,
                      y: height - bottom,
                      width: cropWidth,
                      height: cropHeight)
    }
}
