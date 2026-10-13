import Darwin
import Foundation

/// `Documents/m0-log.txt` への追記ログ。
///
/// 1行ごとに同期して書き込む。背面で落ちたときに、直前の手がかりが残るようにするため。
/// ログは「ファイル」アプリと、画面の「ログを共有」から取り出せる。
final class DiagnosticsLog: @unchecked Sendable {
  static let shared = DiagnosticsLog()

  let fileURL: URL
  private let lock = NSLock()
  private let handle: FileHandle?
  private let formatter: ISO8601DateFormatter

  private init() {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    fileURL = documents.appendingPathComponent("m0-log.txt")
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
    handle = try? FileHandle(forWritingTo: fileURL)
    _ = try? handle?.seekToEnd()
    formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    // 体感で覚えている時刻と突き合わせられるよう、UTCではなく端末のタイムゾーンで書く。
    formatter.timeZone = .current
  }

  func write(_ message: String) {
    lock.lock()
    defer { lock.unlock() }
    let line = "\(formatter.string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    try? handle?.write(contentsOf: data)
    try? handle?.synchronize()
  }

  /// プロセスのメモリ使用量（`phys_footprint`、MB）。
  static func physFootprintMB() -> Double? {
    var info = task_vm_info_data_t()
    // TASK_VM_INFO_COUNT マクロは Swift に取り込まれないため、自分で計算する。
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Double(info.phys_footprint) / 1_048_576
  }
}
