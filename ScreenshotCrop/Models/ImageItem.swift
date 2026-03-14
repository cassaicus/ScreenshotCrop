// 基本的なデータ型やコレクションを扱うFoundationフレームワークをインポートします
import Foundation

// 画像アイテムを表す、一意に識別可能かつハッシュ可能な構造体です
struct ImageItem: Identifiable, Hashable {
    // 各アイテムを一意に識別するためのUUIDです
    let id = UUID()
    // 画像ファイルのURLを保持します
    let url: URL
}
