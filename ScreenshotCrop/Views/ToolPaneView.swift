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
    // 現在のステップを管理する状態変数です
    @State private var currentStep: Int = 1
    
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
                .onChange(of: store.isScreenshotMode) { old, isScreenshot in
                    if !isScreenshot && !store.items.isEmpty {
                        withAnimation { currentStep = 2 }
                    }
                }
                .onChange(of: store.items.count) { old, newCount in
                    if newCount > 0 && currentStep == 1 {
                        withAnimation { currentStep = 2 }
                    } else if newCount == 0 {
                        withAnimation { currentStep = 1 }
                    }
                }
        }
        .onChange(of: store.isScreenshotMode) { old, isScreenshot in
            if !isScreenshot && !store.items.isEmpty {
                withAnimation { currentStep = 2 }
            }
        }
        .onChange(of: store.items.count) { old, newCount in
            if newCount > 0 && currentStep == 1 {
                withAnimation { currentStep = 2 }
            } else if newCount == 0 {
                withAnimation { currentStep = 1 }
            }
        }
    }
    
    // ステップごとのヘッダーを表示するヘルパー関数です
    private func stepHeader(title: LocalizedStringKey, step: Int) -> some View {
        Button(action: {
            withAnimation { currentStep = step }
        }) {
            HStack {
                HStack(spacing: 0) {
                    Text("\(step). ")
                    Text(title)
                }
                .font(.headline)
                .foregroundColor(currentStep == step ? .primary : .secondary)
                Spacer()
                if currentStep > step {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if currentStep == step {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        // 画面収録権限をリクエストします
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
                .tint(store.screenshotFolderURL == nil ? .secondary : .blue)
                .opacity(store.screenshotFolderURL == nil ? 0.3 : 1.0)
                .disabled(store.screenshotFolderURL == nil)
                
                // 自動スクリーンショット設定グループ
////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////
//                AutoScreenshotSettingsView(manager: store.autoManager)
////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////
                
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
            stepHeader(title: "Load Files", step: 1)
            if currentStep == 1 {
                
                Button(action: {
                    store.pickFolder()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Load Files")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint((store.isProcessing || store.isAnalyzingBackground) ? .secondary : .blue)
                .opacity((store.isProcessing || store.isAnalyzingBackground) ? 0.3 : 1.0)
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
                
                
                if !store.items.isEmpty {
                    HStack {
                        Spacer()
                        Button("Next") {
                            withAnimation { currentStep = 2 }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            Divider()
            stepHeader(title: "Configure Crop Area", step: 2)
            if currentStep == 2 {
                VStack(alignment: .leading, spacing: 16) {
                    // 見開きモードの問合せ
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Is this a spread (2-page) document?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: Binding(
                            get: { store.isSpreadMode },
                            set: { store.updateSpreadMode($0) }
                        )) {
                            Text("1 Page").tag(false)
                            Text("2 Pages").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    // 日本式（右開き）の問合せ（見開きモード時のみ）
                    if store.isSpreadMode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Is it Japanese Style (Right-to-Left)?")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: Binding(
                                get: { store.isJapaneseStyle },
                                set: { store.updateJapaneseStyle($0) }
                            )) {
                                Text("L to R").tag(false)
                                Text("R to L").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // メインアクションボタン
                    Button(action: {
                        store.applyAIDetection()
                    }) {
                        HStack {
                            if store.isHeatmapMode {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(store.isHeatmapMode ? "Finish image overlay mode" : "Configure Crop Area")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isProcessing || store.isAnalyzingBackground)



                    // 背景分析調整（ヒートマップモード時のみ）
                    if store.isHeatmapMode {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Background Whiteness:")
                                Spacer()
                                Text("\(Int(store.backgroundWhiteness))")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            HStack {
                                Text("Black").font(.caption)
                                Slider(value: $store.backgroundWhiteness, in: 0...255, step: 1)
                                    .disabled(store.isProcessing || store.isAnalyzingBackground)
                                    .onChange(of: store.backgroundWhiteness) { _, _ in
                                        store.scheduleBackgroundAnalysis()
                                    }
                                Text("White").font(.caption)
                            }
                            
                            Button(action: {
                                store.applyAutomaticAreaSpecified()
                            }) {
                                if store.isAnalyzingBackground {
                                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                                } else {
                                    Text("Automatic Area Specified").frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!store.isHeatmapMode || store.detectedBoundaries.isEmpty || store.isAnalyzingBackground || store.isProcessing)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
 
                    // 実行ショートカット (Step 2 から直接実行)
                    if store.isHeatmapMode && store.isShowingCropBox {
                        VStack(spacing: 8) {
                            Text("Skip steps 3 & 4 and go to Step 5")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button(action: {
                                store.executeCropAll(folderName: folderName, fileNameBase: fileName)
                                withAnimation { currentStep = 5 }
                            }) {
                                if store.isAnalyzingBackground {
                                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                                } else {
                                    Text("Process All Images")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(store.isProcessing)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
  
                    // サイズ表示
                    VStack(alignment: .leading, spacing: 4) {
                        if store.isSpreadMode {
                            let size1 = store.isJapaneseStyle ? pixelSize(for: store.cropRect2) : pixelSize(for: store.cropRect)
                            let size2 = store.isJapaneseStyle ? pixelSize(for: store.cropRect) : pixelSize(for: store.cropRect2)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Page 1:").font(.caption2)
                                    Text("\(size1.width) x \(size1.height) px")
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Page 2:").font(.caption2)
                                    Text("\(size2.width) x \(size2.height) px")
                                }
                            }
                            
                            Button(action: { store.syncCropSizes() }) {
                                Label("Sync frame sizes", systemImage: "arrow.right.arrow.left")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            let size = pixelSize(for: store.cropRect)
                            Text("Size: \(size.width) x \(size.height) px")
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)

                    // Step 3 への案内
                    HStack {
                        Spacer()
                        Button("Next") {
                            withAnimation { currentStep = 3 }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
            stepHeader(title: "Export Settings", step: 3)
            if currentStep == 3 {
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
                HStack {
                    Spacer()
                    Button("Next") {
                        withAnimation { currentStep = 4 }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Divider()
            stepHeader(title: "Execute Cropping", step: 4)
            if currentStep == 4 {
                
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
                // 非アクティブ時は透過させて、より押せないことを強調します
                .opacity(
                    (store.isProcessing || store.isAnalyzingBackground || store.selectedID == nil
                     || store.isHeatmapMode || !store.isShowingCropBox) ? 0.3 : 1.0
                )
                // 目立つスタイルのボタンを設定し、青色にします。非アクティブ時はグレーにします
                .buttonStyle(.borderedProminent)
                .tint((store.isProcessing || store.isAnalyzingBackground || store.selectedID == nil
                       || store.isHeatmapMode || !store.isShowingCropBox) ? .secondary : .blue)
                
                // フォルダ内の全ての画像を切りぬく実行ボタンです
                VStack {
                    let isProcessAllDisabled = store.isProcessing || store.isAnalyzingBackground || !store.isHeatmapMode || !store.isShowingCropBox
                    
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
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            // ボタンのテキストを表示します。無効時はグレーにします。
                            Text("Process All Images")
                                .foregroundColor(isProcessAllDisabled ? .secondary : .white)
                            // 横幅を最大限に広げます
                                .frame(maxWidth: .infinity)
                            // 上下にパディングを付加します
                                .padding(.vertical, 8)
                        }
                    }
                    // 処理中はボタンを無効化します
                    .disabled(isProcessAllDisabled)
                    // 目立つスタイルのボタンを設定します
                    .buttonStyle(.borderedProminent)
                    // ボタンの色を緑色に設定します
                    .tint(.green)
                    // 非アクティブ時は透過させて、より押せないことを強調します
                    .opacity(isProcessAllDisabled ? 0.3 : 1.0)
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                
                
                if store.canCombine {
                    HStack {
                        Spacer()
                        Button("Next") {
                            withAnimation { currentStep = 5 }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            Divider()
            stepHeader(title: "Check and combine images", step: 5)
            if currentStep == 5 {
                VStack(spacing: 12) {
                    // 画像切り出し中の進捗表示
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
                        .padding(.bottom, 8)
                    }

                    // 画像を結合するボタン
                    Button(action: {
                        isShowingCombineSheet = true
                    }) {
                        HStack {
                            Image(systemName: "plus.square.fill.on.square.fill")
                            Text("Combine Images")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint((!store.canCombine || store.isProcessing) ? .secondary : .blue)
                    .disabled(!store.canCombine || store.isProcessing)
                    // 非アクティブ時は透過させて、より押せないことを強調します
                    .opacity((!store.canCombine || store.isProcessing) ? 0.3 : 1.0)

                    // Finderで開くボタン
                    if let url = store.lastOutputFolderURL {
                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("Show in Finder")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}


