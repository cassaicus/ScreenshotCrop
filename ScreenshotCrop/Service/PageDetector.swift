import Cocoa

struct PageDetector {

    // 全ての画像を通じて「安定している」領域を2Dで分析します。
    // RGB各チャンネルで判定を行い、より精密な色の差（見分けのつきにくい薄い色など）を検出します。
    // 面積によるフィルタリングを行い、ノイズを除去して大きな背景領域のみを特定します。
    static func analyzeBackground(images: [[UInt8]], width: Int, height: Int, threshold: UInt8, tolerance: UInt8) -> [Bool] {
        // 画像がない場合は空の配列を返します
        guard !images.isEmpty else { return [] }

        // 背景マスクを初期化します（幅 * 高さ のフラグ配列）
        var mask = [Bool](repeating: false, count: width * height)

        // 1. 各ピクセルが全画像を通じて指定された明るさを持ち、かつ安定しているかチェックします
        // 全ての行をスキャンします
        for y in 0..<height {
            // 現在の行の開始インデックスを計算します（1ピクセル4バイト: RGBA）
            let rowOffset = y * width * 4
            // 現在の行の全ての列をスキャンします
            for x in 0..<width {
                let pixelStartIdx = rowOffset + x * 4

                var isStable = true
                var isBrightEnough = true

                // RGBの各チャンネルについて個別に判定します
                for channelOffset in 0..<3 { // 0:R, 1:G, 2:B (Alphaは無視)
                    var minVal: UInt8 = 255
                    var maxVal: UInt8 = 0

                    for j in 0..<images.count {
                        let pixelValue = images[j][pixelStartIdx + channelOffset]

                        if pixelValue < minVal { minVal = pixelValue }
                        if pixelValue > maxVal { maxVal = pixelValue }

                        // 複数枚の画像間で色が変化していれば不安定とみなします
                        if maxVal - minVal > tolerance {
                            isStable = false
                            break
                        }
                    }

                    if !isStable { break }

                    // 全ての画像において、このチャンネルが閾値以上の明るさを持っているか確認します
                    if minVal < threshold {
                        isBrightEnough = false
                        break
                    }
                }

                // 「指定された明るさ」かつ「全画像で安定（静止）」している場所を背景候補としてマークします
                if isStable && isBrightEnough {
                    mask[y * width + x] = true
                }
            }
        }

        // 2. 面積（ピクセル数）によるフィルタリングを行い、孤立した小さなノイズを除去します
        return filterSmallRegions(mask: mask, width: width, height: height)
    }

    // 連結成分ラベル付け（Connected Component Labeling）を使用して、小さい領域を排除します
    private static func filterSmallRegions(mask: [Bool], width: Int, height: Int) -> [Bool] {
        // 各ピクセルのラベルを保持する配列です
        var labels = [Int](repeating: 0, count: width * height)
        // 次に割り当てるラベル番号です
        var nextLabel = 1
        // Union-Find（素集合データ構造）用の親参照配列です。最初は多めに確保します
        var parent = Array(0...10000)

        // 指定されたラベルのルート親を見つけます（経路圧縮なしの単純実装）
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root {
                root = parent[root]
            }
            return root
        }

        // 2つのラベルが属する集合を統合します
        func union(_ i: Int, _ j: Int) {
            let rootI = find(i)
            let rootJ = find(j)
            if rootI != rootJ {
                parent[rootI] = rootJ
            }
        }

        // 1回目パス：ピクセルを走査し、左または上のピクセルと同じラベルを割り当てます
        for y in 0..<height {
            let rowOffset = y * width
            for x in 0..<width {
                let idx = rowOffset + x
                // 背景候補ピクセルの場合
                if mask[idx] {
                    // 左と上のラベルを取得します
                    let left = (x > 0 && mask[idx - 1]) ? labels[idx - 1] : 0
                    let up = (y > 0 && mask[idx - width]) ? labels[idx - width] : 0

                    if left == 0 && up == 0 {
                        // 周囲にラベルがない場合は新しいラベルを発行します
                        labels[idx] = nextLabel
                        if nextLabel >= parent.count {
                            parent.append(contentsOf: parent.count..<(parent.count + 10000))
                        }
                        parent[nextLabel] = nextLabel
                        nextLabel += 1
                    } else if left != 0 && up == 0 {
                        // 左にだけラベルがある場合はそれを継承します
                        labels[idx] = left
                    } else if left == 0 && up != 0 {
                        // 上にだけラベルがある場合はそれを継承します
                        labels[idx] = up
                    } else {
                        // 両方にラベルがある場合は、左を継承し、上との連結を記録します
                        labels[idx] = left
                        union(left, up)
                    }
                }
            }
        }

        // 各ラベル（ルート）ごとの面積（ピクセル数）をカウントします
        var areaCount = [Int: Int]()
        for i in 0..<width * height {
            if labels[i] != 0 {
                let root = find(labels[i])
                areaCount[root, default: 0] += 1
            }
        }

        // 判定基準：画像全体の0.5%（1/200）以上の面積を持つものだけを「背景」として残します
        let minArea = (width * height) / 200

        // 2回目パス：フィルタリング後の最終的なマスクを生成します
        var filteredMask = [Bool](repeating: false, count: width * height)
        for i in 0..<width * height {
            if labels[i] != 0 {
                let root = find(labels[i])
                if let count = areaCount[root], count >= minArea {
                    filteredMask[i] = true
                }
            }
        }

        return filteredMask
    }

    // 各列（x座標）を分析し、全ての画像において「白に近い色（235以上）」が実質的に一定であるかを判定します。
    // (後方互換性のために維持するか、移行が完了したら削除可能です)
    static func analyzeColumns(images: [[UInt8]], width: Int, height: Int) -> [Bool] {
        guard !images.isEmpty else { return [] }

        var isBackground = [Bool](repeating: false, count: width)
        let whiteThreshold: UInt8 = 235
        let tolerance: UInt8 = 10

        for x in 0..<width {
            var minVal: UInt8 = 255
            var maxVal: UInt8 = 0
            for j in 0..<images.count {
                let pixels = images[j]
                for y in 0..<height {
                    let pixel = pixels[y * width + x]
                    if pixel < minVal { minVal = pixel }
                    if pixel > maxVal { maxVal = pixel }
                }
                if maxVal - minVal > tolerance { break }
            }
            isBackground[x] = (minVal >= whiteThreshold) && (maxVal - minVal <= tolerance)
        }
        return isBackground
    }

    // 画像をRGBAピクセル配列に変換します
    static func rgbaPixels(_ image: NSImage) -> [UInt8]? {
        // CGImageを取得します
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = cg.width
        let height = cg.height

        // 1ピクセル4バイト (RGBA) で配列を確保します
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        // ビットマップコンテキストを作成して描画します
        pixels.withUnsafeMutableBufferPointer { ptr in
            if let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        return pixels
    }

    // 画像をグレースケールピクセル配列に変換します
    static func grayscalePixels(_ image: NSImage) -> [UInt8]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = cg.width
        let height = cg.height

        var pixels = [UInt8](repeating: 0, count: width * height)

        pixels.withUnsafeMutableBufferPointer { ptr in
            if let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        return pixels
    }
}
