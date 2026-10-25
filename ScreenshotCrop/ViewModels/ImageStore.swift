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
// ファイル形式の識別子を扱うUniformTypeIdentifiersをインポートします
import UniformTypeIdentifiers

// メインスレッドで動作することを保証する、画像データを管理するためのストアクラスです
@MainActor
final class ImageStore: ObservableObject {
    enum CropMode: Hashable {
        case book
        case mockup
    }

    @Published var cropMode: CropMode = .book

    @Published var mockupContours: MockupContourResult?
    @Published var mockupContourImageID: UUID?
    @Published var isDetectingMockupContours = false
    @Published var mockupContourError: String?
    @Published var mockupContrast: Double = 3 {
        didSet { saveMockupDetectionSettings() }
    }
    @Published var mockupDetectsDarkOnLight = true {
        didSet { saveMockupDetectionSettings() }
    }
    @Published var mockupMaximumImageDimension = 2048 {
        didSet { saveMockupDetectionSettings() }
    }
    enum MockupPreviewBackground: Hashable {
        case checkerboard, white, black
    }

    @Published var isShowingMockupTransparencyPreview = false
    @Published var mockupPreviewBackground: MockupPreviewBackground = .checkerboard
    @Published var selectedMockupBodyCandidate: Int?
    private var mockupDetectionTask: Task<MockupContourResult, Error>?
    private var mockupDetectionID: UUID?

    @Published var lastMockupOutputURL: URL?
    @Published var mockupExportError: String?

    @Published var mockupBatchResult: MockupBatchResult?

