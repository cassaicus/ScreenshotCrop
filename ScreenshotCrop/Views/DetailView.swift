// SwiftUIフレームワークをインポートします
import SwiftUI
// macOSのAppKitフレームワークをインポートします
import AppKit

// 画像の詳細表示と切り抜き操作を行うビューです
struct DetailView: View {

    // 環境オブジェクトからImageStoreを取得します
    @EnvironmentObject var store: ImageStore
    // 親ビューと共有する画像拡大率のバインディングです
    @Binding var scale: CGFloat
    
    // ピンチジェスチャなどによる一時的な拡大率を保持します
    @GestureState private var magnifyBy: CGFloat = 1.0
    // 読み込まれたフルサイズ画像を保持する状態変数です
    @State private var fullImage: NSImage?
    // 切り抜き枠の点線アニメーション用の位相状態です
    @State private var dashPhase: CGFloat = 0
    // リサイズ時の一時的な座標オフセットを保持します
    @State private var dragOffset: CGSize = .zero
    
    // ドラッグ開始時の切り抜き枠の座標とサイズを保持します
    @State private var initialCropRect: CGRect = .zero
    // 2つ目の切り抜き枠のドラッグ開始時の状態を保持します
    @State private var initialCropRect2: CGRect = .zero

    // 画像の表示位置をオフセットするための状態変数です
    @State private var imageOffset: CGSize = .zero
    // ドラッグ開始時の画像オフセットを保持します
    @State private var initialImageOffset: CGSize = .zero
    // 切り抜き枠をドラッグ中かどうかを保持するフラグです
    @State private var isDraggingCropBox: Bool = false
    // マウスイベントを監視するためのモニターです
    @State private var eventMonitor: Any?
    // ビューのサイズを保持するための変数です
    @State private var viewSize: CGSize = .zero
    // 右ドラッグが実行されたかどうかを管理するフラグです
    @State private var hasMoved: Bool = false
    // 高さ合わせのアシスト線を表示するための座標リストです
    @State private var snapLines: [CGFloat] = []

