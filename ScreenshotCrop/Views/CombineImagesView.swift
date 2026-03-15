// SwiftUIフレームワークをインポートします
import SwiftUI

// 画像を結合するためのビューです
struct CombineImagesView: View {
    // 環境オブジェクトからImageStoreを取得します
    @EnvironmentObject var store: ImageStore
    // ビューを閉じるためのアクションです
    @Environment(\.dismiss) var dismiss

    // 表示する画像ペアのリストです
    @State private var pairs: [ImageStore.ImagePair] = []
    // 日本式（右開き）かどうかの状態変数です
    @State private var isJapaneseStyle: Bool = false
    // 結合後に元画像を削除するかどうかの状態変数です
    @State private var shouldDeleteOriginals: Bool = false

    // ビューの階層構造を定義します
    var body: some View {
        // 垂直方向に要素を並べます
        VStack(spacing: 0) {
            // ヘッダーセクション
            VStack(spacing: 8) {
                HStack {
                    // タイトルを表示します
                    Text("Combine Images")
                        .font(.headline)
                    Spacer()
                    // 日本式（右開き）の切り替えトグルです
                    Toggle("Japanese Style (Right-to-Left)", isOn: $isJapaneseStyle)
                        .toggleStyle(.checkbox)
                }
                HStack {
                    Spacer()
                    // 結合後に元画像を削除するトグルです
                    Toggle("Delete original images after combining", isOn: $shouldDeleteOriginals)
                        .toggleStyle(.checkbox)
                }
            }
            .padding()
            // 背景色をウィンドウの標準色に設定します
            .background(Color(NSColor.windowBackgroundColor))

            // 仕切り線を表示します
            Divider()

            // 画像リストのスクロールエリア
            ScrollView {
                // 遅延読み込みを行う垂直スタックです
                LazyVStack(spacing: 16) {
                    // 各ペアに対して表示を生成します
                    ForEach($pairs) { $pair in
                        HStack(spacing: 20) {
                            // 結合対象にするかどうかのチェックボックスです
                            Toggle("", isOn: $pair.isSelected)
                                .toggleStyle(.checkbox)
                                // 2枚目の画像がない（奇数枚の最後）場合は無効化します
                                .disabled(pair.second == nil)

                            // 画像ペアのサムネイル表示エリア
                            HStack(spacing: 4) {
                                // 日本式の場合は2枚目を左に表示します
                                if isJapaneseStyle {
                                    CombineThumbnailView(url: pair.second?.url)
                                    CombineThumbnailView(url: pair.first.url)
                                } else {
                                    // 通常は1枚目を左に表示します
                                    CombineThumbnailView(url: pair.first.url)
                                    CombineThumbnailView(url: pair.second?.url)
                                }
                            }

                            // ファイル名の表示セクション
                            VStack(alignment: .leading) {
                                // 1枚目のファイル名を表示します
                                Text(pair.first.url.lastPathComponent)
                                // 2枚目があればファイル名を、なければ「なし」を表示します
                                if let second = pair.second {
                                    Text(second.url.lastPathComponent)
                                } else {
                                    Text("None")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption)
                            .frame(width: 200, alignment: .leading)

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
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

                // 結合実行ボタンです
                Button("Combine") {
                    // 非同期で結合処理を実行します
                    Task {
                        store.shouldDeleteOriginalsAfterCombine = shouldDeleteOriginals
                        await store.combineImages(pairs: pairs, isJapaneseStyle: isJapaneseStyle)
                        // 完了後にビューを閉じます
                        dismiss()
                    }
                }
                // 目立つスタイルを設定します
                .buttonStyle(.borderedProminent)
                // 1つも選択されていない場合は無効化します
                .disabled(!pairs.contains { $0.isSelected })
            }
            .padding()
        }
        // ウィンドウのサイズを設定します
        .frame(width: 600, height: 600)
        // 表示された時の初期化処理です
        .onAppear {
            setupPairs()
            // 初期状態をストアから取得します
            isJapaneseStyle = store.isJapaneseStyle
            shouldDeleteOriginals = store.shouldDeleteOriginalsAfterCombine
        }
    }

    // 読み込んだ画像からペアを構築します
    private func setupPairs() {
        // 切り抜き済みフォルダから画像を取得します
        let items = store.loadCroppedImages()
        var newPairs: [ImageStore.ImagePair] = []

        // 2枚ずつペアにしてリストに追加します
        for i in stride(from: 0, to: items.count, by: 2) {
            let first = items[i]
            let second = (i + 1 < items.count) ? items[i + 1] : nil
            // 最初は全てチェックをOFFにします
            newPairs.append(ImageStore.ImagePair(first: first, second: second, isSelected: false))
        }

        self.pairs = newPairs
    }

}

// 結合プレビュー用のサムネイルビューです
struct CombineThumbnailView: View {
    // 表示する画像のURLです
    let url: URL?
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
                // 画像がない場合や読み込み中の表示です
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        Text(url == nil ? "None" : "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    )
            }
        }
        // 固定サイズを設定します
        .frame(width: 120, height: 165)
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
        guard let url = url else { return }
        // 優先度の高いバックグラウンドスレッドで実行します
        DispatchQueue.global(qos: .userInitiated).async {
            // キャッシュからサムネイルを取得します
            let thumb = ThumbnailCache.shared.thumbnail(for: url, size: 200)
            DispatchQueue.main.async {
                // メインスレッドで画像を更新します
                self.image = thumb
            }
        }
    }
}