    func exportAllMockups(folderName: String, fileNameBase: String) {
        guard canExportSelectedMockup, let result = mockupContours,
              let index = selectedMockupBodyCandidate,
              let reference = items.first(where: { $0.id == selectedID }) else { return }
        let points = result.contours[index]
        let urls = items.map(\.url)
        let referenceURL = reference.url
        isProcessing = true
        totalCount = urls.count
        processedCount = 0
        mockupExportError = nil
        mockupBatchResult = nil
        lastMockupOutputURL = nil
        Task {
            defer { isProcessing = false }
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try await MockupPNGExporter.saveBatch(
                        urls: urls, referenceURL: referenceURL, points: points,
                        folderName: folderName, fileNameBase: fileNameBase
                    ) { count in
                        await MainActor.run { self.processedCount = count }
                    }
                }.value
                mockupBatchResult = report
                lastMockupOutputURL = report.saved.last
            } catch {
                mockupExportError = error.localizedDescription
            }
        }
    }

    var canExportSelectedMockup: Bool {
        guard cropMode == .mockup, !isProcessing, !isDetectingMockupContours,
              selectedID != nil, selectedID == mockupContourImageID,
              let result = mockupContours, let index = selectedMockupBodyCandidate else { return false }
        return result.bodyCandidateIndices.contains(index)
    }

    func exportSelectedMockup(folderName: String, fileNameBase: String) {
        guard canExportSelectedMockup, let result = mockupContours,
              let index = selectedMockupBodyCandidate,
              let item = items.first(where: { $0.id == selectedID }) else { return }
        let points = result.contours[index]
        let url = item.url
        isProcessing = true
        totalCount = 1
        processedCount = 0
        mockupBatchResult = nil
        mockupExportError = nil
        lastMockupOutputURL = nil
        Task {
            defer { isProcessing = false }
            do {
                lastMockupOutputURL = try await Task.detached(priority: .userInitiated) {
                    try MockupPNGExporter.save(url: url, points: points,
                                               folderName: folderName, fileNameBase: fileNameBase)
                }.value
                processedCount = 1
            } catch {
                mockupExportError = error.localizedDescription
            }
        }
    }

    private func saveMockupDetectionSettings() {
        MockupDetectionSettings(contrast: mockupContrast,
                                detectsDarkOnLight: mockupDetectsDarkOnLight,
                                maximumImageDimension: mockupMaximumImageDimension).save()
    }

    func resetMockupDetectionSettings() {
        let settings = MockupDetectionSettings()
        mockupContrast = settings.contrast
        mockupDetectsDarkOnLight = settings.detectsDarkOnLight
        mockupMaximumImageDimension = settings.maximumImageDimension
    }

    func clearMockupContours() {
        mockupDetectionTask?.cancel()
        mockupDetectionTask = nil
        mockupDetectionID = nil
        isShowingMockupTransparencyPreview = false
        mockupContours = nil
        selectedMockupBodyCandidate = nil
        mockupContourImageID = nil
        mockupContourError = nil
        isDetectingMockupContours = false
    }

    func detectMockupContours() {
        guard cropMode == .mockup, !isDetectingMockupContours,
              let item = items.first(where: { $0.id == selectedID }) else { return }
        clearMockupContours()
        let detectionID = UUID()
        mockupDetectionID = detectionID
        isDetectingMockupContours = true
        let contrast = Float(mockupContrast)
        // 暗い背景上の本体と側面ボタンを検出するため、基準値は0に固定します。
        let contrastPivot: Float = 0
        let darkOnLight = mockupDetectsDarkOnLight
        let dimension = mockupMaximumImageDimension
        let url = item.url
        let task = Task.detached(priority: .userInitiated) {
            try MockupContourDetector.detect(url: url, contrast: contrast, contrastPivot: contrastPivot,
                                            detectsDarkOnLight: darkOnLight,
                                            maximumImageDimension: dimension)
        }
        mockupDetectionTask = task
        Task {
            do {
                let result = try await task.value
                guard mockupDetectionID == detectionID, selectedID == item.id else { return }
                mockupContours = result
                selectedMockupBodyCandidate = result.bodyCandidateIndices.first
                mockupContourImageID = item.id
            } catch {
                guard mockupDetectionID == detectionID else { return }
                mockupContourError = error.localizedDescription
            }
            guard mockupDetectionID == detectionID else { return }
            isDetectingMockupContours = false
            mockupDetectionTask = nil
        }
    }

    // 保存形式の定義
    enum ExportFormat: String, Sendable {
        case png = "PNG"
        case jpg = "JPEG"

        nonisolated var extensionName: String {
            return self.rawValue.lowercased()
        }
    }


    // 読み込まれた画像アイテムのリストです。変更時にビューに通知されます
    @Published var items: [ImageItem] = []
    // 現在選択されている画像のIDです。変更時にビューに通知されます
    @Published var selectedID: UUID? {
        didSet {
            if oldValue != selectedID { clearMockupContours() }
        }
    }
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
    @Published var shouldDeleteOriginalsAfterCombine: Bool = true
    // 直前に表紙統合を実行したかどうかのフラグです
    @Published var hasCompletedCoverCombine: Bool = false
    // 直前の書き出しが見開きモードだったかどうかのフラグです
    @Published var wasLastExportSpreadMode: Bool = false

    @Published private(set) var conversionFolderURL: URL?
    @Published private(set) var pngConversionCount = 0
    @Published var conversionJPGQuality = 0.8
    @Published private(set) var isConvertingImages = false
    @Published private(set) var convertedImageCount = 0
    @Published private(set) var imageConversionFailures: [String] = []
    private var loadedFolderURL: URL?

    // --- スクリーンショット機能用 ---
    // スクリーンショットモード中かどうかのフラグです
    @Published var isScreenshotMode: Bool = false
    // スクリーンショットの保存先フォルダURLです
    @Published var screenshotFolderURL: URL? = nil
    // 今回のセッションで撮影された枚数です
    @Published var capturedCount: Int = 0
    // スクリーンショット削除用ウィンドウの表示状態を管理します
    @Published var isShowingScreenshotCleanupSheet: Bool = false
    // スクリーンショットフォルダ仕分けウィンドウの表示状態を管理します
    @Published var isShowingFolderSplitSheet: Bool = false

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
    private var isRetired = false

    /// Stop the previous session without deleting any saved files.
    func prepareForReset() {
        isRetired = true
        autoManager.stopAutoCapture()
        hideFloatingPanel()
        clearMockupContours()
        cancellables.removeAll()
        isShowingScreenshotCleanupSheet = false
        isShowingFolderSplitSheet = false
        isScreenshotMode = false
    }

    // ストアを初期化します
    init() {
        let settings = MockupDetectionSettings.load()
        mockupContrast = settings.contrast
        mockupDetectsDarkOnLight = settings.detectsDarkOnLight
        mockupMaximumImageDimension = settings.maximumImageDimension

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
            guard !isRetired else { return }
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

    // 画像結合のモードです
    enum CombineMode: Sendable {
        case spread // 見開き統合
        case cover  // 表紙統合
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
        guard !isRetired, !items.isEmpty, displayedImageSize.width > 0, currentImagePixelSize.width > 0 else { return }

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
                    guard !self.isRetired else { return }
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

    // 表示サイズに対する実際のピクセルサイズの倍率
    var scaleX: CGFloat {
        displayedImageSize.width > 0 ? currentImagePixelSize.width / displayedImageSize.width : 1.0
    }
    var scaleY: CGFloat {
        displayedImageSize.height > 0 ? currentImagePixelSize.height / displayedImageSize.height : 1.0
    }

    // 指定された矩形の実際のピクセルサイズを計算します
    func pixelSize(for rect: CGRect) -> (width: Int, height: Int) {
        (
            width: Int(round(rect.width * scaleX)),
            height: Int(round(rect.height * scaleY))
        )
    }

    // 切り抜き枠の幅をピクセル単位で微調整します
    // page: 1 または 2（単一モード時は 1）
    // delta: 増減ピクセル数（+1, -1 など）
    func adjustCropWidth(page: Int, delta: Int) {
        guard displayedImageSize.width > 0 && currentImagePixelSize.width > 0 else { return }

        let sX = scaleX
        if isSpreadMode {
            // 見開きモード
            // 日本式の場合: Page 1 = cropRect2(右側), Page 2 = cropRect(左側)
            // 標準の場合: Page 1 = cropRect(左側), Page 2 = cropRect2(右側)
            let isLeftBox = (page == 1 && !isJapaneseStyle) || (page == 2 && isJapaneseStyle)

            if isLeftBox {
                // 左側枠 (cropRect)
                // 内側（右端 maxX）を固定し、外側（左端 origin.x）を伸縮
                let currentPx = pixelSize(for: cropRect).width
                let targetPx = max(10, currentPx + delta)
                let newWidth = CGFloat(targetPx) / sX
                let rightBoundary = cropRect.maxX

                var newRect = cropRect
                newRect.size.width = newWidth
                newRect.origin.x = rightBoundary - newWidth

                if newRect.origin.x < 0 {
                    newRect.origin.x = 0
                    newRect.size.width = rightBoundary
                }
                cropRect = newRect
            } else {
                // 右側枠 (cropRect2)
                // 内側（左端 origin.x）を固定し、外側（右端 maxX）を伸縮
                let currentPx = pixelSize(for: cropRect2).width
                let targetPx = max(10, currentPx + delta)
                let newWidth = CGFloat(targetPx) / sX

                var newRect = cropRect2
                newRect.size.width = newWidth

                if newRect.maxX > displayedImageSize.width {
                    newRect.size.width = max(10, displayedImageSize.width - newRect.origin.x)
                }
                cropRect2 = newRect
            }
        } else {
            // 単一モード (cropRect)
            // 中心 (midX) を維持して左右均等に伸縮
            let currentPx = pixelSize(for: cropRect).width
            let maxPx = Int(round(displayedImageSize.width * sX))
            let targetPx = min(max(10, currentPx + delta), maxPx)
            let newWidth = CGFloat(targetPx) / sX
            let diff = newWidth - cropRect.width

            var newRect = cropRect
            newRect.size.width = newWidth
            newRect.origin.x = cropRect.origin.x - (diff / 2.0)

            if newRect.origin.x < 0 {
                newRect.origin.x = 0
            } else if newRect.maxX > displayedImageSize.width {
                newRect.origin.x = max(0, displayedImageSize.width - newRect.size.width)
            }
            cropRect = newRect
        }

        clampRectsToImageSize()
    }

    // 切り抜き枠の高さをピクセル単位で微調整します
    // page: 1 または 2（単一モード時は 1）
    // delta: 増減ピクセル数（+1, -1 など）
    func adjustCropHeight(page: Int, delta: Int) {
        guard displayedImageSize.height > 0 && currentImagePixelSize.height > 0 else { return }

        let sY = scaleY
        if isSpreadMode {
            // 見開きモード
            let isLeftBox = (page == 1 && !isJapaneseStyle) || (page == 2 && isJapaneseStyle)
            let targetRect = isLeftBox ? cropRect : cropRect2

            // 見開き時は上端 (origin.y) を固定して下方向へ伸縮
            let currentPx = pixelSize(for: targetRect).height
            let maxPx = Int(round(displayedImageSize.height * sY))
            let targetPx = min(max(10, currentPx + delta), maxPx)
            let newHeight = CGFloat(targetPx) / sY

            var newRect = targetRect
            newRect.size.height = newHeight

            // 下端が画像外に出る場合は、上端を引き上げて収める
            if newRect.maxY > displayedImageSize.height {
                newRect.origin.y = max(0, displayedImageSize.height - newHeight)
                newRect.size.height = min(newHeight, displayedImageSize.height - newRect.origin.y)
            }

            if isLeftBox {
                cropRect = newRect
            } else {
                cropRect2 = newRect
            }
        } else {
            // 単一モード (cropRect)
            // 中心 (midY) を維持して上下均等に伸縮
            let currentPx = pixelSize(for: cropRect).height
            let maxPx = Int(round(displayedImageSize.height * sY))
            let targetPx = min(max(10, currentPx + delta), maxPx)
            let newHeight = CGFloat(targetPx) / sY
            let diff = newHeight - cropRect.height

            var newRect = cropRect
            newRect.size.height = newHeight
            newRect.origin.y = cropRect.origin.y - (diff / 2.0)

            if newRect.origin.y < 0 {
                newRect.origin.y = 0
            } else if newRect.maxY > displayedImageSize.height {
                newRect.origin.y = max(0, displayedImageSize.height - newRect.size.height)
            }
            cropRect = newRect
        }

        clampRectsToImageSize()
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

    // 出力先（または読み込んだCroppedフォルダ）のPNG画像を確認します。
    func refreshImageConversionAvailability(folderName: String) {
        guard !isConvertingImages else { return }
        let folder = lastOutputFolderURL ?? loadedFolderURL.map {
            ($0.lastPathComponent == folderName || $0.lastPathComponent == "Cropped")
                ? $0 : $0.appendingPathComponent(folderName, isDirectory: true)
        }
        if conversionFolderURL != folder {
            convertedImageCount = 0
            imageConversionFailures = []
        }
        conversionFolderURL = folder
        pngConversionCount = folder.flatMap { try? PNGToJPEGConverter.pngFiles(in: $0).count } ?? 0
    }

    func convertCroppedPNGToJPEG(folderName: String) {
        guard !isProcessing, !isAnalyzingBackground else { return }
        refreshImageConversionAvailability(folderName: folderName)
        guard let folder = conversionFolderURL else { return }
        let urls: [URL]
        do {
            urls = try PNGToJPEGConverter.pngFiles(in: folder)
        } catch {
            imageConversionFailures = [error.localizedDescription]
            return
        }
        guard !urls.isEmpty else { return }
        let quality = conversionJPGQuality
        isProcessing = true
        isConvertingImages = true
        processedCount = 0
        totalCount = urls.count
        convertedImageCount = 0
        imageConversionFailures = []

        Task {
            for url in urls {
                do {
                    let output = try await Task.detached(priority: .userInitiated) {
                        try autoreleasepool { try PNGToJPEGConverter.convert(url, quality: quality) }
                    }.value
                    ThumbnailCache.shared.removeThumbnail(for: url)
                    // Keep the sidebar valid when Cropped itself is open.
                    if let index = items.firstIndex(where: { $0.url == url }) {
                        let wasSelected = selectedID == items[index].id
                        items[index] = ImageItem(url: output)
                        if wasSelected { selectedID = items[index].id }
                    }
                    if lastMockupOutputURL == url { lastMockupOutputURL = nil }
                    convertedImageCount += 1
                } catch {
                    imageConversionFailures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                processedCount += 1
            }
            isConvertingImages = false
            isProcessing = false
            refreshImageConversionAvailability(folderName: folderName)
            refreshCombineAvailability()
        }
    }

    // 出力先フォルダを特定して返します。
    func resolveOutputFolderURL(folderName: String) -> URL? {
        if let last = lastOutputFolderURL, FileManager.default.fileExists(atPath: last.path) {
            return last
        }
        if let conversion = conversionFolderURL, FileManager.default.fileExists(atPath: conversion.path) {
            return conversion
        }
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = name.isEmpty ? "Cropped" : name
        if let loaded = loadedFolderURL {
            let candidate = (loaded.lastPathComponent == effectiveName || loaded.lastPathComponent == "Cropped")
                ? loaded : loaded.appendingPathComponent(effectiveName, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let first = items.first {
            let parent = first.url.deletingLastPathComponent()
            let candidate = parent.appendingPathComponent(effectiveName, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // 出力先フォルダ名を変更し、内部参照を更新します。
    func renameOutputFolder(from oldURL: URL, to newName: String) throws -> URL {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName != oldURL.lastPathComponent else {
            return oldURL
        }
        let parent = oldURL.deletingLastPathComponent()
        let newURL = parent.appendingPathComponent(cleanName, isDirectory: true)

        if FileManager.default.fileExists(atPath: newURL.path) {
            throw NSError(
                domain: "ImageStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "A folder named '\(cleanName)' already exists."]
            )
        }

        try FileManager.default.moveItem(at: oldURL, to: newURL)

        if lastOutputFolderURL == oldURL {
            lastOutputFolderURL = newURL
        }
        if conversionFolderURL == oldURL {
            conversionFolderURL = newURL
        }
        if loadedFolderURL == oldURL {
            loadedFolderURL = newURL
        }
        return newURL
    }

    // 現在作業中の対象フォルダURLを取得します（ステップ1で指定したフォルダ）
    var currentWorkingFolderURL: URL? {
        if let loaded = loadedFolderURL {
            return loaded
        }
        if let first = items.first {
            return first.url.deletingLastPathComponent()
        }
        if let screenshot = screenshotFolderURL {
            return screenshot
        }
        return nil
    }

    // ステップ1で指定されたフォルダ内の画像データとクロップフォルダを削除します（ZIPファイルは保護）
    func deleteWorkingFolderImagesAndCropFolders() {
        guard let targetFolderURL = currentWorkingFolderURL else { return }

        let fileManager = FileManager.default
        guard let itemsInFolder = try? fileManager.contentsOfDirectory(
            at: targetFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let imageExtensions = ["png", "jpg", "jpeg"]

        for itemURL in itemsInFolder {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                // ディレクトリ（クロップフォルダなど）の場合
                // 内部にZIPファイルが存在するか再帰的にチェック
                if directoryContainsZip(at: itemURL) {
                    // ZIPが存在する場合はフォルダ自体を削除せず、内部の画像ファイル(PNG/JPG)のみを削除
                    deleteImagesRecursively(in: itemURL)
                } else {
                    // ZIPが存在しない場合はフォルダごと丸ごと削除
                    try? fileManager.removeItem(at: itemURL)
                }
            } else {
                // ファイルの場合
                let ext = itemURL.pathExtension.lowercased()
                if ext == "zip" {
                    // ZIPファイルは絶対に消さない
                    continue
                } else if imageExtensions.contains(ext) {
                    // PNG, JPGファイルは削除
                    try? fileManager.removeItem(at: itemURL)
                }
            }
        }
    }

    // ディレクトリ内にZIPファイルが存在するかを再帰的に確認します
    private func directoryContainsZip(at directoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "zip" {
                return true
            }
        }
        return false
    }

    // ディレクトリ内の画像ファイル（PNG/JPG）を再帰的に削除します
    private func deleteImagesRecursively(in directoryURL: URL) {
        let fileManager = FileManager.default
        let imageExtensions = ["png", "jpg", "jpeg"]

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var urlsToDelete: [URL] = []
        for case let fileURL as URL in enumerator {
            if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
                urlsToDelete.append(fileURL)
            }
        }

        for fileURL in urlsToDelete {
            try? fileManager.removeItem(at: fileURL)
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
        guard !isRetired else { return }
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
                guard !self.isRetired else { return }
                self.items = items
                self.loadedFolderURL = folderURL
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

    // オーバーレイの表示状態に関係なく、切り抜きの準備が整っているかを判定します。
    var canExecuteCropAll: Bool {
        guard !isRetired, cropMode == .book, !isScreenshotMode,
              !isProcessing, !isAnalyzingBackground,
              !items.isEmpty, isShowingCropBox,
              displayedImageSize.width.isFinite, displayedImageSize.height.isFinite,
              displayedImageSize.width > 0, displayedImageSize.height > 0 else { return false }

        let imageBounds = CGRect(origin: .zero, size: displayedImageSize)
        return getRectsToCrop().allSatisfy { rect in
            rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
            && imageBounds.contains(rect)
        }
    }

    // 全ての画像を切り抜いて一括保存する処理です
    func executeCropAll(folderName: String, fileNameBase: String) {
        guard canExecuteCropAll, let firstItem = items.first else { return }
        hasCompletedCoverCombine = false
        // 処理途中の画像選択や枠・表示サイズの変更に影響されないよう固定します。
        let itemsToCrop = items
        let rectsToCrop = getRectsToCrop()
        let referenceImageSize = displayedImageSize
        let wasSpreadMode = isSpreadMode
        let format = self.exportFormat
        let quality = self.jpgQuality
        // 処理中のフラグを立てます
        isProcessing = true

        Task.detached(priority: .userInitiated) {
            // 読み込み元のフォルダURLを取得し、その中に保存用フォルダを作成します
            let sourceFolderURL = firstItem.url.deletingLastPathComponent()
            let outputFolderURL = sourceFolderURL.appendingPathComponent(folderName)

            // フォルダがなければ作成します
            try? FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)

            // 進行状況を初期化します
            await MainActor.run {
                self.totalCount = itemsToCrop.count
                self.processedCount = 0
            }

            // ページ番号をカウントします
            var pageCount = 1

            // 全ての画像アイテムに対してループ処理を行います
            for item in itemsToCrop {
                // CGImageSourceから直接読み込みます（NSImageのRetina依存・再サンプリングを完全にバイパス）
                guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }

                // 各枠で切り抜き処理を直接実行します
                Self.processCGImageDirect(
                    cgImage,
                    rectsToCrop: rectsToCrop,
                    referenceImageSize: referenceImageSize,
                    outputFolderURL: outputFolderURL,
                    fileNameBase: fileNameBase,
                    format: format,
                    quality: quality,
                    pageCount: &pageCount
                )

                // 処理済み件数を更新します
                await MainActor.run {
                    self.processedCount += 1
                }
            }

            // 全ての処理が完了したらメインスレッドでフラグを戻します
            await MainActor.run {
                self.lastOutputFolderURL = outputFolderURL
                // 一括書き出し時の見開きモードの状態を記録します
                self.wasLastExportSpreadMode = wasSpreadMode
                self.refreshCombineAvailability()
                self.isProcessing = false
            }
        }
    }

    // 現在表示されている（選択されている）画像だけを切り抜いて保存する処理です
    func executeCropSelected(folderName: String, fileNameBase: String) {
        // モック用の透過マスクを実装するまでは書き出しを行いません。
        guard cropMode == .book else { return }
        // 選択されているアイテムを取得します
        guard let selectedID = selectedID,
              let item = items.first(where: { $0.id == selectedID }) else { return }

        let rectsToCrop = getRectsToCrop()
        let referenceImageSize = displayedImageSize
        let format = self.exportFormat
        let quality = self.jpgQuality
        // 処理中のフラグを立てます
        isProcessing = true

        Task.detached(priority: .userInitiated) {
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

            // 画像を直接読み込みます
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                await MainActor.run { self.isProcessing = false }
                return
            }

            // 個別切り抜き用の連番を検索します（_other_001, _other_002...）
            let otherBase = fileNameBase + "_other"
            var nextNumber = Self.findNextOtherNumberDirect(in: outputFolderURL, fileNameBase: otherBase, format: format)

            // 切り抜き処理を実行します
            Self.processCGImageDirect(
                cgImage,
                rectsToCrop: rectsToCrop,
                referenceImageSize: referenceImageSize,
                outputFolderURL: outputFolderURL,
                fileNameBase: otherBase,
                format: format,
                quality: quality,
                pageCount: &nextNumber
            )

            // 完了後にフラグを戻します
            await MainActor.run {
                self.lastOutputFolderURL = outputFolderURL
                // 単一切り出しの場合は結合を許可しません
                self.wasLastExportSpreadMode = false
                self.refreshCombineAvailability()
                self.processedCount = 1
                self.isProcessing = false
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

    // 指定されたフォルダ内で "_other_XXX" 形式の次の空き番号を検索して返します（直接同期実行）
    nonisolated private static func findNextOtherNumberDirect(in folderURL: URL, fileNameBase: String, format: ExportFormat) -> Int {
        let fileManager = FileManager.default
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

    // 1枚の画像に対して指定された複数の枠で切り抜きと保存を行う共通処理です（完全バックグラウンド・Retina非依存）
    nonisolated private static func processCGImageDirect(
        _ cgImage: CGImage,
        rectsToCrop: [CGRect],
        referenceImageSize: CGSize,
        outputFolderURL: URL,
        fileNameBase: String,
        format: ExportFormat,
        quality: Double,
        pageCount: inout Int
    ) {
        // 実際のピクセル解像度を取得します
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // 処理開始時の表示サイズと実際のピクセルサイズの比率を計算します
        let scaleX = referenceImageSize.width > 0 ? pixelWidth / referenceImageSize.width : 1.0
        let scaleY = referenceImageSize.height > 0 ? pixelHeight / referenceImageSize.height : 1.0

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
                // ファイル名を生成します（例: page_001.png）
                let ext = format.extensionName
                let fileName = "\(fileNameBase)_\(String(format: "%03d", pageCount)).\(ext)"
                let fileURL = outputFolderURL.appendingPathComponent(fileName)

                // 指定された形式で直接ファイルに高速保存します
                saveCGImageDirect(croppedCGImage, to: fileURL, format: format, quality: quality)
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
    func combineImages(pairs: [ImagePair], isJapaneseStyle: Bool, mode: CombineMode = .spread) async {
        // 処理中フラグを立てます
        isProcessing = true

        // 現在の設定をキャプチャします（非同期タスクで使用するため）
        let format = self.exportFormat
        let quality = self.jpgQuality
        let shouldDelete = self.shouldDeleteOriginalsAfterCombine
        let isCoverMode = (mode == .cover)

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

                let finalCG: CGImage
                if isCoverMode {
                    // 表紙統合: 2枚の横幅の平均値を切り抜き幅とし、中央で切り抜く
                    let cropWidth = round((width1 + width2) / 2.0)
                    let cropX = round((newWidth - cropWidth) / 2.0)
                    let cropRect = CGRect(x: cropX, y: 0, width: cropWidth, height: newHeight)
                    guard let croppedCG = combinedCG.cropping(to: cropRect) else { continue }
                    finalCG = croppedCG
                } else {
                    finalCG = combinedCG
                }

                let outputURL: URL
                if isCoverMode {
                    // 表紙統合の場合、1枚目のファイル名を引き継ぐ
                    outputURL = pair.first.url
                } else {
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
                    outputURL = pair.first.url.deletingLastPathComponent().appendingPathComponent(combinedFileName)
                }

                // ファイルに直接保存します（バックグラウンド処理）
                Self.saveCGImageDirect(finalCG, to: outputURL, format: format, quality: quality)

                // メインアクターでキャッシュ更新と元画像削除を行います
                await MainActor.run {
                    ThumbnailCache.shared.removeThumbnail(for: pair.first.url)
                    ThumbnailCache.shared.removeThumbnail(for: second.url)

                    // 保存が成功したか（ファイルが存在するか）確認してから元画像を削除します
                    if shouldDelete && FileManager.default.fileExists(atPath: outputURL.path) {
                        if isCoverMode {
                            // 表紙統合の場合、1枚目は新しい表紙画像として上書きされたため、2枚目のみ削除します
                            try? FileManager.default.removeItem(at: second.url)
                        } else {
                            try? FileManager.default.removeItem(at: pair.first.url)
                            try? FileManager.default.removeItem(at: second.url)
                        }
                    }
                }
            }
        }.value

        // 処理中フラグを下ろします
        isProcessing = false

        if mode == .cover {
            hasCompletedCoverCombine = true
        } else if mode == .spread {
            hasCompletedCoverCombine = false
        }
    }

    // CGImageをファイルに直接高速保存するヘルパーメソッドです（Retinaやディスプレイ解像度の影響を完全に排除）
    nonisolated private static func saveCGImageDirect(_ cgImage: CGImage, to url: URL, format: ExportFormat, quality: Double) {
        let typeIdentifier: CFString = (format == .jpg) ? UTType.jpeg.identifier as CFString : UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier, 1, nil) else { return }

        var imageToAdd = cgImage
        var properties: [CFString: Any] = [:]

        if format == .jpg {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
            // アルファチャンネルがある場合、白背景で不透明化
            let alphaInfo = cgImage.alphaInfo
            let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipLast && alphaInfo != .noneSkipFirst
            if hasAlpha {
                let width = cgImage.width
                let height = cgImage.height
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                if let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) {
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(bounds)
                    context.draw(cgImage, in: bounds)
                    if let opaque = context.makeImage() {
                        imageToAdd = opaque
                    }
                }
            }
        }

        CGImageDestinationAddImage(destination, imageToAdd, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    // 画像をファイルに保存するヘルパーメソッドです
    private func saveImage(_ image: NSImage, to url: URL, format: ExportFormat, quality: Double) {
        // NSImageから直接CGImageを取得して、メタデータを保持しつつ変換します
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Self.saveCGImageDirect(cgImage, to: url, format: format, quality: quality)
    }

    // 外部から画像を保存するためのメソッドです（AutoScreenshotManagerなどで使用）
    func saveImageExternal(_ image: NSImage, to url: URL, format: ExportFormat, quality: Double) {
        guard !isRetired else { return }
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
        guard !isRetired, let folderURL = screenshotFolderURL else { return }

        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let fileName = "screenshot_\(dateFormater.string(from: Date())).png"
        let fileURL = folderURL.appendingPathComponent(fileName)

        saveImage(image, to: fileURL, format: .png, quality: 1.0)

        // 撮影音を鳴らします（確実に存在し、音量設定の影響を受けにくいNSSoundを使用します）
        // カメラのシャッター音に近いシステムサウンドを再生します
        // 連続再生時に音が途切れないよう、再生中の場合は複製して再生します
        if let sound = NSSound(named: "Hero") {
            if sound.isPlaying {
                (sound.copy() as? NSSound)?.play()
            } else {
                sound.play()
            }
        }
        
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

    // 画像を指定された巻フォルダごとに仕分ける処理です
    func organizeImagesIntoVolumes(
        groups: [(folderName: String, items: [ImageItem])],
        itemsToDelete: [ImageItem] = [],
        renumberFiles: Bool = false
    ) {
        let fileManager = FileManager.default
        guard let baseFolderURL = screenshotFolderURL else { return }

        // 不要なアイテムを削除
        for item in itemsToDelete {
            ThumbnailCache.shared.removeThumbnail(for: item.url)
            try? fileManager.removeItem(at: item.url)
        }

        // 各グループごとにフォルダ作成してファイルを移動
        for group in groups {
            guard !group.items.isEmpty else { continue }
            let targetFolderURL = baseFolderURL.appendingPathComponent(group.folderName, isDirectory: true)

            if !fileManager.fileExists(atPath: targetFolderURL.path) {
                try? fileManager.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
            }

            for (index, item) in group.items.enumerated() {
                ThumbnailCache.shared.removeThumbnail(for: item.url)
                let ext = item.url.pathExtension
                let newFileName: String
                if renumberFiles {
                    newFileName = String(format: "%03d.%@", index + 1, ext)
                } else {
                    newFileName = item.url.lastPathComponent
                }
                let destinationURL = targetFolderURL.appendingPathComponent(newFileName)

                var finalDestURL = destinationURL
                var counter = 1
                while fileManager.fileExists(atPath: finalDestURL.path) && finalDestURL != item.url {
                    let baseName = destinationURL.deletingPathExtension().lastPathComponent
                    finalDestURL = targetFolderURL.appendingPathComponent("\(baseName)_\(counter).\(ext)")
                    counter += 1
                }

                try? fileManager.moveItem(at: item.url, to: finalDestURL)
            }
        }

        // リストを最新の状態に更新します
        loadImages(from: baseFolderURL)
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
        guard !isRetired else { return }
        // 撮影前に権限をチェックします
        checkScreenCapturePermission()

        guard isScreenCaptureEnabled else {
            // 権限がない場合はOSの要求を呼び出します
            CGRequestScreenCaptureAccess()
            return
        }

        Task {
            // 1. パネル自体が写り込まないように一時的に透明化します
            guard !isRetired else { return }
            let originalAlpha = floatingPanel?.alphaValue ?? 1.0
            await MainActor.run {
                floatingPanel?.alphaValue = 0.0
            }

            // 2. パネルが完全に消えるまで少しだけ待ちます（描画反映の遅延対策）
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            guard !isRetired else { return }

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
