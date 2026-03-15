// macOSのAppKitフレームワークをインポートします
import AppKit
// 画像のメタデータや生成を扱うImageIOフレームワークをインポートします
import ImageIO

// サムネイルをキャッシュするためのクラスです
final class ThumbnailCache {
    // 共有シングルトンインスタンスを提供します
    static let shared = ThumbnailCache()
    // URLをキー、NSImageを値とするキャッシュオブジェクトです
    private let cache = NSCache<NSURL, NSImage>()

    // 指定されたURLとサイズに対してサムネイルを取得または生成します
    func thumbnail(for url: URL, size: CGFloat) -> NSImage? {
        // キャッシュに既に存在する場合は、それを返します
        if let cached = cache.object(forKey: url as NSURL) {
            // キャッシュされた画像を返します
            return cached
        }

        // 指定されたURLから画像ソースを作成します。失敗した場合はnilを返します
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // サムネイル生成のためのオプションを設定します
        let options: [CFString: Any] = [
            // 元の画像から必ずサムネイルを作成するように指定します
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // サムネイルの最大ピクセルサイズを指定します
            kCGImageSourceThumbnailMaxPixelSize: size,
            // 向き情報（EXIF）に基づいてサムネイルを回転させるように指定します
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        // 指定されたインデックス（0番目）のサムネイルを作成します。失敗した場合はnilを返します
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // 作成に失敗したため、nilを返します
            return nil
        }

        // CGImageからNSImageを作成します。サイズは.zeroを指定して元のサイズを維持します
        let image = NSImage(cgImage: cgImage, size: .zero)
        // 生成されたサムネイルをキャッシュに保存します
        cache.setObject(image, forKey: url as NSURL)
        // 生成されたサムネイル画像を返します
        return image
    }
    // 指定されたURLのキャッシュを削除します
    func removeThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    // すべてのキャッシュをクリアします
    func clear() {
        cache.removeAllObjects()
    }
}
