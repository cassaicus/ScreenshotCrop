import SwiftUI
import AppKit

// 連続したスクリーンショット画像を巻ごとにフォルダ仕分けするためのビュー
// 【ワンクリック新巻開始（🚩）方式】
struct VolumeSplitView: View {
    @EnvironmentObject var store: ImageStore
    @Environment(\.dismiss) var dismiss

    // 仕分け用の個別アイテム状態
    struct SplitItem: Identifiable {
        let id: UUID
        let item: ImageItem
        let originalIndex: Int
        var isVolumeStart: Bool = false
        var isExcluded: Bool = false
    }

    // 各巻のグループ情報
    struct VolumeSummary: Identifiable {
        let id: Int
        let volumeNumber: Int
        let startIndex: Int
        let count: Int
        let firstItem: ImageItem
    }

    @State private var items: [SplitItem] = []
    @State private var prefixName: String = ""
    @State private var renumberFiles: Bool = true
    @State private var isExecuting: Bool = false
    @State private var statusMessage: String? = nil

    // 計算プロパティ: 現在の巻の区切り情報
    private var volumeSummaries: [VolumeSummary] {
        var summaries: [VolumeSummary] = []
        var currentVol = 1
        var currentCount = 0
        var currentStart = 0
        var firstItemInVol: ImageItem? = nil

        let activeItems = items.filter { !$0.isExcluded }

        for (idx, item) in activeItems.enumerated() {
            if idx == 0 {
                currentStart = 0
                firstItemInVol = item.item
                currentCount = 1
            } else if item.isVolumeStart {
                if let first = firstItemInVol {
                    summaries.append(VolumeSummary(
                        id: currentVol,
                        volumeNumber: currentVol,
                        startIndex: currentStart,
                        count: currentCount,
                        firstItem: first
                    ))
                }
                currentVol += 1
                currentStart = idx
                firstItemInVol = item.item
                currentCount = 1
            } else {
                currentCount += 1
            }
        }

        if let first = firstItemInVol, currentCount > 0 {
            summaries.append(VolumeSummary(
                id: currentVol,
                volumeNumber: currentVol,
                startIndex: currentStart,
                count: currentCount,
                firstItem: first
            ))
        }

        return summaries
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            volumeSummaryBar
            Divider()

            imageGridSection
            Divider()

            footerSection
        }
        .frame(minWidth: 850, idealWidth: 950, minHeight: 650, idealHeight: 750)
        .onAppear {
            setupItems()
        }
    }

    // MARK: - ヘッダー
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sort Screenshots into Volumes")
                    .font(.headline)
                Text("Click on a cover image (or 'Start New Vol') to mark the start of each volume. Excluded images will be deleted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // リセットボタン
            Button("Reset All Splits") {
                resetSplits()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .disabled(items.isEmpty)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 巻ごとのサマリーバー
    private var volumeSummaryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                let summaries = volumeSummaries
                ForEach(summaries) { summary in
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .foregroundColor(.blue)
                        Text(formatFolderName(volumeNumber: summary.volumeNumber))
                            .fontWeight(.medium)
                        Text("(\(summary.count)p)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }

                let excludedCount = items.filter { $0.isExcluded }.count
                if excludedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text("Excluded: \(excludedCount)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - グリッド表示
    private var imageGridSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let columns = [
                    GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 14)
                ]

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemCard(at: index)
                            .id(item.id)
                    }
                }
                .padding()
            }
        }
    }

    // 個々の画像カード
    @ViewBuilder
    private func itemCard(at index: Int) -> some View {
        let item = items[index]
        let volNum = volumeNumberForIndex(index)

        VStack(spacing: 6) {
            // 巻開始マーカー / ヘッダー
            HStack {
                if index == 0 || item.isVolumeStart {
                    HStack(spacing: 3) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.white)
                        Text("Vol. \(volNum)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
                }
                Spacer()

                // 除外チェックボックス
                HStack(spacing: 2) {
                    Toggle("", isOn: Binding(
                        get: { items[index].isExcluded },
                        set: { items[index].isExcluded = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    if item.isExcluded {
                        Text("Exclude")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .help("Exclude and delete this screenshot")
            }

            // サムネイル表示
            ZStack(alignment: .bottom) {
                CleanupThumbnailView(url: item.item.url)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                item.isVolumeStart ? Color.blue : (item.isExcluded ? Color.red : Color.gray.opacity(0.2)),
                                lineWidth: item.isVolumeStart ? 3 : (item.isExcluded ? 2 : 1)
                            )
                    )
                    .opacity(item.isExcluded ? 0.35 : 1.0)
                    .onTapGesture {
                        toggleVolumeStart(at: index)
                    }

                // 「ここから新巻」トグルボタン
                if index > 0 && !item.isExcluded {
                    Button(action: {
                        toggleVolumeStart(at: index)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: item.isVolumeStart ? "xmark.circle.fill" : "flag.fill")
                            Text(item.isVolumeStart ? "Cancel Split" : "Start New Vol")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.isVolumeStart ? Color.red.opacity(0.85) : Color.black.opacity(0.65))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
            }

            // ファイル名・インデックス表示
            VStack(spacing: 1) {
                Text("#\(item.originalIndex + 1) \(item.item.url.lastPathComponent)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(item.isExcluded ? .secondary : .primary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isVolumeStart ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - フッター設定セクション
    private var footerSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                // フォルダ名プレフィックス
                HStack(spacing: 6) {
                    Text("Folder Prefix:")
                        .font(.caption)
                    TextField("e.g. MangaTitle or Vol_", text: $prefixName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }

                // リネーム設定
                Toggle("Renumber files inside folder (001.png, 002.png...)", isOn: $renumberFiles)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if let message = statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                let summaries = volumeSummaries
                Button(action: executeSorting) {
                    HStack(spacing: 6) {
                        if isExecuting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Image(systemName: "folder.badge.gearshape")
                        Text("Sort into \(summaries.count) Volume Folders")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isExecuting || summaries.isEmpty)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - ロジック関数

    private func setupItems() {
        self.items = store.items.enumerated().map { idx, img in
            SplitItem(
                id: img.id,
                item: img,
                originalIndex: idx,
                isVolumeStart: false,
                isExcluded: false
            )
        }

        // デフォルトのフォルダプレフィックスを親フォルダ名などから推定
        if let folderURL = store.screenshotFolderURL {
            let name = folderURL.lastPathComponent
            if name != "Screenshots" && !name.isEmpty {
                prefixName = name
            }
        }
    }

    private func volumeNumberForIndex(_ targetIndex: Int) -> Int {
        var vol = 1
        for (idx, item) in items.enumerated() {
            if idx > 0 && item.isVolumeStart && !item.isExcluded {
                vol += 1
            }
            if idx == targetIndex {
                return vol
            }
        }
        return vol
    }

    private func toggleVolumeStart(at index: Int) {
        guard index > 0, index < items.count else { return }
        items[index].isVolumeStart.toggle()
    }

    private func resetSplits() {
        for i in 0..<items.count {
            items[i].isVolumeStart = false
            items[i].isExcluded = false
        }
    }

    private func formatFolderName(volumeNumber: Int) -> String {
        let cleanPrefix = prefixName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPrefix.isEmpty {
            return String(format: "Vol_%02d", volumeNumber)
        } else {
            return String(format: "%@_%02d", cleanPrefix, volumeNumber)
        }
    }

    // 仕分け処理の実行
    private func executeSorting() {
        guard !isExecuting else { return }
        isExecuting = true
        statusMessage = "Sorting files..."

        let activeItems = items
        let renumber = self.renumberFiles

        // グループ作成
        var groups: [(folderName: String, items: [ImageItem])] = []
        var currentVol = 1
        var currentGroupItems: [ImageItem] = []

        var excludedItems: [ImageItem] = []

        for (idx, item) in activeItems.enumerated() {
            if item.isExcluded {
                excludedItems.append(item.item)
                continue
            }

            if idx > 0 && item.isVolumeStart && !currentGroupItems.isEmpty {
                let folderName = formatFolderName(volumeNumber: currentVol)
                groups.append((folderName: folderName, items: currentGroupItems))
                currentVol += 1
                currentGroupItems = []
            }

            currentGroupItems.append(item.item)
        }

        if !currentGroupItems.isEmpty {
            let folderName = formatFolderName(volumeNumber: currentVol)
            groups.append((folderName: folderName, items: currentGroupItems))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.store.organizeImagesIntoVolumes(
                    groups: groups,
                    itemsToDelete: excludedItems,
                    renumberFiles: renumber
                )
                self.isExecuting = false
                self.dismiss()
            }
        }
    }
}
