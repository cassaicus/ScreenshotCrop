// SwiftUIフレームワークをインポートします
import SwiftUI
// macOSのAppKitフレームワークをインポートします
import AppKit
// CoreGraphicsフレームワークをインポートします
import CoreGraphics
// 非同期処理やリアクティブプログラミングを扱うCombineフレームワークをインポートします
import Combine
// 画像のメタデータを効率的に読み込むためのImageIOをインポートします
import ImageIO

// メインスレッドで動作することを保証する、画像データを管理するためのストアクラスです
@MainActor
final class ImageStore: ObservableObject {
    // 保存形式の定義
    enum ExportFormat: String {
        case png = "PNG"
        case jpg = "JPEG"
        
        var extensionName: String {
            return self.rawValue.lowercased()
        }
    }


    // 読み込まれた画像アイテムのリストです。変更時にビューに通知されます
    @Published var items: [ImageItem] = []
    // 現在選択されている画像のIDです。変更時にビューに通知されます
    @Published var selectedID: UUID?
    // 切り抜き枠を表示するかどうかのフラグです。変更時にビューに通知されます
    @Published var isShowingCropBox: Bool = false
    // 見開きモードかどうかのフラグです。変更時にビューに通知されます
    @Published var isSpreadMode: Bool = false
    // 日本式（右から左へページが並ぶ）かどうかのフラグです
    @Published var isJapaneseStyle: Bool = false
    // ヒートマップ表示中かどうかのフラグです
    @Published var isHeatmapMode: Bool = false
    // 生成されたドラフト・ヒートマップ画像です
    @Published var heatmapImage: NSImage? = nil
    // 背景分析の結果（2Dマスク: true = 背景, false = 内容）
    @Published var backgroundAnalysis: [Bool]? = nil
    // 分析結果を可視化するためのマスク画像です
    @Published var backgroundMaskImage: NSImage? = nil
    // 検出されたページ境界のx座標（ピクセル単位）
    @Published var detectedBoundaries: [Int] = []

    // 背景分析の閾値（明るさ: 0-255）
    @Published var backgroundWhiteness: Double = 235
    // 背景分析の許容誤差（色の安定度: 0-255）
    @Published var backgroundTolerance: Double = 10

    // 1つ目の切り抜き枠の矩形範囲です
    @Published var cropRect: CGRect = CGRect(x: 50, y: 100, width: 200, height: 300)
    // 2つ目の切り抜き枠の矩形範囲です（見開きモード用）
    @Published var cropRect2: CGRect = CGRect(x: 300, y: 100, width: 200, height: 300)

    // 現在ビューに表示されている画像の表示サイズ（ポイント単位）を保持します
    @Published var displayedImageSize: CGSize = .zero
    // 現在選択されている画像の実際のピクセルサイズを保持します
    @Published var currentImagePixelSize: CGSize = .zero

    // 保存処理の進捗を管理するための状態です
    @Published var isProcessing: Bool = false
    // 背景分析の進捗を管理するための状態です
    @Published var isAnalyzingBackground: Bool = false
    // 処理済みの枚数
    @Published var processedCount: Int = 0
    // 全体の枚数
    @Published var totalCount: Int = 0
    
    // 保存形式
    @Published var exportFormat: ExportFormat = .png
    // JPGの保存品質 (0.0 - 1.0)
    @Published var jpgQuality: Double = 0.8
    
    // フォルダ内にサイズの異なる画像が含まれているかどうかのフラグです
    @Published var hasSizeMismatch: Bool = false

    // 最後に一括書き出しを行ったフォルダのURLです
    @Published var lastOutputFolderURL: URL? = nil
    // 結合機能が利用可能かどうかのフラグです
    @Published var canCombine: Bool = false
    // 結合後に元画像を削除するかどうかのフラグです
    @Published var shouldDeleteOriginalsAfterCombine: Bool = false
    // 直前の書き出しが見開きモードだったかどうかのフラグです
    @Published var wasLastExportSpreadMode: Bool = false

    // --- スクリーンショット機能用 ---
    // スクリーンショットモード中かどうかのフラグです
    @Published var isScreenshotMode: Bool = false
    // スクリーンショットの保存先フォルダURLです
    @Published var screenshotFolderURL: URL? = nil
    // 今回のセッションで撮影された枚数です
    @Published var capturedCount: Int = 0
    // スクリーンショット削除用ウィンドウの表示状態を管理します
    @Published var isShowingScreenshotCleanupSheet: Bool = false

    // --- 自動スクリーンショット用 ---
    // 自動キャプチャを管理するオブジェクトです
////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////
    @Published var autoManager: AutoScreenshotManager!
////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////

    
    
    
    // 画面収録権限があるかどうかのフラグです
    @Published var isScreenCaptureEnabled: Bool = false
    // フローティングパネルが表示されているかどうかのフラグです
    @Published var isShowingFloatingPanel: Bool = false
    
