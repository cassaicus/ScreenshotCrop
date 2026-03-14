// SwiftUIフレームワークをインポートします
import SwiftUI

// 画像のサムネイル一覧を表示するサイドバービューです
struct SidebarView: View {

    // 環境オブジェクトからImageStoreを取得します
    @EnvironmentObject var store: ImageStore

    // ビューの階層構造を定義します
    var body: some View {
        // スクロール位置をプログラムで制御するためのリーダーです
        ScrollViewReader { proxy in
            // 垂直方向にスクロール可能なビューを作成します
            ScrollView {
                // 遅延読み込みを行う垂直スタックを配置します（スペース12）
                LazyVStack(spacing: 12) {
                    // ストア内の全画像アイテムに対してループを回します
                    ForEach(store.items) { item in
                        // サムネイル行を表示します。現在選択されているかどうかも渡します
                        ThumbnailRow(item: item,
                                     isSelected: store.selectedID == item.id)
                        // スクロール時に識別するためのIDを設定します
                        .id(item.id)
                        // タップ時のアクションを設定します
                        .onTapGesture {
                            // 選択された画像のIDをストアに保存します
                            store.selectedID = item.id
                            // アニメーション付きでスクロールを実行します
                            withAnimation {
                                // 選択された画像が画面の中央に来るようにスクロールします
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                }
                // スタックの周囲にパディングを設定します
                .padding(12)
            }
        }
    }
}

// サムネイル画像の1行分の表示を定義する構造体です
struct ThumbnailRow: View {

    // 表示する画像アイテムです
    let item: ImageItem
    // 現在選択されているかどうかを示します
    let isSelected: Bool

    // 生成されたサムネイル画像を保持する状態変数です
    @State private var thumbnail: NSImage?

    // ビューの階層構造を定義します
    var body: some View {
        // 中央揃えの垂直スタックを配置します（スペース6）
        VStack(alignment: .center, spacing: 6) {
            // 背景や画像を重ねるためのZStackです
            ZStack {
                // サムネイル画像が存在する場合に表示します
                if let thumbnail {
                    // サムネイル画像を表示します
                    Image(nsImage: thumbnail)
                        // サイズ変更を可能にします
                        .resizable()
                        // アスペクト比を維持してフィットさせます
                        .aspectRatio(contentMode: .fit)
                        // 角を丸くします
                        .cornerRadius(4)
                } else {
                    // サムネイル生成中などに表示するグレーの矩形です
                    Rectangle()
                        // 15%の不透明度のグレーで塗りつぶします
                        .fill(Color.gray.opacity(0.15))
                        // 3:2のアスペクト比を設定します
                        .aspectRatio(3/2, contentMode: .fit)
                        // 角を丸くします
                        .cornerRadius(4)
                }
            }
            // 横幅を最大限に広げます
            .frame(maxWidth: .infinity)
            
            // ファイル名を表示するテキストビューです
            Text(item.url.lastPathComponent)
                // フォントサイズを最小に設定します
                .font(.caption2)
                // 最大2行まで表示します
                .lineLimit(2)
                // テキストを中央揃えにします
                .multilineTextAlignment(.center)
                // 選択状態に応じてテキストの色を変更します
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        // 内側にパディングを設定します
        .padding(8)
        // ビューが表示された時の処理です
        .onAppear {
            // サムネイルを読み込みます
            loadThumbnail()
        }
        // 背景の設定です
        .background(
            // 角丸の矩形を背景に設定します
            RoundedRectangle(cornerRadius: 8)
                // 選択されている場合はアクセントカラーを、そうでなければ透明を設定します
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        // 枠線の設定です
        .overlay(
            // 角丸の矩形の枠線を表示します
            RoundedRectangle(cornerRadius: 8)
                // 選択されている場合はアクセントカラーを、そうでなければ透明を設定します。線幅は2です
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    // 非同期でサムネイル画像を読み込むメソッドです
    private func loadThumbnail() {
        // すでにサムネイルが読み込まれている場合は何もしません
        if thumbnail != nil { return }

        // 優先度の高いバックグラウンドスレッドで実行します
        DispatchQueue.global(qos: .userInitiated).async {
            // キャッシュからサムネイルを取得します（サイズ400ピクセル）
            let image = ThumbnailCache.shared.thumbnail(for: item.url, size: 400)

            // メインスレッドで状態を更新します
            DispatchQueue.main.async {
                // 読み込まれた画像をセットします
                self.thumbnail = image
            }
        }
    }
}
