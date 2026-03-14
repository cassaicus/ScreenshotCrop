// SwiftUIフレームワークをインポートします
import SwiftUI

// アプリのメインレイアウトを定義するContentViewです
struct ContentView: View {

    // 画像データを管理する状態オブジェクトを作成します
    @StateObject private var store = ImageStore()
    // 画像の拡大縮小率を管理する状態変数です（初期値1.0）
    @State private var imageScale: CGFloat = 1.0

    // ビューの階層構造を定義します
    var body: some View {
        // ナビゲーション用の分割ビューを作成します
        NavigationSplitView {

            // 左側のサイドバービューを配置します
            SidebarView()
                // ImageStoreを環境オブジェクトとして提供します
                .environmentObject(store)
                // ツールバーをサイドバーに追加します
                .toolbar {
                    // フォルダを開くためのボタンを配置します
                    Button {
                        // ImageStoreのpickFolderメソッドを呼び出し、フォルダ選択パネルを表示します
                        store.pickFolder()
                    } label: {
                        // フォルダのアイコンを表示します
                        Image(systemName: "folder")
                    }
                    // ボタンのヘルプテキスト（ツールチップ）を設定します
                    .help("Open Folder")
                }

        } detail: {
            // 右側の詳細表示エリアを水平方向に配置します（スペース0）
            HStack(spacing: 0) {
                // 画像を表示・操作する詳細ビューです。拡大率をバインディングで渡します
                DetailView(scale: $imageScale)
                    // ImageStoreを環境オブジェクトとして提供します
                    .environmentObject(store)
                    // ビューの枠いっぱいに広げます
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 枠からはみ出した部分を切り取ります
                    .clipped()
                    // ツールバーを詳細ビューに追加します
                    .toolbar {
                        // ツールバーの中央にスライダーを配置します
                        ToolbarItem(placement: .principal) {
                            // 画像の拡大縮小を操作するスライダーを作成します（範囲 0.1〜10.0）
                            HStack(spacing: 8) {
                                Image(systemName: "minus")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)

                                Slider(value: $imageScale, in: 0.1...10.0) {
                                    // スライダーのラベル（虫眼鏡アイコン）を表示します
                                    Image(systemName: "magnifyingglass")
                                }
                                // スライダーの幅を150ポイントに設定します
                                .frame(width: 150)

                                Image(systemName: "plus")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 12)
                            }
                            // スライダーのヘルプテキストを設定します
                            .help("Scale Image")
                        }
                    }
                
                // サイドパネルとの仕切り線を表示します
                Divider()
                
                // 右側のツール操作パネルビューです
                ToolPaneView()
                    // ImageStoreを環境オブジェクトとして提供します
                    .environmentObject(store)
                    // 幅を250ポイントに固定します
                    .frame(width: 250)
            }
        }
        // ウィンドウが閉じられた（ビューが破棄された）際の処理を定義します
        .onDisappear {
            // ウィンドウが閉じられたらスクリーンショットモードを強制的にオフにします
            // これにより、フローティングパネルも自動的に非表示になります
            store.updateScreenshotMode(false)
        }
    }
}
