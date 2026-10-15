import Foundation

/// チャットファイルを順に読むための入力。ファイル全体をメモリに載せないために、チャンク単位で返す。
public protocol ChatByteSource {
  /// 次のチャンク。終端で `nil`（空のチャンクは返さない）。
  /// 終端の後に呼んでも `nil` を返す（先読みで終端に達した後に、続きを読みにいくため）。
  mutating func nextChunk() throws -> [UInt8]?
}

/// メモリ上のデータを `chunkSize` ごとに返す。テスト用。
public struct DataByteSource: ChatByteSource {
  private let data: [UInt8]
  private let chunkSize: Int
  private var offset = 0

  public init(_ data: Data, chunkSize: Int) {
    self.data = [UInt8](data)
    self.chunkSize = max(1, chunkSize)
  }

  public mutating func nextChunk() throws -> [UInt8]? {
    guard offset < data.count else { return nil }
    let end = min(offset + chunkSize, data.count)
    defer { offset = end }
    return Array(data[offset..<end])
  }
}

/// `FileHandle` で `chunkSize`（既定1MiB）ずつ読む。
public struct FileByteSource: ChatByteSource {
  private let handle: FileHandle
  private let chunkSize: Int
  private var isFinished = false

  /// 開けないときは投げる。
  public init(url: URL, chunkSize: Int = 1 << 20) throws {
    handle = try FileHandle(forReadingFrom: url)
    self.chunkSize = max(1, chunkSize)
  }

  public mutating func nextChunk() throws -> [UInt8]? {
    // 閉じた後の `FileHandle` を読むと投げるので、終端に達したら以後は読まずに `nil` を返す。
    guard !isFinished else { return nil }
    // 終端では `nil` ではなく空の `Data` が返ることがあるので、両方を終端として扱う。
    guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else {
      isFinished = true
      try? handle.close()
      return nil
    }
    return [UInt8](data)
  }
}
