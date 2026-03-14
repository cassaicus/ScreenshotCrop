import ApplicationServices
import CoreGraphics
// SwiftUIフレームワークをインポートします
import SwiftUI

// 右側に表示されるツール操作パネルのビューです
struct ToolPaneView: View {
    // 環境オブジェクトからImageStoreを取得します
    @EnvironmentObject var store: ImageStore
    // 保存先のフォルダ名を管理する状態変数です
    @State private var folderName: String = "Cropped"
    // 保存するファイル名を管理する状態変数です
    @State private var fileName: String = "page"
    // 結合用ウィンドウの表示状態を管理します
    @State private var isShowingCombineSheet: Bool = false

    // 現在の切り抜き枠の実際のピクセルサイズを計算するヘルパー関数です
    private func pixelSize(for rect: CGRect) -> (width: Int, height: Int) {
        // 表示サイズに対する実際のピクセルサイズの倍率を計算します
        let scaleX =
            store.displayedImageSize.width > 0
            ? store.currentImagePixelSize.width / store.displayedImageSize.width
            : 1.0
        let scaleY =
            store.displayedImageSize.height > 0
            ? store.currentImagePixelSize.height
                / store.displayedImageSize.height : 1.0

        // 四捨五入して整数ピクセル値を返します
        return (
            width: Int(round(rect.width * scaleX)),
            height: Int(round(rect.height * scaleY))
        )
    }