    // 背景分析のデバウンス（遅延）実行用
    private let backgroundTrigger = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    // フローティングパネルのインスタンス
    private var floatingPanel: FloatingPanel?

    // ストアを初期化します
    init() {
        setupDebounce()
        
        
        
        // 自動キャプチャマネージャーを初期化します
////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////
        self.autoManager = AutoScreenshotManager(store: self)
////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////        ////////////////////////////////////////////////////////////

        
        
        
        
    }

    // デバウンス処理（0.5秒の遅延）を設定します
    private func setupDebounce() {
        backgroundTrigger
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.applyAutomaticAreaSetting()
            }
            .store(in: &cancellables)
    }
    
    // 背景分析の更新をスケジュールします
    func scheduleBackgroundAnalysis() {
        backgroundTrigger.send()
    }

    // スクリーンショットモードを更新し、関連する状態をリセットします
    func updateScreenshotMode(_ isScreenshot: Bool) {
        Task { @MainActor in
            isScreenshotMode = isScreenshot
            if isScreenshot {
                isHeatmapMode = false
                isShowingCropBox = false
                // 画面収録権限をチェックします
                checkScreenCapturePermission()
            } else {
                // スクリーンショットモードを抜ける際にフローティングパネルを閉じます
                hideFloatingPanel()
            }
        }
    }

    // 見開きモードを更新し、関連する枠の配置を初期化します
    func updateSpreadMode(_ isEnabled: Bool) {
        Task { @MainActor in
            isSpreadMode = isEnabled
            if isEnabled {
                setupInitialSpreadRects()
                isShowingCropBox = true

                // 見開きモードがONになった際、境界線が既に存在すれば自動吸着を実行します
                if !detectedBoundaries.isEmpty {
                    applyAutomaticAreaSpecified()
                }
            } else {
                setupInitialSingleRect()
            }
        }
    }

    // 日本式（右開き）設定を更新します
    func updateJapaneseStyle(_ isEnabled: Bool) {
        Task { @MainActor in
            isJapaneseStyle = isEnabled
            // 日本式がONになった際、境界線が既に存在すれば自動吸着を実行します
            // (OFFにした際は何もしないというユーザー要望に合わせ、isEnabledがtrueの場合のみ実行)
            if isEnabled && !detectedBoundaries.isEmpty {
                applyAutomaticAreaSpecified()
            }
        }
    }

    // 結合処理に使用するペアの構造体です
    struct ImagePair: Identifiable {
        // 一意識別子です
        let id = UUID()
        // 1枚目の画像です
        let first: ImageItem
        // 2枚目の画像（オプション）です
        let second: ImageItem?
        // ユーザーが選択したかどうかのフラグです
        var isSelected: Bool = false
    }

    // AIによる切り抜きエリア検出を実行します（ヒートマップ表示に切り替えます）
    func applyAIDetection() {
        if isHeatmapMode {
            // すでに表示中の場合は解除します
            isHeatmapMode = false
            heatmapImage = nil
            backgroundAnalysis = nil
            backgroundMaskImage = nil
            detectedBoundaries = []
            return
        }

        // ヒートマップを生成します
        generateHeatmap()
        isHeatmapMode = true
        isShowingCropBox = true
        
        // 自動的に属性検出（エリア設定）も実行し、完了後に吸着させます
        applyAutomaticAreaSetting(autoApply: true)
    }

    // 自動エリア設定を実行します（複数枚の画像からページ領域を自動判定します）
    // autoApply が true の場合、解析完了後に自動的に枠を吸着させます
    func applyAutomaticAreaSetting(autoApply: Bool = false) {
        // 画像がない、またはサイズ情報がない場合は中断します
        guard !items.isEmpty, displayedImageSize.width > 0, currentImagePixelSize.width > 0 else { return }

        // 背景分析中フラグを立てます
        isAnalyzingBackground = true

        // 現在の設定値をキャプチャします
        let threshold = UInt8(backgroundWhiteness)
        let tolerance = UInt8(backgroundTolerance)

        Task {
            // 3枚目（Index 2）から最大20枚を取得します
            let rangeStart = 2
            let rangeEnd = min(items.count, rangeStart + 20)

            guard rangeStart < items.count else {
                await MainActor.run { self.isAnalyzingBackground = false }
                return
            }

            let subset = Array(items[rangeStart..<rangeEnd])
            let urls = subset.map { $0.url }
            let width = Int(currentImagePixelSize.width)
            let height = Int(currentImagePixelSize.height)

            // 重い処理（画像読み込みと分析）をバックグラウンドで行います
            let analysisResult = await Task.detached(priority: .userInitiated) { () -> ([Bool], [Int])? in
                var imagesData: [[UInt8]] = []
                for url in urls {
                    if let img = NSImage(contentsOf: url),
                       let pixels = await PageDetector.rgbaPixels(img) {
                        imagesData.append(pixels)
                    }
                }
                guard !imagesData.isEmpty else { return nil }
                
                // 背景分析を実行
                let result = await PageDetector.analyzeBackground(images: imagesData, width: width, height: height, threshold: threshold, tolerance: tolerance)
                
                // 境界線の検出
                var columnVotes = [Int](repeating: 0, count: width)
                for y in 0..<height {
                    let rowOffset = y * width
                    for x in 0..<width {
                        if result[rowOffset + x] {
                            columnVotes[x] += 1
                        }
                    }
                }

                let isBackgroundColumn = columnVotes.map { $0 > (height / 2) }
                var detectedBoundaries: [Int] = []
                for x in 1..<width {
                    if isBackgroundColumn[x] != isBackgroundColumn[x-1] {
                        let centerX = width / 2
                        let ignoreMargin = width / 10
                        if abs(x - centerX) > ignoreMargin {
                            detectedBoundaries.append(x)
                        }
                    }
                }
                
                return (result, detectedBoundaries)
            }.value

            await MainActor.run {
                if let (result, boundaries) = analysisResult {
                    self.backgroundAnalysis = result
                    self.backgroundMaskImage = self.generateBackgroundMaskImage(mask: result, width: width, height: height)
                    self.detectedBoundaries = boundaries

                    // 解析完了後に自動吸着が指定されており、かつ境界線が見つかっている場合に実行します
                    if autoApply && !boundaries.isEmpty {
                        self.applyAutomaticAreaSpecified()
                    }
                }
                self.isAnalyzingBackground = false
            }
        }
    }

    // 自動エリア指定を実行します（検出された境界線に枠を合わせます）
    func applyAutomaticAreaSpecified() {
        guard !detectedBoundaries.isEmpty, displayedImageSize.width > 0, currentImagePixelSize.width > 0 else { return }
        
        // ピクセル座標からポイント座標への変換倍率
        let pixelToPointScale = displayedImageSize.width / currentImagePixelSize.width
        
        // 境界線を座標順（左から右）にソートします
        let sortedBoundaries = detectedBoundaries.sorted().map { CGFloat($0) * pixelToPointScale }
        
        guard let leftmost = sortedBoundaries.first, let rightmost = sortedBoundaries.last else { return }
        
        let halfWidth = displayedImageSize.width / 2.0
        
        if isSpreadMode {
            // 見開きモードの場合（常にcropRectが左側、cropRect2が右側として初期化されています）
            // 日本式かに関わらず、物理的な左側（Page 1 or 2）をleftmostに、右側をrightmostに合わせます
            
            // 左側枠 (常に左半分に配置)
            cropRect.origin.x = leftmost
            cropRect.origin.y = 0
            cropRect.size.width = max(40, halfWidth - leftmost)
            cropRect.size.height = displayedImageSize.height
            
            // 右側枠 (常に右半分に配置)
            cropRect2.origin.x = halfWidth
            cropRect2.origin.y = 0
            cropRect2.size.width = max(40, rightmost - halfWidth)
            cropRect2.size.height = displayedImageSize.height
        } else {
            // 単一モードの場合
            cropRect.origin.x = leftmost
            cropRect.origin.y = 0
            cropRect.size.width = max(40, rightmost - leftmost)
            cropRect.size.height = displayedImageSize.height
        }
        
        // 範囲外に出ないようにクランプします
        clampRectsToImageSize()
    }

    // 背景分析の結果を1つのNSImage（マスク画像）として生成します
    private func generateBackgroundMaskImage(mask: [Bool], width: Int, height: Int) -> NSImage? {
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)

        image.lockFocus()
        // 背景部分を半透明の赤色で塗りつぶします
        let color = NSColor.red.withAlphaComponent(0.3)
        color.set()

        // 描画を高速化するため、各行ごとに連続する範囲をまとめて描画します
        for y in 0..<height {
            let rowOffset = y * width
            var startX: Int? = nil

            for x in 0..<width {
                if mask[rowOffset + x] {
                    if startX == nil { startX = x }
                } else {
                    if let sX = startX {
                        // Core Graphics の座標系（左下原点）に合わせるため y を反転させます
                        NSRect(x: CGFloat(sX), y: CGFloat(height - 1 - y), width: CGFloat(x - sX), height: 1).fill()
                        startX = nil
                    }
                }
            }
            if let sX = startX {
                NSRect(x: CGFloat(sX), y: CGFloat(height - 1 - y), width: CGFloat(width - sX), height: 1).fill()
            }
        }

        image.unlockFocus()
        return image
    }

    // 全ての画像を重ね合わせたヒートマップ画像を生成します
    private func generateHeatmap() {
        guard !items.isEmpty else { return }
        
        // 最初の画像のサイズを基準にします
        guard let firstImage = NSImage(contentsOf: items[0].url) else { return }
        let baseSize = firstImage.size
        
        let newHeatmap = NSImage(size: baseSize)
        newHeatmap.lockFocus()
        
        // 透明度を計算します（枚数が多いほど1枚あたりの透明度を下げます）
        let opacity = CGFloat(max(0.05, 1.0 / CGFloat(min(items.count, 20))))
        
        for item in items.prefix(20) { // パフォーマンスのため最大20枚程度に制限するのも手
            if let img = NSImage(contentsOf: item.url) {
                img.draw(in: NSRect(origin: .zero, size: baseSize),
                        from: NSRect(origin: .zero, size: img.size),
                        operation: .sourceOver,
                        fraction: opacity)
            }
        }
        
        newHeatmap.unlockFocus()
        self.heatmapImage = newHeatmap
    }

    // 切り抜き枠が画像サイズ（displayedImageSize）を超えないようにクランプします
    func clampRectsToImageSize() {
        // 画像サイズが正しく設定されていない場合は何もしません
        guard displayedImageSize.width > 0 && displayedImageSize.height > 0 else { return }

        // 1つ目の枠を制限します
        cropRect = clamp(rect: cropRect, within: displayedImageSize)
        // 2つ目の枠を制限します
        cropRect2 = clamp(rect: cropRect2, within: displayedImageSize)
    }

    // 与えられた矩形を指定されたサイズ内に収めるプライベートメソッドです
    private func clamp(rect: CGRect, within size: CGSize) -> CGRect {
        var newRect = rect

        // サイズを制限します。最小40ピクセルを維持しつつ、画像幅・高さを超えないようにします
        newRect.size.width = min(max(40, rect.width), size.width)
        newRect.size.height = min(max(40, rect.height), size.height)

        // 座標を制限します。左端は0以上、右端は画像幅を超えないように調整します
        newRect.origin.x = max(0, min(rect.origin.x, size.width - newRect.size.width))
        // 上端は0以上、下端は画像高さを超えないように調整します
        newRect.origin.y = max(0, min(rect.origin.y, size.height - newRect.size.height))

        return newRect
    }

    // 見開きモードが有効になった際、2つの枠を初期配置（中心を境に左右並び）に設定します
    func setupInitialSpreadRects() {
        guard displayedImageSize.width > 0 && displayedImageSize.height > 0 else { return }
        
        // 画像サイズの半分を基準にします
        let halfWidth = displayedImageSize.width / 2.0
        let rectHeight = min(displayedImageSize.height * 0.8, 400) // 最大400ptか80%
        let rectWidth = min(halfWidth * 0.8, 300) // 最大300ptか80%
        
        let y = (displayedImageSize.height - rectHeight) / 2.0
        
        // 1つ目の枠（左側またはページ2）を中心より左側に配置
        cropRect = CGRect(
            x: halfWidth - rectWidth,
            y: y,
            width: rectWidth,
            height: rectHeight
        )
        
        // 2つ目の枠（右側またはページ1）を中心より右側に配置
        cropRect2 = CGRect(
            x: halfWidth,
            y: y,
            width: rectWidth,
            height: rectHeight
        )
    }

    // 2つの枠のサイズを同期させます（1枠のサイズを2枠へコピー）
    func syncCropSizes() {
        guard isSpreadMode else { return }
        
        if isJapaneseStyle {
            // 日本式: 1枠=cropRect2(左), 2枠=cropRect(右)
            // 2枠のサイズとY座標を1枠に合わせ、内側の辺(2枠のorigin.x)を固定します
            cropRect.size = cropRect2.size
            cropRect.origin.y = cropRect2.origin.y
        } else {
            // 標準: 1枠=cropRect(左), 2枠=cropRect2(右)
            // 2枠のサイズとY座標を1枠に合わせ、内側の辺(2枠のorigin.x)を固定します
            cropRect2.size = cropRect.size
            cropRect2.origin.y = cropRect.origin.y
        }
        
        // 範囲外に出ないようにクランプします
        clampRectsToImageSize()
    }

    // 通常モードの際、枠を初期配置（中心）に設定します
    func setupInitialSingleRect() {
        guard displayedImageSize.width > 0 && displayedImageSize.height > 0 else { return }
        
        let rectHeight = min(displayedImageSize.height * 0.8, 400)
        let rectWidth = min(displayedImageSize.width * 0.8, 300)
        
        cropRect = CGRect(
            x: (displayedImageSize.width - rectWidth) / 2.0,
            y: (displayedImageSize.height - rectHeight) / 2.0,
            width: rectWidth,
            height: rectHeight
        )
    }

    // 結合機能が利用可能かどうかを確認し、状態を更新します
    func refreshCombineAvailability() {
        // 出力先URLがない、または直前の書き出しが見開きモードでない場合は無効にします
        guard let url = lastOutputFolderURL, wasLastExportSpreadMode else {
            canCombine = false
            return
        }

        var isDir: ObjCBool = false
        // フォルダが存在するかチェックします
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // フォルダが存在する場合、画像ファイルが含まれているか軽くチェックします
            let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let imageExtensions = ["jpg", "jpeg", "png", "webp"]
            // いずれかの画像拡張子を持つファイルがあれば有効にします
            canCombine = files.contains { imageExtensions.contains($0.pathExtension.lowercased()) }
        } else {
            canCombine = false
        }
    }

    // フォルダ選択パネルを開き、選択されたフォルダから画像を読み込みます
    func pickFolder() {
        // フォルダを開くためのパネルを作成します
        let panel = NSOpenPanel()
        // ディレクトリを選択可能にします
        panel.canChooseDirectories = true
        // ファイルの選択を不可にします
        panel.canChooseFiles = false
        // 複数選択を不可にします
        panel.allowsMultipleSelection = false

        // ユーザーがOKボタンを押し、URLが取得できた場合に処理を実行します
        if panel.runModal() == .OK, let url = panel.url {
            // 指定されたURLから画像を読み込みます
            loadImages(from: url)
        }
    }

    // 指定されたフォルダURLから画像を非同期で読み込みます
    private func loadImages(from folderURL: URL) {
        // メインスレッドから切り離されたタスクで実行します
        Task.detached {
            // ファイルマネージャーのインスタンスを取得します
            let fileManager = FileManager.default

            // 指定されたディレクトリの内容をリストアップします。隠しファイルはスキップします
            let urls = (try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            // 対象とする画像の拡張子リストを定義します
            let imageExtensions = ["jpg", "jpeg", "png", "webp"]

            // ファイルURLの中から、対象の拡張子を持つものだけをフィルタリングします
            var imageURLs = urls.filter {
                // 拡張子を小文字にして、対象リストに含まれているかチェックします
                imageExtensions.contains($0.pathExtension.lowercased())
            }

            // 画像のファイル名を自然な順序（1, 2, 10...）で並び替えます
            imageURLs.sort { (url1, url2) -> Bool in
                // ファイル名を取得します
                let name1 = url1.lastPathComponent
                let name2 = url2.lastPathComponent
                // localizedStandardCompare を使用して、数字を含めた正しい順序で比較します
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }

            // フィルタリングと並び替えが完了した画像URLをImageItemオブジェクトに変換します
            let items = imageURLs.map { ImageItem(url: $0) }
            
            // 画像のサイズが一致しているかチェックします
            var localSizeMismatch = false
            if let firstURL = imageURLs.first {
                if let baseSize = await self.getImageSize(at: firstURL) {
                    for url in imageURLs.dropFirst() {
                        if let currentSize = await self.getImageSize(at: url) {
                            if currentSize != baseSize {
                                localSizeMismatch = true
                                break
                            }
                        }
                    }
                }
            }

            let sizeMismatchResult = localSizeMismatch

            // メインスレッドで結果をプロパティに反映させます
            await MainActor.run {
                // 画像アイテムリストを更新します
                self.items = items
                // サイズ不一致フラグを更新します
                self.hasSizeMismatch = sizeMismatchResult
                // 結合機能を無効化します（新しいフォルダを読み込んだため）
                self.canCombine = false
                self.lastOutputFolderURL = nil
                self.wasLastExportSpreadMode = false
                // 最初の画像をデフォルトで選択状態にします
                self.selectedID = items.first?.id
            }
        }
    }

    // 画像ファイルをメモリに完全ロードせずにサイズ（幅・高さ）を取得します
    private func getImageSize(at url: URL) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        
        let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        
        guard width > 0 && height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    // 全ての画像を切り抜いて一括保存する処理です
    func executeCropAll(folderName: String, fileNameBase: String) {
        // アイテムがない場合は何もしません
        guard let firstItem = items.first else { return }
        // 処理中のフラグを立てます
        isProcessing = true

        Task {
            // 読み込み元のフォルダURLを取得し、その中に保存用フォルダを作成します
            let sourceFolderURL = firstItem.url.deletingLastPathComponent()
            let outputFolderURL = sourceFolderURL.appendingPathComponent(folderName)

            // フォルダがなければ作成します
            try? FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)

            // 進行状況を初期化します
            await MainActor.run {
                self.totalCount = items.count
                self.processedCount = 0
            }

            // ページ番号をカウントします
            var pageCount = 1

            // 全ての画像アイテムに対してループ処理を行います
            for item in items {
                // 画像を読み込みます。失敗した場合はスキップします
                guard let image = NSImage(contentsOf: item.url) else { continue }

                // 切り抜きを行う枠の順序を取得します
                let rectsToCrop = getRectsToCrop()

                // 各枠で切り抜き処理を実行します
                await processImage(image, rectsToCrop: rectsToCrop, outputFolderURL: outputFolderURL, fileNameBase: fileNameBase, pageCount: &pageCount)
                
                // 処理済み件数を更新します
                await MainActor.run {
                    self.processedCount += 1
                }
            }

            // 全ての処理が完了したらメインスレッドでフラグを戻します
            await MainActor.run {
                self.lastOutputFolderURL = outputFolderURL
                // 一括書き出し時の見開きモードの状態を記録します
                self.wasLastExportSpreadMode = self.isSpreadMode
                self.refreshCombineAvailability()
                isProcessing = false
            }
        }
    }

    // 現在表示されている（選択されている）画像だけを切り抜いて保存する処理です
    func executeCropSelected(folderName: String, fileNameBase: String) {
        // 選択されているアイテムを取得します
        guard let selectedID = selectedID,
              let item = items.first(where: { $0.id == selectedID }) else { return }

        // 処理中のフラグを立てます
        isProcessing = true

        Task {
            // 読み込み元のフォルダURLを取得し、その中に保存用フォルダを作成します
            let sourceFolderURL = item.url.deletingLastPathComponent()
            let outputFolderURL = sourceFolderURL.appendingPathComponent(folderName)

            // フォルダがなければ作成します
            try? FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)

            // 進行状況を初期化します
            await MainActor.run {
                self.totalCount = 1
                self.processedCount = 0
            }

            // ページ番号をカウントします（この画像だけで完結するため1から開始）
//            var pageCount = 1

            // 画像を読み込みます
            guard let image = NSImage(contentsOf: item.url) else {
                await MainActor.run { isProcessing = false }
                return
            }

            // 個別切り抜き用の連番を検索します（_other_001, _other_002...）
            let otherBase = fileNameBase + "_other"
            var nextNumber = await findNextOtherNumber(in: outputFolderURL, fileNameBase: otherBase)
            
            // 切り抜きを行う枠の順序を取得します
            let rectsToCrop = getRectsToCrop()

            // 切り抜き処理を実行します（fileNameBaseに"_other"を付加し、pageCountに検索した連番を渡します）
            await processImage(image, rectsToCrop: rectsToCrop, outputFolderURL: outputFolderURL, fileNameBase: otherBase, pageCount: &nextNumber)

            // 完了後にフラグを戻します
            await MainActor.run {
                self.lastOutputFolderURL = outputFolderURL
                // 単一切り出しの場合は結合を許可しません
                self.wasLastExportSpreadMode = false
                self.refreshCombineAvailability()
                self.processedCount = 1
                isProcessing = false
            }
        }
    }

    // モード設定に基づいて、切り抜くべき矩形を正しい順序（ラベル1→2）で返します
    private func getRectsToCrop() -> [CGRect] {
        if isSpreadMode {
            if isJapaneseStyle {
                // 日本式（右開き）: 枠2がラベル「1」、枠1がラベル「2」として表示されています
                return [cropRect2, cropRect]
            } else {
                // 通常（左開き）: 枠1がラベル「1」、枠2がラベル「2」として表示されています
                return [cropRect, cropRect2]
            }
        } else {
            // 通常モードは単一の枠のみ
            return [cropRect]
        }
    }

    // 指定されたフォルダ内で "_other_XXX" 形式の次の空き番号を検索して返します
    private func findNextOtherNumber(in folderURL: URL, fileNameBase: String) async -> Int {
        let fileManager = FileManager.default
        let format = await MainActor.run { self.exportFormat }
        let ext = format.extensionName
        
        var index = 1
        while index < 1000 { // 999まで
            let testFileName = "\(fileNameBase)_\(String(format: "%03d", index)).\(ext)"
            if !fileManager.fileExists(atPath: folderURL.appendingPathComponent(testFileName).path) {
                return index
            }
            index += 1
        }
        return index
    }

    // 1枚の画像に対して指定された複数の枠で切り抜きと保存を行う共通処理です
    private func processImage(_ image: NSImage, rectsToCrop: [CGRect], outputFolderURL: URL, fileNameBase: String, pageCount: inout Int) async {
        // CGImageを取得して、実際のピクセルサイズに基づいた切り抜きを行います
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        // 実際のピクセル解像度を取得します
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // UI上の表示サイズと実際のピクセルサイズの比率を計算します
        let scaleX = displayedImageSize.width > 0 ? pixelWidth / displayedImageSize.width : 1.0
        let scaleY = displayedImageSize.height > 0 ? pixelHeight / displayedImageSize.height : 1.0

        for rect in rectsToCrop {
            // UI上のポイント座標を、画像の実ピクセル座標に正確に変換します
            let pixelRect = CGRect(
                x: rect.origin.x * scaleX,
                y: rect.origin.y * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )

            // CGImageを使用して、劣化のないピクセル単位の切り抜きを実行します
            if let croppedCGImage = cgImage.cropping(to: pixelRect) {
                // 切り抜かれたCGImageからNSImageを再構成します
                let croppedImage = NSImage(cgImage: croppedCGImage, size: pixelRect.size)

                // ファイル名を生成します（例: page_001.png）
                let (format, quality) = await MainActor.run { (self.exportFormat, self.jpgQuality) }
                let ext = format.extensionName
                let fileName = "\(fileNameBase)_\(String(format: "%03d", pageCount)).\(ext)"
                let fileURL = outputFolderURL.appendingPathComponent(fileName)

                // 指定された形式で保存します
                saveImage(croppedImage, to: fileURL, format: format, quality: quality)
                // ページ番号をカウントアップします
                pageCount += 1
            }
        }
    }

    // 書き出し先フォルダから画像を読み込みます
    func loadCroppedImages() -> [ImageItem] {
        // 出力先URLがない場合は空配列を返します
        guard let url = lastOutputFolderURL else { return [] }

        let fileManager = FileManager.default
        // フォルダ内のコンテンツを取得します
        let urls = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        // 対象の拡張子を定義します
        let imageExtensions = ["jpg", "jpeg", "png", "webp"]
        // 画像ファイルのみをフィルタリングします
        var imageURLs = urls.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }

        // ファイル名で自然な順序に並び替えます
        imageURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        // ImageItemのリストに変換して返します
        return imageURLs.map { ImageItem(url: $0) }
    }

    // 指定されたペアを結合して保存します
    func combineImages(pairs: [ImagePair], isJapaneseStyle: Bool) async {
        // 処理中フラグを立てます
        isProcessing = true

        // 現在の設定をキャプチャします（非同期タスクで使用するため）
        let format = self.exportFormat
        let quality = self.jpgQuality
        let shouldDelete = self.shouldDeleteOriginalsAfterCombine

        // 重い処理をバックグラウンドで実行します
        await Task.detached(priority: .userInitiated) {
            for pair in pairs {
                // 選択されていない、または2枚目がない場合はスキップします
                guard pair.isSelected, let second = pair.second else { continue }

                // CGImageを取得（劣化を避けるため）
                guard let img1 = NSImage(contentsOf: pair.first.url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let img2 = NSImage(contentsOf: second.url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

                // 日本式の場合は左右を入れ替えます
                let leftCG = isJapaneseStyle ? img2 : img1
                let rightCG = isJapaneseStyle ? img1 : img2

                // 各画像のサイズを取得します
                let width1 = CGFloat(leftCG.width)
                let height1 = CGFloat(leftCG.height)
                let width2 = CGFloat(rightCG.width)
                let height2 = CGFloat(rightCG.height)

                // 結合後の幅と高さを計算します
                let newWidth = width1 + width2
                let newHeight = max(height1, height2)

                // 結合用のビットマップコンテキストを作成します
                guard let context = CGContext(data: nil,
                                            width: Int(newWidth),
                                            height: Int(newHeight),
                                            bitsPerComponent: 8,
                                            bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }

                // コンテキストをクリア（透明化）します
                context.clear(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

                // 左側の画像を描画（上端合わせ：座標系が左下原点のため y = newHeight - height）
                context.draw(leftCG, in: CGRect(x: 0, y: newHeight - height1, width: width1, height: height1))

                // 右側の画像を描画
                context.draw(rightCG, in: CGRect(x: width1, y: newHeight - height2, width: width2, height: height2))

                // コンテキストから画像を作成します
                guard let combinedCG = context.makeImage() else { continue }
                let combinedImage = NSImage(cgImage: combinedCG, size: CGSize(width: newWidth, height: newHeight))

                // ファイル名を生成します (xx_001.png + xx_002.png -> xx_001_002.png)
                let base1 = pair.first.url.deletingPathExtension().lastPathComponent
                var secondPart = second.url.deletingPathExtension().lastPathComponent
                // 2枚目のファイル名の最後のアンダースコア以降（番号部分）を取得します
                if let lastUnderscoreRange = secondPart.range(of: "_", options: .backwards) {
                    secondPart = String(secondPart[lastUnderscoreRange.upperBound...])
                }

                // 拡張子を取得して最終的なパスを構築します
                let ext = pair.first.url.pathExtension
                let combinedFileName = "\(base1)_\(secondPart).\(ext)"
                let outputURL = pair.first.url.deletingLastPathComponent().appendingPathComponent(combinedFileName)

                // 非同期タスク内からメインアクターのメソッドを安全に呼び出し、画像を保存します
                await MainActor.run {
                    self.saveImage(combinedImage, to: outputURL, format: format, quality: quality)

                    // 保存が成功したか（ファイルが存在するか）確認してから元画像を削除します
                    if shouldDelete && FileManager.default.fileExists(atPath: outputURL.path) {
                        // キャッシュを削除します
                        ThumbnailCache.shared.removeThumbnail(for: pair.first.url)
                        ThumbnailCache.shared.removeThumbnail(for: second.url)
    
                        try? FileManager.default.removeItem(at: pair.first.url)
                        try? FileManager.default.removeItem(at: second.url)
                    }
                }
            }
        }.value

        // 処理中フラグを下ろします
        isProcessing = false
    }

    // 画像をファイルに保存するヘルパーメソッドです
    private func saveImage(_ image: NSImage, to url: URL, format: ExportFormat, quality: Double) {
        // NSImageから直接CGImageを取得して、メタデータを保持しつつ変換します
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        let data: Data?
        if format == .jpg {
            // JPEG形式のデータを生成します（圧縮率を指定）
            data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        } else {
            // PNG形式のデータを生成します
            data = bitmapRep.representation(using: .png, properties: [:])
        }

        // ファイルに書き出します
        if let data = data {
            try? data.write(to: url)
        }
    }

    // 外部から画像を保存するためのメソッドです（AutoScreenshotManagerなどで使用）
    func saveImageExternal(_ image: NSImage, to url: URL, format: ExportFormat, quality: Double) {
        saveImage(image, to: url, format: format, quality: quality)
    }

    // --- スクリーンショット機能のメソッド ---

    // スクリーンショット保存用のフォルダを選択します
    func pickScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to save screenshots"

        if panel.runModal() == .OK, let url = panel.url {
            self.screenshotFolderURL = url
            // 指定されたフォルダから画像を読み込みます
            loadImages(from: url)
        }
    }

    // 画面収録権限をチェックします
    func checkScreenCapturePermission() {
        isScreenCaptureEnabled = CGPreflightScreenCaptureAccess()
    }

    // 撮影した画像を保存し、リストに追加します
    private func saveCapturedImage(_ image: NSImage) {
        guard let folderURL = screenshotFolderURL else { return }

        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let fileName = "screenshot_\(dateFormater.string(from: Date())).png"
        let fileURL = folderURL.appendingPathComponent(fileName)

        saveImage(image, to: fileURL, format: .png, quality: 1.0)

        // 撮影音を鳴らします（確実に存在し、音量設定の影響を受けにくいNSSoundを使用します）
        // カメラのシャッター音に近いシステムサウンドを再生します
        NSSound(named: "Hero")?.play()

        capturedCount += 1

        // リストを更新（新しい画像を読み込む）
        loadImages(from: folderURL)
    }

    // 外部から画像を読み込むためのメソッドです（AutoScreenshotManagerなどで使用）
    func loadImagesExternal(from folderURL: URL) {
        loadImages(from: folderURL)
    }

    // 指定された画像アイテムを削除する処理です
    func deleteImages(_ itemsToDelete: [ImageItem]) {
        // ファイルマネージャーを取得します
        let fileManager = FileManager.default

        // 各アイテムに対して削除を試みます
        for item in itemsToDelete {
            // キャッシュを削除します
            ThumbnailCache.shared.removeThumbnail(for: item.url)

            try? fileManager.removeItem(at: item.url)
        }

        // スクリーンショット保存フォルダが設定されている場合
        if let folderURL = screenshotFolderURL {
            // リストを最新の状態に更新します
            loadImages(from: folderURL)
        }
    }

    // --- フローティングパネルのメソッド ---

    // フローティングパネルの表示・非表示を切り替えます
    func toggleFloatingPanel() {
        if isShowingFloatingPanel {
            hideFloatingPanel()
        } else {
            showFloatingPanel()
        }
    }

    // フローティングパネルを表示します
    private func showFloatingPanel() {
        guard floatingPanel == nil else { return }

        let view = FloatingButtonView().environmentObject(self)
        let panel = FloatingPanel(view: AnyView(view))

        // 画面中央付近に配置します（必要に応じて座標を調整可能）
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 30
            let y = screen.visibleFrame.midY - 30
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        floatingPanel = panel
        isShowingFloatingPanel = true
    }

    // フローティングパネルを閉じます
    private func hideFloatingPanel() {
        floatingPanel?.close()
        floatingPanel = nil
        isShowingFloatingPanel = false
    }

    // フローティングパネルからスクリーンショットを実行します
    func triggerFloatingScreenshot() {
        // 撮影前に権限をチェックします
        checkScreenCapturePermission()

        guard isScreenCaptureEnabled else {
            // 権限がない場合はOSの要求を呼び出します
            CGRequestScreenCaptureAccess()
            return
        }

        Task {
            // 1. パネル自体が写り込まないように一時的に透明化します
            let originalAlpha = floatingPanel?.alphaValue ?? 1.0
            await MainActor.run {
                floatingPanel?.alphaValue = 0.0
            }

            // 2. パネルが完全に消えるまで少しだけ待ちます（描画反映の遅延対策）
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

            do {
                // 3. メインディスプレイのキャプチャを実行
                let image = try await ScreenshotService.shared.captureMainDisplay()

                // 4. 保存処理を実行
                await MainActor.run {
                    saveCapturedImage(image)
                    // パネルの透明度を戻します
                    floatingPanel?.alphaValue = originalAlpha
                }
            } catch {
                print("Failed to capture floating screenshot: \(error)")
                await MainActor.run {
                    floatingPanel?.alphaValue = originalAlpha
                }
            }
        }
    }
}
