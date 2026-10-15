import Foundation

public struct ChatLoadResult: Sendable {
  public let store: ChatStore
  public let format: ChatFormat
  /// 除いた件数。JSONとして読めない行と、パーサーが対象外とした行（ティッカー・サブスク通知・負の時刻など）。
  public let skipped: Int
}

public enum ChatLoaderError: Error, Equatable {
  case cancelled
  /// チャットの形式として読めない（Twitchは `comments` の配列に入れない、YouTubeはJSONとして読める行が無い）。
  case unreadable
}

/// チャットファイルを先頭から順に読み、形式を判定して `ChatStore` にする。
public enum ChatLoader {
  /// 形式の判定に使う先頭のバイト数（PC版と同じ）。
  public static let formatPeekLength = 4096

  /// 引用符込みの `"replayChatItemAction"`（22バイト）を先頭4096バイトの中に含めば YouTube。
  /// PC版も引用符込みで探す。BOMの読み飛ばしと切り詰めは、この関数の中で行う。
  /// PC版は先頭4096「文字」を見るが、Issue の決定に従いバイトで見る（キーはASCIIなので実データでは同じ結果）。
  public static func detectFormat(head: [UInt8]) -> ChatFormat {
    var start = 0
    if head.starts(with: [0xEF, 0xBB, 0xBF]) { start = 3 }
    let window = head[start..<min(head.count, start + formatPeekLength)]
    let needle = Array("\"replayChatItemAction\"".utf8)
    guard window.count >= needle.count else { return .twitch }
    let lastStart = window.endIndex - needle.count
    var index = window.startIndex
    while index <= lastStart {
      if window[index] == needle[0] && window[index..<(index + needle.count)].elementsEqual(needle) {
        return .youTube
      }
      index += 1
    }
    return .twitch
  }

  /// `isCancelled` は、チャンクを読むたびと256件ごとに確かめる。`progress` には追加済みの件数を、
  /// 5000件ごと、および並べ替えと容量の詰め直し（`finish()`）の直後に1回渡す。
  public static func load(
    from source: some ChatByteSource,
    isCancelled: () -> Bool,
    progress: (Int) -> Void
  ) throws -> ChatLoadResult {
    var source = source

    // 形式の判定に必要な先頭（BOM＋4096バイト）まで先に読む。読んだチャンクは後で処理に回す。
    var prefetched: [[UInt8]] = []
    var head: [UInt8] = []
    let headLength = 3 + formatPeekLength
    while head.count < headLength, let chunk = try source.nextChunk() {
      if isCancelled() { throw ChatLoaderError.cancelled }
      prefetched.append(chunk)
      head.append(contentsOf: chunk)
    }
    let format = detectFormat(head: head)
    prefetched.reverse()

    var builder = ChatStoreBuilder()
    var skipped = 0
    var readableLines = 0
    var handled = 0
    var sinceProgress = 0

    /// 1行／1要素ぶんの処理全体を1つの `autoreleasepool` に入れる。`JSONSerialization` が作る一時オブジェクトを、
    /// 行ごとに解放して、ピークのメモリを抑えるため。
    func handle(_ bytes: some Sequence<UInt8>, parse: ([String: Any]) -> ChatMessage?) throws {
      handled += 1
      if handled % 256 == 0, isCancelled() { throw ChatLoaderError.cancelled }
      autoreleasepool {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any] else {
          skipped += 1
          return
        }
        readableLines += 1
        guard let message = parse(object) else {
          skipped += 1
          return
        }
        builder.append(
          timeSeconds: message.timeSeconds, author: message.author, role: message.role, runs: message.runs
        )
        sinceProgress += 1
      }
      if sinceProgress >= 5000 {
        sinceProgress = 0
        progress(builder.count)
      }
    }

    var lineSplitter = LineSplitter()
    var objectSplitter = JSONObjectSplitter()

    func nextChunk() throws -> [UInt8]? {
      if let chunk = prefetched.popLast() { return chunk }
      return try source.nextChunk()
    }

    chunks: while let chunk = try nextChunk() {
      if isCancelled() { throw ChatLoaderError.cancelled }
      switch format {
      case .youTube:
        try lineSplitter.feed(chunk) { line in
          try handle(line, parse: YouTubeChatParser.parse(line:))
        }
      case .twitch:
        let status = try objectSplitter.feed(chunk) { element in
          try handle(element, parse: TwitchChatParser.parse(comment:))
        }
        // 配列が閉じたら、以降のバイト（大きな別プロパティなど）は読まない。
        if status == .finished { break chunks }
      }
    }
    if format == .youTube {
      try lineSplitter.finish { line in
        try handle(line, parse: YouTubeChatParser.parse(line:))
      }
    }

    switch format {
    case .youTube:
      if readableLines == 0 { throw ChatLoaderError.unreadable }
    case .twitch:
      if objectSplitter.outcome != .arrayFound { throw ChatLoaderError.unreadable }
    }

    let store = builder.finish()
    progress(store.count)
    return ChatLoadResult(store: store, format: format, skipped: skipped)
  }
}
