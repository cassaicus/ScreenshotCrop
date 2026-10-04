import Combine

/// Replacing the store also gives all views fresh startup state.
@MainActor
final class WorkSession: ObservableObject {
    @Published private(set) var store = ImageStore()

    func clearWorkData() {
        // Let file-writing operations finish before discarding their state.
        guard !store.isProcessing else { return }
        let interval = store.autoManager.autoCaptureInterval
        let threshold = store.autoManager.autoCaptureThreshold
        store.prepareForReset()
        ThumbnailCache.shared.clear()

        let freshStore = ImageStore()
        freshStore.autoManager.autoCaptureInterval = interval
        freshStore.autoManager.autoCaptureThreshold = threshold
        store = freshStore
    }
}
