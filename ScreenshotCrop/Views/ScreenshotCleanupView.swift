// SwiftUIフレームワークをインポートします
import SwiftUI

// 不要なスクリーンショットを選択して削除するためのビューです
struct ScreenshotCleanupView: View {
    // 環境オブジェクトからImageStoreを取得します
    @EnvironmentObject var store: ImageStore
    // ビューを閉じるためのアクションです
    @Environment(\.dismiss) var dismiss

    // 選択状態を保持するための構造体です
    struct SelectableItem: Identifiable {
        // 一意識別子として画像アイテムのIDを使用します
        var id: UUID { item.id }
        // 画像アイテム本体です
        let item: ImageItem
        // 選択されているかどうかのフラグです
        var isSelected: Bool = false
    }

    // 表示するアイテムのリストです
    @State private var selectableItems: [SelectableItem] = []

    // ビューの階層構造を定義します
    var body: some View {
        // 垂直方向に要素を並べます
        VStack(spacing: 0) {
            // ヘッダーセクション
            HStack {
                // タイトルを表示します
                Text("Delete unnecessary screenshots")
                    .font(.headline)
                Spacer()
                // 全選択ボタン
                Button("Select All") {
                    for i in 0..<selectableItems.count {
                        selectableItems[i].isSelected = true
                    }
                }
                .buttonStyle(.borderless)

                // 全解除ボタン
                Button("Deselect All") {
                    for i in 0..<selectableItems.count {
                        selectableItems[i].isSelected = false
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding()
            // 背景色をウィンドウの標準色に設定します
            .background(Color(NSColor.windowBackgroundColor))

            // 仕切り線を表示します
            Divider()

            // 画像リストのスクロールエリア
            ScrollView {
                // グリッドレイアウトを定義します（3列）
                let columns = [
                    GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    // 各アイテムに対して表示を生成します
                    ForEach($selectableItems) { $selectable in
                        VStack(spacing: 8) {
                            // サムネイル表示エリア
                            ZStack(alignment: .topTrailing) {
                                // 画像のサムネイル
                                CleanupThumbnailView(url: selectable.item.url)
                                    // タップで選択状態を反転させます
                                    .onTapGesture {
                                        selectable.isSelected.toggle()
                                    }

                                // 選択チェックボックス
                                Toggle("", isOn: $selectable.isSelected)
                                    .toggleStyle(.checkbox)
                                    .padding(4)
                                    .background(Color.white.opacity(0.8))
                                    .cornerRadius(4)
                                    .padding(4)
                            }

                            // ファイル名の表示
                            Text(selectable.item.url.lastPathComponent)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding()
            }

            // 仕切り線を表示します
            Divider()

            // フッターセクション
            HStack {
                // キャンセルボタンです
                Button("Cancel") {
                    dismiss()
                }
                // エスケープキーでキャンセルできるようにします
                .keyboardShortcut(.cancelAction)

                Spacer()

                // 削除ボタンの枚数表示
                let selectedCount = selectableItems.filter { $0.isSelected }.count
                if selectedCount > 0 {
                    Text("\(selectedCount) items selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 削除実行ボタンです
                Button(role: .destructive) {
                    // 削除対象を抽出します
                    let itemsToDelete = selectableItems.filter { $0.isSelected }.map { $0.item }
                    // ImageStoreの削除処理を呼び出します
                    store.deleteImages(itemsToDelete)
                    // ウィンドウを閉じます
                    dismiss()
                } label: {
                    Text("Delete")
                }
                // 1つも選択されていない場合は無効化します
                .disabled(selectedCount == 0)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
        }
        // ウィンドウのサイズを設定します
        .frame(width: 700, height: 600)
        // 表示された時の初期化処理です
        .onAppear {
            setupItems()
        }
    }

    // ストアのアイテムから選択用リストを構築します
    private func setupItems() {
        self.selectableItems = store.items.map { SelectableItem(item: $0, isSelected: false) }
    }
}

// 削除確認用のサムネイルビューです
struct CleanupThumbnailView: View {
    // 表示する画像のURLです
    let url: URL
    // 読み込まれたサムネイル画像を保持します
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image = image {
                // 画像を表示します
                Image(nsImage: image)
                    .resizable()
                    // アスペクト比を維持してフィットさせます
                    .aspectRatio(contentMode: .fit)
            } else {
                // 読み込み中の表示です
                ProgressView()
                    .controlSize(.small)
            }
        }
        // 固定サイズを設定します
        .frame(width: 150, height: 150)
        // 背景色を設定します
        .background(Color.black.opacity(0.05))
        // 枠線を描画します
        .border(Color.gray.opacity(0.2))
        // 表示された時にサムネイルを読み込みます
        .onAppear {
            loadThumbnail()
        }
    }

    // サムネイルを非同期で読み込むメソッドです
    private func loadThumbnail() {
        // 優先度の高いバックグラウンドスレッドで実行します
        DispatchQueue.global(qos: .userInitiated).async {
            // キャッシュからサムネイルを取得します
            let thumb = ThumbnailCache.shared.thumbnail(for: url, size: 300)
            DispatchQueue.main.async {
                // メインスレッドで画像を更新します
                self.image = thumb
            }
        }
    }
}