    // 幅合わせ用のアシスト線を表す構造体です
    struct LineGeometry: Hashable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
    }
    // 幅合わせ用のアシスト線を保持するリストです
    @State private var widthSnapLines: [LineGeometry] = []

    // 高さ合わせ用（垂直）のアシスト線を表す構造体です
    struct VLineGeometry: Hashable {
        let x: CGFloat
        let y: CGFloat
        let height: CGFloat
    }
    // 高さ合わせ用のアシスト線を保持するリストです
    @State private var heightSnapLines: [VLineGeometry] = []

    // 現在選択されている画像アイテムをストアから取得します
    var selectedItem: ImageItem? {
        // IDが一致する最初のアイテムを返します
        store.items.first { $0.id == store.selectedID }
    }

    // ビューの階層構造を定義します
    var body: some View {
        // ビューのサイズを取得するためにGeometryReaderを使用します
        GeometryReader { geometry in
            // ジオメトリリーダー内でコンテンツを中央に配置するためのZStackです
            ZStack(alignment: .center) {
                // 親ビューのサイズをキャプチャし、Preferenceとして上位に伝えます
                Color.clear
                    .preference(key: ViewSizeKey.self, value: geometry.size)

            // 条件によって表示を切り替えるGroupです
            Group {
                // フルサイズ画像またはヒートマップ画像が読み込まれている場合に表示します
            if let image = store.isHeatmapMode ? store.heatmapImage : fullImage {
                    // 画像を表示します
                    Image(nsImage: image)
                        // サイズ変更を可能にします
                        .resizable()
                        // アスペクト比を維持してフィットさせます
                        .scaledToFit()
                        // 画像が表示された際やサイズが変わった際に、その表示サイズをストアに保存します
                        // これにより、実際の画像サイズとの比率を計算して正確な切り抜きを可能にします
                        .background(
                            GeometryReader { imgGeo in
                                Color.clear
                                    .onAppear {
                                        Task { @MainActor in
                                            if store.displayedImageSize != imgGeo.size {
                                                store.displayedImageSize = imgGeo.size
                                                // 初回表示時に枠を中央に配置します
                                                if !store.isSpreadMode {
                                                    store.setupInitialSingleRect()
                                                } else {
                                                    store.setupInitialSpreadRects()
                                                }
                                                // 画像が表示された際に枠を範囲内に収めます
                                                store.clampRectsToImageSize()
                                            }
                                        }
                                    }
                                    .onChange(of: imgGeo.size) { _, newSize in
                                        Task { @MainActor in
                                            let diffX = abs(newSize.width - store.displayedImageSize.width)
                                            let diffY = abs(newSize.height - store.displayedImageSize.height)
                                            
                                            // 1.0ピクセル以上の有意なサイズ変更時のみ処理を行います（微小な丸め誤差による無限更新を防ぐため）
                                            if diffX > 1.0 || diffY > 1.0 || store.displayedImageSize == .zero {
                                                let isFirstSize = store.displayedImageSize == .zero
                                                store.displayedImageSize = newSize
                                                
                                                if isFirstSize {
                                                    if !store.isSpreadMode {
                                                        store.setupInitialSingleRect()
                                                    } else {
                                                        store.setupInitialSpreadRects()
                                                    }
                                                }
                                                
                                                // 表示サイズが変更された（ウィンドウリサイズ等）際に枠を範囲内に収めます
                                                store.clampRectsToImageSize()
                                            }
                                        }
                                    }
                            }
                        )
                        .overlay(alignment: .topLeading) {
                            ZStack(alignment: .topLeading) {
                                // 切り抜き枠の表示フラグをオパシティとヒットテストで制御します
                                Group {
                                    // 1つ目の切り抜き枠を描画します
                                    cropBoxView(rect: $store.cropRect, initialRect: $initialCropRect, label: store.isSpreadMode ? (store.isJapaneseStyle ? "2" : "1") : nil, isFirst: true)

                                    // 見開きモードが有効な場合、2つ目の切り抜き枠を描画します
                                    if store.isSpreadMode {
                                        cropBoxView(rect: $store.cropRect2, initialRect: $initialCropRect2, label: store.isJapaneseStyle ? "1" : "2", isFirst: false)
                                    }
                                }
                                .opacity(store.isShowingCropBox ? 1.0 : 0.0)
                                .allowsHitTesting(store.isShowingCropBox)

                                // 2D背景分析の結果（赤い囲い）をオーバーレイ表示します
                                if store.isHeatmapMode {
                                    if let maskImage = store.backgroundMaskImage {
                                        Image(nsImage: maskImage)
                                            .resizable()
                                            .frame(width: store.displayedImageSize.width, height: store.displayedImageSize.height)
                                            .allowsHitTesting(false)
                                    }
                                }

                                // 高さ合わせのアシスト線を描画します
                                if let _ = fullImage {
                                    // 枠の枠線と同じように、スケールにかかわらず一定の太さ（1.0ポイント）に見えるように調整します
                                    // ここでは、ZStackが画像と同じ座標系（左上原点、スケール適用前）にあるため、
                                    // 単純に画像上の座標 y を offset に指定すれば、後の .scaleEffect(currentScale) で正しく配置されます
                                    ForEach(snapLines, id: \.self) { y in
                                        Rectangle()
                                            .fill(Color.yellow)
                                            // 線の太さを 1.0 ポイントにするために、現在の合計スケールで割ります
                                            .frame(width: store.displayedImageSize.width, height: 1.0 / (scale * magnifyBy))
                                            .offset(y: y)
                                    }

                                    // 幅合わせ用のアシスト線を描画します
                                    ForEach(widthSnapLines, id: \.self) { line in
                                        Rectangle()
                                            .fill(Color.yellow)
                                            .frame(width: line.width, height: 1.0 / (scale * magnifyBy))
                                            .offset(x: line.x, y: line.y)
                                    }

                                    // 高さ合わせ用のアシスト線（垂直線）を描画します
                                    ForEach(heightSnapLines, id: \.self) { line in
                                        Rectangle()
                                            .fill(Color.yellow)
                                            .frame(width: 1.0 / (scale * magnifyBy), height: line.height)
                                            .offset(x: line.x, y: line.y)
                                    }
                                }
                            }
                        }
                // ビュー全体をスケール変換し、ドラッグによるオフセットを適用します
                .offset(imageOffset)
                .scaleEffect(scale * magnifyBy)
                // 拡大縮小（ピンチ）ジェスチャを設定します
                .gesture(
                    MagnificationGesture()
                        // ジェスチャ実行中に一時的なスケール値を更新します
                        .updating($magnifyBy) { value, state, transaction in
                            state = value.magnitude
                        }
                        // ジェスチャ終了時に最終的なスケール値を確定します
                        .onEnded { value in
                            scale *= value.magnitude
                            // スケール範囲を0.1から10.0に制限します
                            scale = max(0.1, min(scale, 10.0))
                        }
                 )
                // 左ドラッグによる画像移動ジェスチャを追加します
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // ドラッグ開始時のオフセットを保存します
                            if initialImageOffset == .zero {
                                initialImageOffset = imageOffset
                            }
                            
                            // 右ドラッグと同様の制限をかけます
                            let currentScale = scale * magnifyBy
                            
                            // 移動量を加算します（スケールで割って画像座標系での移動量にする）
                            let newX = initialImageOffset.width + (value.translation.width / currentScale)
                            let newY = initialImageOffset.height + (value.translation.height / currentScale)
                            
                            let limitX = max(1000, viewSize.width)
                            let limitY = max(1000, viewSize.height)
                            
                            // 切り抜き枠のドラッグ中でない場合のみ画像を移動します
                            if !isDraggingCropBox && abs(newX) < limitX && abs(newY) < limitY {
                                imageOffset = CGSize(width: newX, height: newY)
                            }
                            
                            // カーソルを「掴んでいる手」に変更します（移動可能な場合のみ）
                            if !isDraggingCropBox {
                                NSCursor.closedHand.set()
                            }
                        }
                        .onEnded { _ in
                            // ドラッグ終了時に初期オフセットをリセットします
                            initialImageOffset = .zero
                            isDraggingCropBox = false
                            // カーソルを通常の矢印に戻します
                            NSCursor.arrow.set()
                        }
                )
                // 周囲にパディングを付加します
                .padding()
            } else if !store.isScreenshotMode {
                // 画像が選択されておらず、かつスクショモードでない時のプレースホルダテキストです
                Text("Please select an image")
                    // テキストの色を二次的な色にします
                    .foregroundColor(.secondary)
            } else {
                Text("Screenshot Mode")
                    // テキストの色を二次的な色にします
                    .foregroundColor(.secondary)
            }
        }
        // 選択された画像が変わった時に画像を再読み込みし、位置と拡大率をリセットします
        .onChange(of: store.selectedID) { _, _ in
            loadFullImage()
            // 画像移動距離をリセットします
            imageOffset = .zero
            // 拡大率を1.0にリセットします
            scale = 1.0
        }
        // ビューが表示された時に画像を読み込みます
        .onAppear {
            loadFullImage()
            // マウスの右ボタン操作を監視するためのローカルモニターを登録します
            setupEventMonitor(geometry: geometry)
        }
        // PreferenceKeyを通じてビューサイズの変更を検知し、状態変数を更新します
        .onPreferenceChange(ViewSizeKey.self) { newSize in
            // 無限ループを防ぐため、値が異なる場合のみ更新を行います
            if viewSize != newSize {
                viewSize = newSize
            }
        }
        // ビューが非表示になる時にモニターを解除します
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            }
            // ジオメトリリーダーの全領域を埋めるように設定し、中央に配置します
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // マウスの右ドラッグイベントを監視・処理するメソッドです
    private func setupEventMonitor(geometry: GeometryProxy) {
        // 右マウスダウン、右マウスアップ、右マウスドラッグのイベントを監視対象にします
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .rightMouseDragged]) { event in
            // 他のウィンドウやビューでのイベントを無視するため、ウィンドウがアクティブか確認します
            guard NSApp.isActive, let window = event.window, window.isKeyWindow else {
                return event
            }

            // マウスの現在位置をウィンドウ座標系で取得します
            let mouseLocation = event.locationInWindow
            
            if event.type == .rightMouseDown {
                // スクリーン座標系での詳細ビューの範囲を取得します
                // NSEvent.locationInWindow は (0,0) が左下の座標系であることに注意
                let globalFrame = geometry.frame(in: .global)
                
                // マウス位置が詳細ビュー内にない場合は無視します
                // window.contentView が詳細ビューそのものではない可能性があるため、geometry を使用
                if !globalFrame.contains(mouseLocation) {
                    return event
                }
            }

            switch event.type {
            case .rightMouseDown:
                // ドラッグ移動フラグをリセットし、カーソルを「掴んでいる手」に変更します
                hasMoved = false
                NSCursor.closedHand.set()
                return event
            case .rightMouseUp:
                // カーソルを通常の矢印に戻します
                NSCursor.arrow.set()
                // ドラッグが行われた場合は、コンテキストメニューの表示を抑制するためにイベントを消費（nilを返す）します
                if hasMoved {
                    hasMoved = false
                    return nil
                }
                return event
            case .rightMouseDragged:
                // 右ドラッグ中に、マウスの移動量（deltaX, deltaY）をオフセットに加算します
                // SwiftUIのオフセットは下方向が正のため、deltaYをそのまま加算します
                let currentScale = scale * magnifyBy
                let newX = imageOffset.width + (event.deltaX / currentScale)
                let newY = imageOffset.height + (event.deltaY / currentScale)

                // 画像が画面外に完全に出ないように制限をかけます。
                // ビューのサイズから制限値を計算します。
                let limitX = max(1000, viewSize.width)
                let limitY = max(1000, viewSize.height)

                if abs(newX) < limitX && abs(newY) < limitY {
                    imageOffset = CGSize(width: newX, height: newY)
                    // 移動が発生したことを記録します
                    hasMoved = true
                }
                // ドラッグイベントを消費（nilを返す）して、他のビューが反応しないようにします
                return nil
            default:
                return event
            }
        }
    }


    // 四辺の方向を定義する列挙型です
    enum Edge {
        case top, bottom, leading, trailing
    }

    // 切り抜き枠本体を描画するビュービルダーです
    @ViewBuilder
    private func cropBoxView(rect: Binding<CGRect>, initialRect: Binding<CGRect>, label: String?, isFirst: Bool) -> some View {
        // 切り抜き枠内の要素を重ねるZStackです
        ZStack(alignment: .topLeading) {
            // 枠内（背景）のドラッグ移動・ホバー判定用の矩形です
            Rectangle()
                // ほとんど透明な黒色で塗りつぶし、タップ判定を有効にします
                .fill(Color.black.opacity(0.001))
                // ドラッグジェスチャを設定します
                .gesture(
                    // 最小距離0でグローバル座標系のドラッグを検知します
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        // ドラッグ位置が変化した時の処理です
                        .onChanged { value in
                            // 切り抜き枠のドラッグを開始したことを記録します
                            isDraggingCropBox = true
                            // ドラッグ開始時の矩形を保存します
                            if initialRect.wrappedValue == .zero { initialRect.wrappedValue = rect.wrappedValue }
                            // 現在の合計スケールを計算します
                            let currentScale = scale * magnifyBy
                            // ドラッグ量に応じて切り抜き枠の座標を更新します
                            var newX = initialRect.wrappedValue.origin.x + (value.translation.width / currentScale)
                            var newY = initialRect.wrappedValue.origin.y + (value.translation.height / currentScale)

                            // 見開きモードかつ移動中の高さ合わせアシスト
                            var lines: [CGFloat] = []
                            var vLines: [VLineGeometry] = [] // 垂直方向のアシスト線
                            if store.isSpreadMode {
                                let otherRect = isFirst ? store.cropRect2 : store.cropRect
                                // 吸着のしきい値（ポイント単位）を画像座標系に変換します
                                let threshold: CGFloat = 5.0 / currentScale

                                // 自分の上端と相手の上端
                                if abs(newY - otherRect.minY) < threshold {
                                    newY = otherRect.minY
                                    lines.append(newY)
                                }
                                // 自分の下端と相手の下端
                                if abs((newY + rect.wrappedValue.height) - otherRect.maxY) < threshold {
                                    newY = otherRect.maxY - rect.wrappedValue.height
                                    lines.append(otherRect.maxY)
                                }
                                // 自分の上端と相手の下端
                                if abs(newY - otherRect.maxY) < threshold {
                                    newY = otherRect.maxY
                                    lines.append(newY)
                                }
                                // 自分の下端と相手の上端
                                if abs((newY + rect.wrappedValue.height) - otherRect.minY) < threshold {
                                    newY = otherRect.minY - rect.wrappedValue.height
                                    lines.append(otherRect.minY)
                                }

                                // 左右の内側の境界線（スナップ対象）への吸着
                                if isFirst {
                                    // 左側ボックスの場合：自分の右端と相手の左端
                                    let myRight = newX + rect.wrappedValue.width
                                    if abs(myRight - otherRect.minX) < threshold {
                                        newX = otherRect.minX - rect.wrappedValue.width
                                        // 垂直線のマーカー（必要なら追加できますが、現在は水平線のみ）
                                    }
                                } else {
                                    // 右側ボックスの場合：自分の左端と相手の右端
                                    if abs(newX - otherRect.maxX) < threshold {
                                        newX = otherRect.maxX
                                    }
                                }
                            }

                            // 自動エリア設定の境界線（赤・青の境界）への吸着
                            if store.isHeatmapMode {
                                let pixelToPointScale = store.displayedImageSize.width / store.currentImagePixelSize.width
                                let threshold: CGFloat = 5.0 / currentScale
                                for pxX in store.detectedBoundaries {
                                    let pointX = CGFloat(pxX) * pixelToPointScale
                                    // 自分の左端が境界線に近い場合
                                    if abs(newX - pointX) < threshold {
                                        newX = pointX
                                        vLines.append(VLineGeometry(x: pointX, y: 0, height: store.displayedImageSize.height))
                                    }
                                    // 自分の右端が境界線に近い場合
                                    let myRight = newX + rect.wrappedValue.width
                                    if abs(myRight - pointX) < threshold {
                                        newX = pointX - rect.wrappedValue.width
                                        vLines.append(VLineGeometry(x: pointX, y: 0, height: store.displayedImageSize.height))
                                    }
                                }
                            }

                            // 画像の範囲内に収まるように座標を制限（クランプ）します
                            let maxX = store.displayedImageSize.width - rect.wrappedValue.width
                            let maxY = store.displayedImageSize.height - rect.wrappedValue.height

                            rect.wrappedValue.origin.x = max(0, min(newX, maxX))
                            rect.wrappedValue.origin.y = max(0, min(newY, maxY))
                            self.snapLines = lines
                            self.heightSnapLines = vLines

                            // カーソルを「掴んでいる手」に変更します
                            NSCursor.closedHand.set()
                        }
                        // ドラッグが終了した時の処理です
                        .onEnded { _ in
                            // ドラッグ終了を記録します
                            isDraggingCropBox = false
                            // 開始時の矩形をリセットします
                            initialRect.wrappedValue = .zero
                            // アシスト線を消去します
                            self.snapLines = []
                            self.heightSnapLines = []
                            // カーソルを通常の矢印に戻します
                            NSCursor.arrow.set()
                        }
                )
                // マウスホバー時の処理です
                .onHover { inside in
                    // 枠内に入った時にカーソルを矢印にします
                    if inside { NSCursor.arrow.set() }
                }

            // メインの枠線を表示します
            let currentScale = scale * magnifyBy
            // スケールに応じた線幅を計算します
            let strokeWidth = 1.0 / currentScale

            // 枠線を描画する矩形です
            Rectangle()
                // 点線のスタイルを設定して描画します
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, dash: [4, 4], dashPhase: dashPhase))
                // 線の色を白にします
                .foregroundColor(.white)
                // 白い線の裏に黒い点線を重ねて見やすくします
                .background(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: strokeWidth, dash: [4, 4], dashPhase: dashPhase + 4))
                        .foregroundColor(.black)
                )

            // ページ番号ラベルを表示します（指定がある場合）
            if let labelText = label {
                Text(labelText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .offset(x: 4, y: 4)
            }

            // 上辺のリサイズハンドルを配置します
            edgeHandle(at: .top, rect: rect, initialRect: initialRect, isFirst: isFirst)
            // 下辺のリサイズハンドルを配置します
            edgeHandle(at: .bottom, rect: rect, initialRect: initialRect, isFirst: isFirst)
            // 左辺のリサイズハンドルを配置します
            edgeHandle(at: .leading, rect: rect, initialRect: initialRect, isFirst: isFirst)
            // 右辺のリサイズハンドルを配置します
            edgeHandle(at: .trailing, rect: rect, initialRect: initialRect, isFirst: isFirst)
        }
        // ストアに保存されたサイズを枠に適用します
        .frame(width: rect.wrappedValue.width, height: rect.wrappedValue.height)
        // ストアに保存された座標を枠に適用します
        .offset(x: rect.wrappedValue.origin.x, y: rect.wrappedValue.origin.y)
        // ビューが表示された時の処理です
        .onAppear {
            // 点線を永遠に動かすアニメーションを開始します
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                dashPhase -= 8
            }
        }
    }

    // 各辺のリサイズハンドルを生成するビュービルダーです
    @ViewBuilder
    private func edgeHandle(at edge: Edge, rect: Binding<CGRect>, initialRect: Binding<CGRect>, isFirst: Bool = true) -> some View {
        // ハンドルの当たり判定サイズを定義します
        let handleSize: CGFloat = 10
        
        // 当たり判定用の矩形です
        Rectangle()
            // 透明だがタップ可能な色を設定します
            .fill(Color.black.opacity(0.001))
            // 辺の方向に応じてサイズを調整します
            .frame(
                width: (edge == .leading || edge == .trailing) ? handleSize : nil,
                height: (edge == .top || edge == .bottom) ? handleSize : nil
            )
            // ドラッグジェスチャを設定します
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    // ドラッグ中の処理です
                    .onChanged { value in
                        // 切り抜き枠の操作中であることを記録します
                        isDraggingCropBox = true
                        // ドラッグ開始時の矩形を保持します
                        if initialRect.wrappedValue == .zero { initialRect.wrappedValue = rect.wrappedValue }
                        
                        // 現在の合計スケールとドラッグの変位を計算します
                        let currentScale = scale * magnifyBy
                        let deltaX = value.translation.width / currentScale
                        let deltaY = value.translation.height / currentScale
                        
                        // 新しい矩形を計算します
                        var newRect = initialRect.wrappedValue
                        var lines: [CGFloat] = []
                        var vLines: [VLineGeometry] = [] // 垂直方向のアシスト線
                        switch edge {
                        case .top:
                            // 上辺を移動させ、高さを調整します
                            var newY = initialRect.wrappedValue.origin.y + deltaY
                            // 最小高さを40ポイントに制限します
                            let maxY = initialRect.wrappedValue.maxY - 40
                            var newHeight = initialRect.wrappedValue.maxY - newY // 新しい高さを計算するベース
                            
                            var hLines: [VLineGeometry] = [] // 高さ合わせの線を保持する一時変数

                            // 見開きモードかつリサイズ中の高さ合わせアシスト
                            if store.isSpreadMode {
                                let otherRect = isFirst ? store.cropRect2 : store.cropRect
                                let threshold: CGFloat = 5.0 / currentScale
                                // 自分の上端と相手の上端を比較します
                                if abs(newY - otherRect.minY) < threshold {
                                    newY = otherRect.minY
                                    newHeight = initialRect.wrappedValue.maxY - newY
                                    lines.append(newY)
                                }
                                
                                // 高さの一致判定
                                if abs(newHeight - otherRect.height) < threshold {
                                    // 高さを他方に合わせ、それに伴うY座標を逆算します
                                    newHeight = otherRect.height
                                    newY = initialRect.wrappedValue.maxY - newHeight
                                    
                                    // 上下それぞれのボックスの垂直中心を通る黄色の線を設定します
                                    let myMidX = initialRect.wrappedValue.origin.x + initialRect.wrappedValue.size.width / 2
                                    hLines.append(VLineGeometry(x: myMidX, y: newY, height: newHeight))
                                    hLines.append(VLineGeometry(x: otherRect.midX, y: otherRect.minY, height: otherRect.height))
                                }
                            }

                            // 画像の上端（0）と最小サイズ（10）を考慮して制限します
                            newY = max(0, min(newY, maxY))
                            newRect.origin.y = newY
                            newRect.size.height = initialRect.wrappedValue.maxY - newRect.origin.y
                            // 吸着線を更新
                            self.heightSnapLines = hLines
                            // 上下リサイズ用カーソルを設定します
                            NSCursor.resizeUpDown.set()
                        case .bottom:
                            // 高さを変更します（最小40ピクセル）
                            var newHeight = initialRect.wrappedValue.size.height + deltaY
                            var hLines: [VLineGeometry] = [] // 高さ合わせの線を保持する一時変数

                            // 見開きモードかつリサイズ中の高さ合わせアシスト
                            if store.isSpreadMode {
                                let otherRect = isFirst ? store.cropRect2 : store.cropRect
                                let threshold: CGFloat = 5.0 / currentScale
                                let newBottomY = initialRect.wrappedValue.origin.y + newHeight
                                // 自分の下端と相手の下端を比較します
                                if abs(newBottomY - otherRect.maxY) < threshold {
                                    newHeight = otherRect.maxY - initialRect.wrappedValue.origin.y
                                    lines.append(otherRect.maxY)
                                }
                                
                                // 高さの一致判定
                                if abs(newHeight - otherRect.height) < threshold {
                                    newHeight = otherRect.height
                                    
                                    // 上下それぞれのボックスの垂直中心を通る黄色の線を設定します
                                    let myMidX = initialRect.wrappedValue.origin.x + initialRect.wrappedValue.size.width / 2
                                    hLines.append(VLineGeometry(x: myMidX, y: initialRect.wrappedValue.origin.y, height: newHeight))
                                    hLines.append(VLineGeometry(x: otherRect.midX, y: otherRect.minY, height: otherRect.height))
                                }
                            }

                            // 画像の下端と最小サイズ（40ポイント）を考慮して制限します
                            let maxHeight = store.displayedImageSize.height - initialRect.wrappedValue.origin.y
                            newRect.size.height = max(40, min(newHeight, maxHeight))
                            // 吸着線を更新
                            self.heightSnapLines = hLines
                            // 上下リサイズ用カーソルを設定します
                            NSCursor.resizeUpDown.set()
                        case .leading:
                            // 左辺を移動させ、幅を調整します
                            var newX = initialRect.wrappedValue.origin.x + deltaX
                            // 最小幅を40ポイントに制限します
                            let maxX = initialRect.wrappedValue.maxX - 40
                            var newWidth = initialRect.wrappedValue.maxX - newX // 新しい幅を計算するベース
                            
                            var wLines: [LineGeometry] = [] // 幅合わせの線を保持する一時変数

                            // 見開きモードかつ、右側エリアの左辺（内側）のリサイズ中の吸着など
                            if store.isSpreadMode {
                                if !isFirst {
                                    let otherRect = store.cropRect // 他方は常に左側
                                    let threshold: CGFloat = 5.0 / currentScale
                                    if abs(newX - otherRect.maxX) < threshold {
                                        newX = otherRect.maxX
                                        newWidth = initialRect.wrappedValue.maxX - newX
                                    }
                                }
                                
                                // 幅の一致判定
                                let otherRect = isFirst ? store.cropRect2 : store.cropRect
                                let threshold: CGFloat = 5.0 / currentScale
                                if abs(newWidth - otherRect.width) < threshold {
                                    // 幅を他方に合わせ、それに伴うX座標を逆算します
                                    newWidth = otherRect.width
                                    newX = initialRect.wrappedValue.maxX - newWidth
                                    
                                    // 左右それぞれのボックスの水平中心を通る黄色の線を設定します
                                    let myMidY = initialRect.wrappedValue.origin.y + initialRect.wrappedValue.size.height / 2
                                    wLines.append(LineGeometry(x: newX, y: myMidY, width: newWidth))
                                    wLines.append(LineGeometry(x: otherRect.minX, y: otherRect.midY, width: otherRect.width))
                                }
                            }

                            // 自動エリア設定の境界線（赤・青の境界）への吸着
                            if store.isHeatmapMode {
                                let pixelToPointScale = store.displayedImageSize.width / store.currentImagePixelSize.width
                                let threshold: CGFloat = 5.0 / currentScale
                                for pxX in store.detectedBoundaries {
                                    let pointX = CGFloat(pxX) * pixelToPointScale
                                    if abs(newX - pointX) < threshold {
                                        newX = pointX
                                        newWidth = initialRect.wrappedValue.maxX - newX
                                        vLines.append(VLineGeometry(x: pointX, y: 0, height: store.displayedImageSize.height))
                                    }
                                }
                            }

                            // 画像の左端（0）と最小サイズ（10）を考慮して制限します
                            newX = max(0, min(newX, maxX))
                            newRect.origin.x = newX
                            newRect.size.width = initialRect.wrappedValue.maxX - newRect.origin.x
                            // 吸着線を更新
                            self.widthSnapLines = wLines
                            // 左右リサイズ用カーソルを設定します
                            NSCursor.resizeLeftRight.set()
                        case .trailing:
                            // 幅を変更します（最小40ピクセル）
                            var newWidth = initialRect.wrappedValue.size.width + deltaX
                            var wLines: [LineGeometry] = [] // 幅合わせの線を保持する一時変数

                            // 見開きモードかつ、リサイズ中の吸着など
                            if store.isSpreadMode {
                                if isFirst {
                                    let otherRect = store.cropRect2 // 他方は常に右側
                                    let threshold: CGFloat = 5.0 / currentScale
                                    let newRightX = initialRect.wrappedValue.origin.x + newWidth
                                    if abs(newRightX - otherRect.minX) < threshold {
                                        newWidth = otherRect.minX - initialRect.wrappedValue.origin.x
                                    }
                                }
                                
                                // 幅の一致判定
                                let otherRect = isFirst ? store.cropRect2 : store.cropRect
                                let threshold: CGFloat = 5.0 / currentScale
                                if abs(newWidth - otherRect.width) < threshold {
                                    newWidth = otherRect.width
                                    
                                    // 左右それぞれのボックスの水平中心を通る黄色の線を設定します
                                    let myMidY = initialRect.wrappedValue.origin.y + initialRect.wrappedValue.size.height / 2
                                    wLines.append(LineGeometry(x: initialRect.wrappedValue.origin.x, y: myMidY, width: newWidth))
                                    wLines.append(LineGeometry(x: otherRect.minX, y: otherRect.midY, width: otherRect.width))
                                }
                            }

                            // 自動エリア設定の境界線（赤・青の境界）への吸着
                            if store.isHeatmapMode {
                                let pixelToPointScale = store.displayedImageSize.width / store.currentImagePixelSize.width
                                let threshold: CGFloat = 5.0 / currentScale
                                let currentRightX = initialRect.wrappedValue.origin.x + newWidth
                                for pxX in store.detectedBoundaries {
                                    let pointX = CGFloat(pxX) * pixelToPointScale
                                    if abs(currentRightX - pointX) < threshold {
                                        newWidth = pointX - initialRect.wrappedValue.origin.x
                                        vLines.append(VLineGeometry(x: pointX, y: 0, height: store.displayedImageSize.height))
                                    }
                                }
                            }

                            // 画像の右端と最小サイズ（40ポイント）を考慮して制限します
                            let maxWidth = store.displayedImageSize.width - initialRect.wrappedValue.origin.x
                            newRect.size.width = max(40, min(newWidth, maxWidth))
                            // 吸着線を更新
                            self.widthSnapLines = wLines
                            // 左右リサイズ用カーソルを設定します
                            NSCursor.resizeLeftRight.set()
                        }
                        // 計算した新しい矩形をストアに反映します
                        rect.wrappedValue = newRect
                        // アシスト線を表示します
                        self.snapLines = lines
                        self.heightSnapLines = vLines
                    }
                     // ドラッグ終了時の処理です
                    .onEnded { _ in
                        // 操作終了を記録します
                        isDraggingCropBox = false
                        // 開始位置をリセットします
                        initialRect.wrappedValue = .zero
                        // アシスト線を消去します
                        self.snapLines = []
                        self.widthSnapLines = []
                        self.heightSnapLines = []
                        // カーソルを通常に戻します
                        NSCursor.arrow.set()
                    }
            )
            // マウスホバー時の処理です
            .onHover { inside in
                // ハンドル上にマウスがある場合、適切なリサイズカーソルを表示します
                if inside {
                    switch edge {
                    case .top, .bottom:
                        NSCursor.resizeUpDown.set()
                    case .leading, .trailing:
                        NSCursor.resizeLeftRight.set()
                    }
                } else {
                    // 外れたら通常の矢印に戻します
                    NSCursor.arrow.set()
                }
            }
            // 枠の端にハンドルを配置します
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: {
                switch edge {
                case .top: return .top
                case .bottom: return .bottom
                case .leading: return .leading
                case .trailing: return .trailing
                }
            }())
    }

    // フルサイズ画像を読み込むメソッドです
    private func loadFullImage() {
        // 選択された画像のURLを取得します。なければ何もしません
        guard let url = selectedItem?.url else { return }

        // 優先度の高いバックグラウンドスレッドで画像を読み込みます
        DispatchQueue.global(qos: .userInitiated).async {
            // URLから画像データを読み込みます
            let image = NSImage(contentsOf: url)

            // メインスレッドで状態を更新します
            DispatchQueue.main.async {
                // 読み込まれた画像をセットします
                self.fullImage = image

                // 読み込まれた画像の実ピクセルサイズを取得してストアに保存します
                if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    self.store.currentImagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
                }
            }
        }
    }
}

// ビューのサイズを子ビューから親ビューに伝えるためのキーです
struct ViewSizeKey: PreferenceKey {
    // デフォルト値としてゼロのサイズを指定します
    static var defaultValue: CGSize = .zero
    // 複数の値を統合する際の処理を定義します。ここでは新しい値を採用します
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
