import Foundation
import Testing
@testable import VLCChatCore

private let youTubeText = #"""
  {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"message":{"runs":[{"text":"hi"}]},"authorName":{"simpleText":"A"},"timestampText":{"simpleText":"0:05"}}}}}]}}
  """#
private let youTubeTicker = #"""
  {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTickerPaidMessageItemRenderer":{"x":1}}}}]}}
  """#
private let youTubeBroken = #"{"replayChatItemAction":{"actions":["#

private func twitchComment(offset: Int, body: String) -> String {
  #"{"content_offset_seconds":\#(offset),"commenter":{"display_name":"A"},"message":{"body":"\#(body)","fragments":[{"text":"\#(body)","emoticon":null}]}}"#
}

private func load(_ bytes: [UInt8], chunkSize: Int, isCancelled: () -> Bool = { false }) throws -> ChatLoadResult {
  try ChatLoader.load(from: DataByteSource(Data(bytes), chunkSize: chunkSize), isCancelled: isCancelled, progress: { _ in })
}

private func texts(_ result: ChatLoadResult) -> [String] {
  (0..<result.store.count).map { position in
    if case .text(let text) = result.store.message(at: position).runs.first { return text }
    return "?"
  }
}

struct ChatLoaderTests {
  private let key = Array("\"replayChatItemAction\"".utf8)

  @Test("先頭にキーがあればYouTube、無ければTwitch") func detectsFormat() {
    #expect(ChatLoader.detectFormat(head: Array(youTubeText.utf8)) == .youTube)
    #expect(ChatLoader.detectFormat(head: Array(#"{"FileInfo":{"Version":"1.0"},"comments":[]}"#.utf8)) == .twitch)
    #expect(ChatLoader.detectFormat(head: []) == .twitch)
  }

  @Test("キーが先頭4096バイトに完全に収まるときだけYouTube") func detectFormatUsesFirst4096Bytes() {
    #expect(key.count == 22)
    let spaces = { (count: Int) in [UInt8](repeating: 0x20, count: count) }
    #expect(ChatLoader.detectFormat(head: spaces(4074) + key) == .youTube)
    #expect(ChatLoader.detectFormat(head: spaces(4075) + key) == .twitch)
    // BOMは4096バイトに数えない。
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    #expect(ChatLoader.detectFormat(head: bom + spaces(4074) + key) == .youTube)
    #expect(ChatLoader.detectFormat(head: bom + spaces(4075) + key) == .twitch)
  }

  @Test("YouTubeは対象外の行と壊れた行を除いて読み、チャンクの大きさで結果が変わらない") func loadsYouTube() throws {
    let file = Array([youTubeText, youTubeTicker, youTubeBroken].joined(separator: "\n").utf8)
    for size in [1, 7, 100_000] {
      let result = try load(file, chunkSize: size)
      #expect(result.format == .youTube, "size=\(size)")
      #expect(result.store.count == 1, "size=\(size)")
      #expect(result.skipped == 2, "size=\(size)")
      #expect(result.store.message(at: 0).author == "A")
      #expect(result.store.message(at: 0).timeSeconds == 5)
    }
  }

  @Test("Twitchはサブスク通知と負の時刻を除いて読み、チャンクの大きさで結果が変わらない") func loadsTwitch() throws {
    let comments = [
      twitchComment(offset: 3, body: "keep"),
      twitchComment(offset: 4, body: "x subscribed with Prime."),
      twitchComment(offset: -1, body: "neg"),
    ].joined(separator: ",")
    let file: [UInt8] = [0xEF, 0xBB, 0xBF] + Array(#"{"video":{},"comments":[\#(comments)],"embeddedData":{"a":[1]}}"#.utf8)
    for size in [1, 7, 100_000] {
      let result = try load(file, chunkSize: size)
      #expect(result.format == .twitch, "size=\(size)")
      #expect(texts(result) == ["keep"], "size=\(size)")
      #expect(result.skipped == 2, "size=\(size)")
    }
  }

  @Test("時刻が非昇順の入力は安定に並ぶ") func sortsLoadedMessagesStably() throws {
    let comments = [(5, "A"), (1, "B"), (5, "C"), (1, "D")].map { twitchComment(offset: $0.0, body: $0.1) }
    let file = Array(#"{"comments":[\#(comments.joined(separator: ","))]}"#.utf8)
    #expect(texts(try load(file, chunkSize: 16)) == ["B", "D", "A", "C"])
  }

  @Test("キャンセルされたらcancelledを投げる") func throwsWhenCancelled() {
    let file = Array(youTubeText.utf8)
    #expect(throws: ChatLoaderError.cancelled) { try load(file, chunkSize: 10, isCancelled: { true }) }
  }

  @Test("先読みのループでも、commentsを含まない入力のキャンセルが効く") func cancelsDuringPrefetchWithoutComments() {
    var calls = 0
    let file = Array(#"{"video":{"title":"x"},"other":[1,2,3,4,5,6,7,8,9]}"#.utf8)
    #expect(throws: ChatLoaderError.cancelled) {
      try load(file, chunkSize: 4, isCancelled: { calls += 1; return calls >= 3 })
    }
    #expect(calls == 3)
  }

  @Test("先頭の判定に足りない小さいファイルも、FileByteSource経由で最後まで読める") func loadsSmallFileFromDisk() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("small-chat-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(youTubeText.utf8).write(to: url)
    // 4099バイト未満なので、先読みで終端に達した後にもう一度読みにいく。
    let result = try ChatLoader.load(from: try FileByteSource(url: url), isCancelled: { false }, progress: { _ in })
    #expect(result.store.count == 1)

    try Data().write(to: url)
    #expect(throws: ChatLoaderError.unreadable) {
      try ChatLoader.load(from: try FileByteSource(url: url), isCancelled: { false }, progress: { _ in })
    }
  }

  @Test("先読みを過ぎたチャンクごとにもキャンセルを確かめる") func cancelsPerChunkAfterFormatDetection() {
    var calls = 0
    // 5000バイト（先頭の判定に足りる）を1000バイトずつ。先読みで5回、本体のループで3回目に真になる。
    let file = Array((#"{"x":""# + String(repeating: "a", count: 5000) + #""}"#).utf8)
    #expect(throws: ChatLoaderError.cancelled) {
      try load(file, chunkSize: 1000, isCancelled: { calls += 1; return calls >= 8 })
    }
    #expect(calls == 8)
  }

  @Test("256件ごとにもキャンセルを確かめる") func cancelsEvery256Items() {
    var calls = 0
    let file = Array(Array(repeating: youTubeText, count: 600).joined(separator: "\n").utf8)
    // 全体が1チャンクに入る。先読みで1回、本体のチャンクで1回、256件目で3回目に真になる。
    #expect(throws: ChatLoaderError.cancelled) {
      try load(file, chunkSize: 10_000_000, isCancelled: { calls += 1; return calls >= 3 })
    }
    #expect(calls == 3)
  }

  @Test("チャットとして読めない入力はunreadable") func throwsUnreadable() {
    for text in ["", #"{"x":1}"#, "[1,2]", #"{"comments":5}"#] {
      #expect(throws: ChatLoaderError.unreadable, "\(text)") { try load(Array(text.utf8), chunkSize: 5) }
    }
    // YouTubeの形式で、JSONとして読める行が1つも無い。
    #expect(throws: ChatLoaderError.unreadable) { try load(Array(youTubeBroken.utf8), chunkSize: 5) }
  }

  @Test("読めたが対象のメッセージが0件なら、空のストア") func returnsEmptyStoreWhenNothingMatches() throws {
    let twitch = try load(Array(#"{"comments":[]}"#.utf8), chunkSize: 4)
    #expect(twitch.store.count == 0)
    let youTube = try load(Array([youTubeTicker, youTubeBroken].joined(separator: "\n").utf8), chunkSize: 4)
    #expect(youTube.store.count == 0)
    #expect(youTube.skipped == 2)
  }

  @Test("進捗は5000件ごとと、最後に1回渡す") func reportsProgressEvery5000Items() throws {
    var reported: [Int] = []
    let comments = (0..<5001).map { twitchComment(offset: $0, body: "m") }.joined(separator: ",")
    let file = Array(#"{"comments":[\#(comments)]}"#.utf8)
    _ = try ChatLoader.load(
      from: DataByteSource(Data(file), chunkSize: 100_000), isCancelled: { false }, progress: { reported.append($0) })
    #expect(reported == [5000, 5001])
  }

  @Test("進捗は最後に件数を1回渡す") func reportsFinalCount() throws {
    var reported: [Int] = []
    _ = try ChatLoader.load(
      from: DataByteSource(Data(youTubeText.utf8), chunkSize: 64), isCancelled: { false }, progress: { reported.append($0) })
    #expect(reported == [1])
  }
}
