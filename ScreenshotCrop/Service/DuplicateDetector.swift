import Foundation
import CoreGraphics
import Vision

/// Protocol for detecting duplicate images.
/// 重複画像を検出するためのプロトコル。
protocol DuplicateDetecting {
    /// Resets the internal state (e.g., clears the previous image reference).
    /// 内部状態をリセットします（例：以前の画像参照をクリアする）。
    func reset()

    /// Checks if the provided image is a duplicate of the previously processed image.
    /// 提供された画像が、以前に処理された画像と重複しているかどうかを確認します。
    /// - Parameter image: The new image to check.
    /// - Parameter image: チェックする新しい画像。
    /// - Returns: `true` if the image is considered a duplicate, `false` otherwise.
    /// - Returns: 画像が重複していると見なされる場合は `true`、そうでない場合は `false`。
    func isDuplicate(_ image: CGImage) async -> Bool

    /// Sets the sensitivity threshold for duplicate detection.
    /// 重複検出の感度しきい値を設定します。
    /// - Parameter value: A value typically between 0.0 and 1.0. Lower values mean stricter matching.
    /// - Parameter value: 通常 0.0 から 1.0 の間の値。値が低いほど厳密な一致を意味します。
    func setThreshold(_ value: Double)
}

/// A duplicate detector that uses the Vision framework's Feature Print to detect similarities.
/// VisionフレームワークのFeature Printを使用して類似性を検出する重複検出器。
/// It ignores minor differences (like a clock ticking) based on the configured threshold.
/// 設定されたしきい値に基づいて、些細な違い（時計の秒針など）を無視します。
class VisionDuplicateDetector: DuplicateDetecting {
    private var lastObservation: VNFeaturePrintObservation?

    /// The distance threshold. If the distance between two images is less than this value,
    /// 距離のしきい値。2つの画像間の距離がこの値より小さい場合、
    /// they are considered duplicates.
    /// それらは重複していると見なされます。
    /// 0.0 means identical. A higher value (e.g., 0.1) allows for some variation.
    /// 0.0 は完全一致を意味します。より高い値（例：0.1）は、ある程度の変動を許容します。
    private var threshold: Double = 0.05 // Default starting value

    func reset() {
        lastObservation = nil
    }

    func setThreshold(_ value: Double) {
        self.threshold = value
    }

    func isDuplicate(_ image: CGImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }

                if let error = error {
                    print("VisionDuplicateDetector error: \(error)")
                    continuation.resume(returning: false)
                    return
                }

                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(returning: false)
                    return
                }

                // If we don't have a previous image, this is not a duplicate.
                // 以前の画像がない場合、これは重複ではありません。
                // We just store the current one.
                // 現在のものを保存するだけです。
                guard let lastObservation = self.lastObservation else {
                    self.lastObservation = observation
                    continuation.resume(returning: false)
                    return
                }

                do {
                    var distance: Float = 0
                    try observation.computeDistance(&distance, to: lastObservation)

                    // Update the last observation to the current one for the next comparison
                    // 次の比較のために、最後の観測を現在のものに更新します
                    // (This is a design choice: do we compare against the *first* of a sequence or the *previous*?
                    // （これは設計上の選択です：シーケンスの*最初*のものと比較するか、*直前*のものと比較するか？
                    // Usually "previous" to detect when the screen stops changing.)
                    // 通常、画面の変化が止まったことを検出するには「直前」と比較します。）
                    self.lastObservation = observation

                    // Check if distance is within the threshold
                    // 距離がしきい値内にあるかどうかを確認します
                    // distance is a Float, threshold is Double
                    // distance は Float、threshold は Double です
                    let isDup = Double(distance) <= self.threshold
                    if isDup {
                        print("Duplicate detected. Distance: \(distance), Threshold: \(self.threshold)")
                    } else {
                        // print("Not a duplicate. Distance: \(distance)")
                    }

                    continuation.resume(returning: isDup)
                } catch {
                    print("VisionDuplicateDetector distance computation error: \(error)")
                    continuation.resume(returning: false)
                }
            }

            // Prefer .fast or .balanced. .accurate might be too slow for real-time loop?
            // .fast または .balanced を推奨。.accurate はリアルタイムループには遅すぎる可能性があります？
            // But we are taking screenshots with 1s interval, so .accurate is probably fine and better for "ignoring clocks".
            // しかし、1秒間隔でスクリーンショットを撮っているので、.accurate でもおそらく問題なく、「時計を無視する」には適しています。
            // Actually, revision1 is the default. Let's stick to defaults or explicit revision.
            // 実際には、revision1 がデフォルトです。デフォルトまたは明示的なリビジョンに固執しましょう。
            request.revision = VNGenerateImageFeaturePrintRequestRevision1

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("VisionDuplicateDetector handler error: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
}
