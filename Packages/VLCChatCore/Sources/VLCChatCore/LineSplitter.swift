/// チャンクに分かれたバイト列を、1行ずつに切り出す（YouTubeのJSON Lines用）。
///
/// 区切りは `\n` だけ（末尾の `\r` は除く）。PC版の `ReadLine` は単独の `\r` でも区切るが、
/// yt-dlpの出力は `\n` なので揃えていない。空行と空白だけの行は渡さない（PC版の `IsNullOrWhiteSpace` と同じ）。
/// 先頭のUTF-8のBOMは読み飛ばす（PC版は `StreamReader` が除く）。
public struct LineSplitter {
  private var buffer: [UInt8] = []
  private var isFirstLine = true

  public init() {}

  /// 1行が完成するたびに `handler` を呼ぶ。チャンクをまたぐ行は内部のバッファに持ち越す。
  public mutating func feed(_ chunk: [UInt8], handler: (ArraySlice<UInt8>) throws -> Void) rethrows {
    var start = 0
    while let newline = chunk[start...].firstIndex(of: 0x0A) {
      buffer.append(contentsOf: chunk[start..<newline])
      try emit(handler)
      start = newline + 1
    }
    buffer.append(contentsOf: chunk[start...])
  }

  /// 末尾に改行の無い最後の行を渡す。
  public mutating func finish(handler: (ArraySlice<UInt8>) throws -> Void) rethrows {
    if !buffer.isEmpty { try emit(handler) }
  }

  private mutating func emit(_ handler: (ArraySlice<UInt8>) throws -> Void) rethrows {
    var line = buffer[...]
    if isFirstLine {
      isFirstLine = false
      if line.starts(with: [0xEF, 0xBB, 0xBF]) { line = line.dropFirst(3) }
    }
    if line.last == 0x0D { line = line.dropLast() }
    if !line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
      try handler(line)
    }
    // 巨大な1行の後に、その容量を持ち続けない。
    buffer.removeAll(keepingCapacity: buffer.capacity <= (4 << 20))
  }
}
