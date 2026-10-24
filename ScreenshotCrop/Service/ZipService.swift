import Foundation

enum ZipServiceError: LocalizedError {
    case folderNotFound(URL)
    case processFailed(Int32, String)
    case destinationExists(URL)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let url):
            return "Folder not found: \(url.path)"
        case .processFailed(let code, let message):
            return "ZIP compression failed (code \(code)): \(message)"
        case .destinationExists(let url):
            return "Destination file already exists: \(url.path)"
        }
    }
}

final class ZipService {
    /// 指定されたフォルダを ditto コマンドで ZIP に圧縮します。
    /// - Parameters:
    ///   - sourceFolderURL: 圧縮対象のフォルダURL
    ///   - destinationZipURL: 出力先ZIPファイルのURL
    ///   - overwrite: 既にファイルが存在する場合に上書きするかどうか
    static func compressFolder(
        sourceFolderURL: URL,
        destinationZipURL: URL,
        overwrite: Bool = true
    ) async throws {
        guard FileManager.default.fileExists(atPath: sourceFolderURL.path) else {
            throw ZipServiceError.folderNotFound(sourceFolderURL)
        }

        if !overwrite && FileManager.default.fileExists(atPath: destinationZipURL.path) {
            throw ZipServiceError.destinationExists(destinationZipURL)
        }

        try await Task.detached(priority: .userInitiated) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let tempZipURL = tempDir.appendingPathComponent(destinationZipURL.lastPathComponent)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-c", "-k",
                "--sequesterRsrc",
                "--keepParent",
                sourceFolderURL.path,
                tempZipURL.path
            ]

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown ditto error"
                throw ZipServiceError.processFailed(process.terminationStatus, errorMsg)
            }

            // 出力先の親フォルダが存在しない場合は作成
            let destParent = destinationZipURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: destParent.path) {
                try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
            }

            // 既存ファイルがあれば削除してから移動
            if FileManager.default.fileExists(atPath: destinationZipURL.path) {
                try FileManager.default.removeItem(at: destinationZipURL)
            }
            try FileManager.default.moveItem(at: tempZipURL, to: destinationZipURL)
        }.value
    }
}
