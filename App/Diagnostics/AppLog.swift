import Foundation
import VLCChatCore

/// `Documents/app-log.txt` への追記ログ（5MBで1世代に退避）。
///
/// 1行ごとに同期して書く。背面で落ちたときに、直前の手がかりが残るようにするため。
/// ログは「ファイル」アプリと、画面の「ログを共有」から取り出せる。
enum AppLog {
  static let shared: RotatingLog = {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return RotatingLog(fileURL: documents.appendingPathComponent("app-log.txt"))
  }()

  private static let lock = NSLock()
  private static let formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    // 体感で覚えている時刻と突き合わせられるよう、UTCではなく端末のタイムゾーンで書く。
    formatter.timeZone = .current
    return formatter
  }()

  static func write(_ message: String) {
    lock.lock()
    let stamp = formatter.string(from: Date())
    lock.unlock()
    shared.append("\(stamp) \(message)")
  }
}
