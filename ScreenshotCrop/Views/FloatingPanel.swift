import AppKit
import SwiftUI

// 1. フローティングボタンのデザイン
struct FloatingButtonView: View {
    // ImageStoreを環境オブジェクトとして取得します
    @EnvironmentObject var store: ImageStore
    // 強調表示（赤い円）の表示状態を管理します
    @State private var showHighlight = false

    var body: some View {
        Button(action: {
            // スクリーンショット撮影のメソッドを呼び出します
            store.triggerFloatingScreenshot()
        }) {
            ZStack {
                // 背景円
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 50, height: 50)

                // カメラアイコン
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)

                // 表示時にユーザーの注意を引くための強調用赤い円
                if showHighlight {
                    Circle()
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: 54, height: 54)
                        // ふわっと表示・消去するためのアニメーション設定
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(5)
        }
        .buttonStyle(PlainButtonStyle())
        // ドラッグして移動できるようにします（背景部分）
        .help("Drag to move, click to capture")
        .onAppear {
            // パネルが表示された際、強調表示を開始します
            withAnimation(.easeInOut(duration: 0.5)) {
                showHighlight = true
            }
            // 3秒後に自動的に強調表示を消します
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    showHighlight = false
                }
            }
        }
    }
}

// 2. パネル（ウィンドウ）の制御クラス
// NSPanelを継承し、特殊な挙動（最前面表示、フォーカスを奪わない等）を実現します
class FloatingPanel: NSPanel {
    init(view: AnyView) {
        // ウィンドウの初期設定
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 60, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // 特殊なパネル設定
        self.isFloatingPanel = true
        // 他のアプリ（フルスクリーンアプリ含む）より上に表示されるようにします
        self.level = .mainMenu
        // 全ての操作スペース（仮想デスクトップ）やフルスクリーンアプリの上でも表示されるように設定
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 背景を透明にします
        self.backgroundColor = .clear
        // 影を表示します
        self.hasShadow = true
        // 背後のアプリからフォーカスを奪わないように設定（重要！）
        self.becomesKeyOnlyIfNeeded = true

        // 背景をドラッグしてウィンドウを移動できるようにします
        self.isMovableByWindowBackground = true

        // SwiftUIビューをコンテンツとして設定
        self.contentView = NSHostingView(rootView: view)
    }

    // パネルをクリックしても、背後のアプリが非アクティブにならないように明示的に設定
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}
