import Foundation

/// 1ファイル最大 `maxBytes`、1世代の退避（`app-log.txt` → `app-log.1.txt`）を持つログファイル。
public final class RotatingLog: @unchecked Sendable {
  public let fileURL: URL
  private let maxBytes: Int
  private let fileManager: FileManager
  private let lock = NSLock()
  private var handle: FileHandle?
  /// 現在のファイルのサイズ。書いたバイト数をメモリ上で数える（毎回ファイルシステムに聞かない）。
  private var currentSize = 0

  public init(fileURL: URL, maxBytes: Int = 5 * 1024 * 1024, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.maxBytes = maxBytes
    self.fileManager = fileManager
    openForAppending()
  }

  deinit {
    try? handle?.close()
  }

  /// 例: …/app-log.1.txt（拡張子の前に ".1"）
  public var backupURL: URL {
    let ext = fileURL.pathExtension
    let base = fileURL.deletingPathExtension().lastPathComponent
    let name = ext.isEmpty ? "\(base).1" : "\(base).1.\(ext)"
    return fileURL.deletingLastPathComponent().appendingPathComponent(name)
  }

  /// 存在するものだけ。現在 → 退避の順（共有シート用）。
  public var existingFileURLs: [URL] {
    [fileURL, backupURL].filter { fileManager.fileExists(atPath: $0.path) }
  }

  /// 1行ごとに同期して書く。書き込みの失敗は握りつぶす（ログがアプリを落とさない）。
  public func append(_ line: String) {
    lock.lock()
    defer { lock.unlock() }
    let data = Data((line + "\n").utf8)
    // 現在のファイルが空なら退避しない。空のファイルを退避すると、中身のある退避ファイルを消してしまう。
    // 1行が maxBytes より大きいときも、その行は新しいファイルに書く（無限に退避しない）。
    if currentSize > 0, currentSize + data.count > maxBytes {
      rotate()
    }
    guard let handle else { return }
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      currentSize += data.count
    } catch {
      // 握りつぶす
    }
  }

  private func openForAppending() {
    if !fileManager.fileExists(atPath: fileURL.path) {
      try? fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      fileManager.createFile(atPath: fileURL.path, contents: nil)
    }
    guard let opened = try? FileHandle(forWritingTo: fileURL) else { return }
    currentSize = Int((try? opened.seekToEnd()) ?? 0)
    handle = opened
  }

  private func rotate() {
    // ハンドルを閉じないと、移動した退避ファイルに書き続けてしまう。
    try? handle?.close()
    handle = nil
    try? fileManager.removeItem(at: backupURL)
    try? fileManager.moveItem(at: fileURL, to: backupURL)
    currentSize = 0
    openForAppending()
  }
}
