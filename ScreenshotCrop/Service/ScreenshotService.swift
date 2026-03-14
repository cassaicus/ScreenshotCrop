import Foundation
import ScreenCaptureKit
import AppKit

class ScreenshotService {
    static let shared = ScreenshotService()

    func captureMainDisplay() async throws -> NSImage {
        // 利用可能なコンテンツ（画面、ウィンドウ）を取得します
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // メインディスプレイを選択します
        guard let mainDisplay = content.displays.first else {
            throw NSError(domain: "ScreenshotService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Main display not found"])
        }

        // フィルタを作成します（ディスプレイ全体を対象）
        let filter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])

        // 設定を構成します
        let config = SCStreamConfiguration()
        config.showsCursor = false
        // キャプチャの品質を最高に設定
        config.width = Int(mainDisplay.width)
        config.height = Int(mainDisplay.height)

        // スクリーンショットを実行します
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
