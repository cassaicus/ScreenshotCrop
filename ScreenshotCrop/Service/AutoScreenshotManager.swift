import SwiftUI
import AppKit
import CoreGraphics
import Vision
import Combine

// 自動スクリーンショットのロジックを管理するクラスです。
// AppStoreのガイドラインに配慮し、このクラスに自動キャプチャ関連の機能を隔離しています。
@MainActor
final class AutoScreenshotManager: ObservableObject {
    // 自動キャプチャ実行中かどうかのフラグです。
    @Published var isAutoCapturing: Bool = false
    // 自動キャプチャの間隔（秒）です。
    @Published var autoCaptureInterval: Double = 1.0
    // 自動キャプチャのキー入力方向です。
    @Published var autoCaptureDirection: String = "down"
    // 自動キャプチャの停止条件（しきい値）です。
    @Published var autoCaptureThreshold: Double = 0.5

    // 重複検知のためのデテクターです。
    private let duplicateDetector: DuplicateDetecting = VisionDuplicateDetector()

    // ImageStoreへの弱参照を保持します。
    private weak var store: ImageStore?

    // 初期化時にImageStoreを受け取ります。
    init(store: ImageStore) {
        self.store = store
    }

    // 自動キャプチャを開始します。
    func startAutoCapture() {
        guard !isAutoCapturing else { return }
        isAutoCapturing = true

        // 重複検知器をリセットします。
        duplicateDetector.reset()
        // しきい値を設定します。
        duplicateDetector.setThreshold(autoCaptureThreshold)

        // メインアクター上で実行されるタスクを作成します。
        Task {
            // 最初に5秒間待機し、その間1秒ごとにビープ音を鳴らします。
            for _ in 0..<5 {
                if !self.isAutoCapturing { return }
                NSSound.beep()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            // 開始時の連番を取得します。
            var currentNumber = self.getNextScreenshotNumber()

            // 最大999回まで繰り返します。
            for _ in 0..<999 {
                // 停止ボタンが押されていたら終了します。
                if !self.isAutoCapturing { break }

                do {
                    // スクリーンショットを撮影します。
                    let image = try await ScreenshotService.shared.captureMainDisplay()

                    // 重複チェックを実行します。
                    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        if await duplicateDetector.isDuplicate(cgImage) {
                            print("Log: 重複が検知されたため自動停止します。")
                            // 停止時にビープ音を鳴らします。
                            NSSound.beep()
                            break
                        }
                    }

                    // 保存処理を実行します。
                    self.saveAutoCapturedImage(image, number: currentNumber)
                    currentNumber += 1
                } catch {
                    print("Log: 自動キャプチャ中にエラーが発生しました: \(error)")
                    break
                }

                if !self.isAutoCapturing { break }

                // 指定されたキー入力をシミュレートします。
                let direction = self.autoCaptureDirection
                simulateKeyPress(direction: direction)

                // 設定された撮影間隔だけ待機します。
                let interval = self.autoCaptureInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }

            // 終了後に状態をリセットします。
            self.isAutoCapturing = false
        }
    }

    // 自動キャプチャを停止します。
    func stopAutoCapture() {
        isAutoCapturing = false
    }

    // 次の連番を取得します。
    private func getNextScreenshotNumber() -> Int {
        guard let folderURL = store?.screenshotFolderURL else { return 1 }
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []

        var maxNumber = 0
        // screenshot_###.png にマッチする正規表現
        let pattern = "^screenshot_(\\d+)\\.png$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        for url in urls {
            let fileName = url.lastPathComponent
            if let match = regex?.firstMatch(in: fileName, options: [], range: NSRange(location: 0, length: fileName.utf16.count)) {
                if let range = Range(match.range(at: 1), in: fileName),
                   let number = Int(fileName[range]) {
                    maxNumber = max(maxNumber, number)
                }
            }
        }
        return maxNumber + 1
    }

    // 自動撮影した画像を連番で保存し、リストに追加します。
    private func saveAutoCapturedImage(_ image: NSImage, number: Int) {
        guard let folderURL = store?.screenshotFolderURL else { return }

        let fileName = String(format: "screenshot_%03d.png", number)
        let fileURL = folderURL.appendingPathComponent(fileName)

        // 画像を保存します。
        store?.saveImageExternal(image, to: fileURL, format: .png, quality: 1.0)

        // 撮影音を鳴らします。
        NSSound(named: "Hero")?.play()

        store?.capturedCount += 1

        // リストを更新（新しい画像を読み込む）。
        // パフォーマンスのため、本来は差分更新が望ましいが、一旦既存の仕組みを利用。
        store?.loadImagesExternal(from: folderURL)
    }

    // キー入力をシミュレートします。
    private func simulateKeyPress(direction: String) {
        let keyCode: CGKeyCode
        switch direction {
        case "up": keyCode = 126
        case "down": keyCode = 125
        case "left": keyCode = 123
        case "right": keyCode = 124
        default: return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        // HIDイベントとしてポストします。アクセシビリティ権限が必要です。
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
