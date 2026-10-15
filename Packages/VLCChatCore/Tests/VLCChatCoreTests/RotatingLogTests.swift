import Foundation
import Testing
@testable import VLCChatCore

struct RotatingLogTests {
  /// 改行込みでちょうど30バイトの行（29文字＋改行）。
  private func line(_ n: Int) -> String {
    let head = "L\(n)-"
    return head + String(repeating: "x", count: 29 - head.count)
  }

  private func makeDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func read(_ url: URL) throws -> [String] {
    try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  private func totalSize(_ log: RotatingLog) -> Int {
    log.existingFileURLs.reduce(0) { sum, url in
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
      return sum + ((attributes?[.size] as? NSNumber)?.intValue ?? 0)
    }
  }

  @Test("初期化でファイルが作られる") func createsFileOnInit() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"), maxBytes: 100)
    #expect(FileManager.default.fileExists(atPath: log.fileURL.path))
  }

  @Test("appendした行が順に読める") func appendsInOrder() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"))
    log.append("a")
    log.append("b")
    #expect(try read(log.fileURL) == ["a", "b"])
  }

  @Test("上限を超えると退避され、現在のファイルは新しい行から始まる") func rotatesWhenOverLimit() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"), maxBytes: 100)
    for n in 1...5 { log.append(line(n)) }
    #expect(try read(log.backupURL) == [line(1), line(2), line(3)])
    #expect(try read(log.fileURL) == [line(4), line(5)])
  }

  @Test("2回目の退避で古い退避が置き換わり、合計は2×maxBytes以下") func replacesBackupAndStaysBounded() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"), maxBytes: 100)
    for n in 1...8 {
      log.append(line(n))
      #expect(totalSize(log) <= 200)
    }
    #expect(try read(log.backupURL) == [line(4), line(5), line(6)])
    #expect(try read(log.fileURL) == [line(7), line(8)])
  }

  @Test("existingFileURLsは存在するものだけを現在→退避の順で返す") func listsExistingFiles() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"), maxBytes: 100)
    #expect(log.existingFileURLs == [log.fileURL])
    for n in 1...4 { log.append(line(n)) }
    #expect(log.existingFileURLs == [log.fileURL, log.backupURL])
    #expect(log.backupURL.lastPathComponent == "app-log.1.txt")
  }

  @Test("再初期化しても追記される") func appendsAfterReinit() throws {
    let dir = try makeDirectory()
    let url = dir.appendingPathComponent("app-log.txt")
    RotatingLog(fileURL: url).append("first")
    let log = RotatingLog(fileURL: url)
    log.append("second")
    #expect(try read(url) == ["first", "second"])
  }

  @Test("再初期化時のサイズが退避の判定に使われる") func usesExistingSizeAfterReinit() throws {
    let dir = try makeDirectory()
    let url = dir.appendingPathComponent("app-log.txt")
    let first = RotatingLog(fileURL: url, maxBytes: 100)
    for n in 1...3 { first.append(line(n)) }
    let log = RotatingLog(fileURL: url, maxBytes: 100)
    log.append(line(4))
    #expect(try read(log.backupURL) == [line(1), line(2), line(3)])
    #expect(try read(url) == [line(4)])
  }

  @Test("maxBytesより大きい行でも落ちずに書かれ、空のファイルは退避されない") func hugeLineOnEmptyFile() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"), maxBytes: 100)
    let huge = String(repeating: "h", count: 200)
    log.append(huge)
    #expect(!FileManager.default.fileExists(atPath: log.backupURL.path))
    #expect(try read(log.fileURL) == [huge])
  }

  @Test("普通の行の後の大きい行は、普通の行を退避へ移す") func hugeLineAfterNormalLine() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("app-log.txt"), maxBytes: 100)
    let huge = String(repeating: "h", count: 200)
    log.append(line(1))
    log.append(huge)
    #expect(try read(log.backupURL) == [line(1)])
    #expect(try read(log.fileURL) == [huge])
  }

  @Test("ちょうどmaxBytesなら退避しない、1バイト超えれば退避する") func boundaryIsExclusive() throws {
    let dir = try makeDirectory()
    let log = RotatingLog(fileURL: dir.appendingPathComponent("a.txt"), maxBytes: 90)
    for n in 1...3 { log.append(line(n)) }
    #expect(!FileManager.default.fileExists(atPath: log.backupURL.path))
    log.append(line(4))
    #expect(FileManager.default.fileExists(atPath: log.backupURL.path))
  }
}
