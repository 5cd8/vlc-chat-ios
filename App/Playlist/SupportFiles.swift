import Foundation

/// Application Support 下の保存ファイル。
enum SupportFiles {
  static func url(_ name: String) -> URL {
    let directory =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.temporaryDirectory
    return directory.appendingPathComponent(name)
  }

  /// 読めないファイルを `<名前>.broken-<日時>.json` に改名して残す（既存を上書きしない）。
  static func quarantine(_ url: URL) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMddHHmmss"
    let base = url.deletingPathExtension().lastPathComponent
    let target = url.deletingLastPathComponent()
      .appendingPathComponent("\(base).broken-\(formatter.string(from: Date())).json")
    do {
      try FileManager.default.moveItem(at: url, to: target)
      AppLog.write("保存ファイル 破損のため退避 \(target.lastPathComponent)")
    } catch {
      AppLog.write("保存ファイル 退避に失敗: \(error)")
    }
  }
}
