import SwiftUI
// macOSのAppKitフレームワークをインポートします（NSWorkspaceを使用するため）
import AppKit
// macOSのアクセシビリティAPIを使用するためにインポートします
import ApplicationServices

/// 自動スクリーンショット設定を表示するビューです
/// AppStore審査への影響を考慮し、機能を切り出しやすくするために別ファイルとしています
struct AutoScreenshotSettingsView: View {
    // 環境オブジェクトからImageStoreを取得します
    @EnvironmentObject var store: ImageStore
    // ImageStore内のAutoScreenshotManagerを監視します
    @ObservedObject var manager: AutoScreenshotManager

    init(manager: AutoScreenshotManager) {
        self.manager = manager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1列目：アクセシビリティの承認ボタン
            HStack {
                // システムのアクセシビリティ設定画面を開くためのボタンです
                Button("Accessibility approval") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    AXIsProcessTrustedWithOptions(options as CFDictionary)
                    
                    // アクセシビリティ設定のURLを定義します
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    // デフォルトのブラウザやアプリでURL（システム設定）を開きます
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            }
            Text("Key input")
                .font(.caption)
            // 2列目：キー入力方向セレクター
            HStack {
//                Text("Key input")
//                    .font(.caption)
                Picker("", selection: $manager.autoCaptureDirection) {
                    Text("left").tag("left")
                    Text("up").tag("up")
                    Text("down").tag("down")
                    Text("right").tag("right")
                }
                .pickerStyle(.segmented)
                .disabled(manager.isAutoCapturing)
            }

            // 3列目：撮影間隔
            HStack {
                Text("Shooting interval")
                    .font(.caption)
                Spacer()
                Stepper(value: $manager.autoCaptureInterval, in: 0.1...10.0, step: 0.1) {
                    Text("\(String(format: "%.1f", manager.autoCaptureInterval))秒")
                        .monospacedDigit()
                }
                .disabled(manager.isAutoCapturing)
            }

            // 4列目：停止条件
            VStack(alignment: .leading, spacing: 4) {
                Text("Stopping conditions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: $manager.autoCaptureThreshold, in: 0.0...1.0)
                        .disabled(manager.isAutoCapturing)
                    Text("\(Int(manager.autoCaptureThreshold * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            // 5列目：キャプチャ開始ボタン
            Button(action: {
                if manager.isAutoCapturing {
                    manager.stopAutoCapture()
                } else {
                    manager.startAutoCapture()
                }
            }) {
                Text(manager.isAutoCapturing ? "Stop capturing" : "Start capturing")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isAutoCapturing ? .red : .blue)
            .disabled(store.screenshotFolderURL == nil)
        }
        .padding(12)
        .background(Color.blue.opacity(0.05)) // 背景色を設定
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    let store = ImageStore()
    AutoScreenshotSettingsView(manager: store.autoManager)
        .environmentObject(store)
        .frame(width: 250)
        .padding()
}