    // ビューの階層構造を定義します
    var body: some View {
        ScrollView {
            // 左揃えで要素を配置する垂直スタックです（スペース8）
            VStack(alignment: .leading, spacing: 8) {
                // モード切替
                Picker(
                    "",
                    selection: Binding(
                        get: { store.isScreenshotMode },
                        set: { store.updateScreenshotMode($0) }
                    )
                ) {
                    Text("Crop Mode").tag(false)
                    Text("Screenshot Mode").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
                if store.isScreenshotMode {
                    screenshotSection
                } else {
                    cropSection
                }
            }
        }
        .padding()
        .sheet(isPresented: $isShowingCombineSheet) {
            CombineImagesView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingScreenshotCleanupSheet) {
            ScreenshotCleanupView()
                .environmentObject(store)
        }
    }

    // スクリーンショット機能のセクション
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Screenshot Folder")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if let url = store.screenshotFolderURL {
                        Text(url.lastPathComponent)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    } else {
                        Text("None")
                    }
                    Spacer()
                    Button("Select Folder") {
                        store.pickScreenshotFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // 画面収録権限がない場合に警告を表示します
            if !store.isScreenCaptureEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Screen capture requires permission.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                    
                    Button("Settings ScreenCapture") {
//                        // 画面収録権限をリクエストします
//                        CGRequestScreenCaptureAccess()
                        
                        if !CGRequestScreenCaptureAccess() {
                            // すでに権限が拒否されている、または設定が必要な場合はシステム設定を開きます
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    

                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            }

            VStack(spacing: 12) {
                // フローティングパネルの表示・非表示を切り替えるボタンです
                Button(action: {
                    store.toggleFloatingPanel()
                }) {
                    HStack {
                        Image(
                            systemName: store.isShowingFloatingPanel
                                ? "minus.square" : "plus.square"
                        )
                        Text(
                            store.isShowingFloatingPanel
                                ? "Hide Floating Panel" : "Show Floating Panel"
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.screenshotFolderURL == nil)

                // 自動スクリーンショット設定グループ
                AutoScreenshotSettingsView(manager: store.autoManager)

            }

            // アイテムが存在する場合に削除ボタンを表示します
            if !store.items.isEmpty {
                Button(action: {
                    // 削除用シートを表示します
                    store.isShowingScreenshotCleanupSheet = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete unnecessary screenshots")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Spacer()
        }
    }


    // 切り抜き機能のセクション
    private var cropSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // タイトルを表示します
            Text("1. Load Files")
                // 見出し用のフォントを設定します
                .font(.headline)

            // フォルダを選択してファイルを読み込むボタンです
            Button(action: {
                store.pickFolder()
            }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Load Files")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isProcessing || store.isAnalyzingBackground)

            // フォルダ内の画像サイズが不一致の場合に警告を表示します
            if store.hasSizeMismatch {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(
                        "The folder contains images of different sizes. The crop position may be shifted."
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            }

            // セクションを分ける仕切り線です
            Divider()
            Text("2. Configure Crop Area")
                // 見出し用のフォントを設定します
                .font(.headline)

            // 切り抜き設定を実行するボタンです

            Button(action: {
                // AIによる検出を実行します
                store.applyAIDetection()
                // デバッグ用のログを出力します
                print("Log: Configure Crop Area executed")
            }) {
                // ボタンのテキストを表示します
                Text(
                    store.isHeatmapMode
                        ? "Finish image overlay mode" : "Configure Crop Area"
                )
                // 横幅を最大限に広げます
                .frame(maxWidth: .infinity)
            }
            // 目立つスタイルのボタンを設定します
            .buttonStyle(.borderedProminent)
            .disabled(store.isProcessing || store.isAnalyzingBackground)

            // 背景分析の調整スライダーを表示します（ヒートマップモード時のみ）
            if store.isHeatmapMode {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Background Whiteness:")
                        Spacer()
                        Text("\(Int(store.backgroundWhiteness))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack {
                        Text("Black")
                            .font(.caption)
                        Slider(value: $store.backgroundWhiteness, in: 0...255, step: 1)
                            .disabled(store.isProcessing || store.isAnalyzingBackground)
                            .onChange(of: store.backgroundWhiteness) {old, _ in
                                store.scheduleBackgroundAnalysis()
                            }
                        Text("White")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            // 見開きモードと日本式のチェックボックスを水平に並べます
            HStack {
                // 見開きモードのオンオフを切り替えるトグル（チェックボックス風）です
                Toggle(
                    "Spread Mode",
                    isOn: Binding(
                        get: { store.isSpreadMode },
                        set: { store.updateSpreadMode($0) }
                    )
                )
                .toggleStyle(.checkbox)

                // 見開きモードの時のみ、日本式（右開き）のトグルを表示します
                if store.isSpreadMode {
                    Toggle(
                        "Japanese Style (Right-to-Left)",
                        isOn: Binding(
                            get: { store.isJapaneseStyle },
                            set: { store.updateJapaneseStyle($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }

            // 「自動エリア指定」ボタン
            Button(action: {
                store.applyAutomaticAreaSpecified()
                print("Log: Automatic Area Specified executed")
            }) {
                if store.isAnalyzingBackground {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Automatic Area Specified")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!store.isHeatmapMode || store.detectedBoundaries.isEmpty || store.isAnalyzingBackground || store.isProcessing)

            // 現在の切り抜き枠のサイズを表示します
            VStack(alignment: .leading, spacing: 4) {
                // 見開きモードの場合、ラベルを付けて2つのサイズを表示します
                if store.isSpreadMode {
                    // 日本式（右開き）の場合は、枠2（ページ1）を先に、枠1（ページ2）を後に表示して整合性を取ります
                    if store.isJapaneseStyle {
                        let size1 = pixelSize(for: store.cropRect2)
                        let size2 = pixelSize(for: store.cropRect)
                        Text("Page 1:")
                        HStack(spacing: 8) {
                            Text("[H: \(size1.height)px]")
                            Text("[W: \(size1.width)px]")
                        }

                        Text("Page 2:")
                        HStack(spacing: 8) {
                            Text("[H: \(size2.height)px]")
                            Text("[W: \(size2.width)px]")
                        }
                        // サイズ同期ボタン
                        Button(action: { store.syncCropSizes() }) {
                            Label(
                                "Sync frame sizes",
                                systemImage: "arrow.right.arrow.left"
                            )
                            .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .padding(.bottom, 4)
                    } else {
                        // 通常モード（左開き）の場合は、枠1（ページ1）が先、枠2（ページ2）が後です
                        let size1 = pixelSize(for: store.cropRect)
                        let size2 = pixelSize(for: store.cropRect2)

                        Text("Page 1:")
                        HStack(spacing: 8) {
                            Text("[H: \(size1.height)px]")
                            Text("[W: \(size1.width)px]")
                        }

                        Text("Page 2:")
                        HStack(spacing: 8) {
                            Text("[H: \(size2.height)px]")
                            Text("[W: \(size2.width)px]")
                        }
                        // サイズ同期ボタン
                        Button(action: { store.syncCropSizes() }) {
                            Label(
                                "Sync frame sizes",
                                systemImage: "arrow.right.arrow.left"
                            )
                            .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .padding(.bottom, 4)
                    }
                } else {
                    // 通常モードは単一のサイズのみ表示します
                    let size = pixelSize(for: store.cropRect)
                    HStack(spacing: 8) {
                        // 高さをピクセル単位で表示します
                        Text("[H: \(size.height)px]")
                        // 横幅をピクセル単位で表示します
                        Text("[W: \(size.width)px]")
                    }
                }
            }
            // フォントを等幅（モノスペース）に設定して、数値が変わっても位置がズレにくくします
            .font(.system(.body, design: .monospaced))
            // テキストの色を二次的な色にします
            .foregroundColor(.secondary)
            // 水平方向に中央揃えにします
            .frame(maxWidth: .infinity)

            // セクションを分ける仕切り線です
            Divider()
            Text("3. Export Settings")
                // 見出し用のフォントを設定します
                .font(.headline)
            // フォルダ名入力セクションです
            VStack(alignment: .leading, spacing: 4) {
                // ラベルを表示します
                Text("Output folder name")
                    // キャプション用のフォントを設定します
                    .font(.caption)
                    // テキストの色を二次的な色にします
                    .foregroundColor(.secondary)
                // フォルダ名を入力するテキストフィールドです
                TextField("Folder name", text: $folderName)
                    // 角丸のボーダースタイルを設定します
                    .textFieldStyle(.roundedBorder)
            }

            // ファイル名入力セクションです
            VStack(alignment: .leading, spacing: 4) {
                // ラベルを表示します
                Text("File name (appends _001, _002...)")
                    // キャプション用のフォントを設定します
                    .font(.caption)
                    // テキストの色を二次的な色にします
                    .foregroundColor(.secondary)
                // ファイル名を入力するテキストフィールドです
                TextField("Base file name", text: $fileName)
                    // 角丸のボーダースタイルを設定します
                    .textFieldStyle(.roundedBorder)
            }

            //            Divider()

            // 保存形式セクション
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Format")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Toggle(
                        "PNG",
                        isOn: Binding(
                            get: { store.exportFormat == .png },
                            set: { if $0 { store.exportFormat = .png } }
                        )
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "JPEG",
                        isOn: Binding(
                            get: { store.exportFormat == .jpg },
                            set: { if $0 { store.exportFormat = .jpg } }
                        )
                    )
                    .toggleStyle(.checkbox)
                }

                if store.exportFormat == .jpg {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("JPEG Quality:")
                            Spacer()
                            Text("\(Int(store.jpgQuality * 100))%")
                                .monospacedDigit()
                        }
                        .font(.caption)

                        Slider(value: $store.jpgQuality, in: 0.1...1.0)
                    }
                    .padding(.top, 4)
                }
            }

            // 下部に余白を作ります
            //            Spacer()

            Divider()
            Text("4. Execute Cropping")
                // 見出し用のフォントを設定します
                .font(.headline)

            // 現在表示されている画像だけを切り抜くボタンです
            Button(action: {
                // ImageStoreの単一画像保存処理を呼び出します
                store.executeCropSelected(
                    folderName: folderName,
                    fileNameBase: fileName
                )
            }) {
                // 処理中の場合は読み込み中インジケータを表示します
                if store.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    // ボタンのテキストを表示します
                    Text("Crop Current Image")
                        // 横幅を最大限に広げます
                        .frame(maxWidth: .infinity)
                }
            }
            // 処理中はボタンを無効化し、画像が選択されていない場合も無効化します
            .disabled(
                store.isProcessing || store.isAnalyzingBackground || store.selectedID == nil
                    || store.isHeatmapMode || !store.isShowingCropBox
            )
            // 標準的なボーダースタイルのボタンを設定します
            .buttonStyle(.bordered)

            // フォルダ内の全ての画像を切りぬく実行ボタンです
            Button(action: {
                // ImageStoreの一括保存処理を呼び出します
                store.executeCropAll(
                    folderName: folderName,
                    fileNameBase: fileName
                )
            }) {
                // 処理中の場合は読み込み中インジケータを表示します
                if store.isProcessing {
                    VStack(spacing: 4) {
                        ProgressView(
                            value: Double(store.processedCount),
                            total: Double(store.totalCount)
                        )
                        .progressViewStyle(.linear)
                        Text("\(store.processedCount) / \(store.totalCount)")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // ボタンのテキストを表示します
                    Text("Process All Images")
                        // 横幅を最大限に広げます
                        .frame(maxWidth: .infinity)
                        // 上下にパディングを付加します
                        .padding(.vertical, 8)
                }
            }
            // 処理中はボタンを無効化します
            .disabled(
                store.isProcessing || store.isAnalyzingBackground || !store.isHeatmapMode
                    || !store.isShowingCropBox
            )
            // 目立つスタイルのボタンを設定します
            .buttonStyle(.borderedProminent)
            // ボタンの色を緑色に設定します
            .tint(.green)

            if !store.isProcessing && store.canCombine {
                Text("5. Check and combine images")
                // 画像を結合するボタン
                Button(action: {
                    isShowingCombineSheet = true
                }) {
                    Text("Combine Images")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
    }
}
