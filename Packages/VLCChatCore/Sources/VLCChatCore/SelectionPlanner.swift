import Foundation

/// 「ファイルを選択」「追加」で選んだファイルの振り分け結果。添字はすべて入力（`fileNames`）の位置。
public struct SelectionPlan: Equatable, Sendable {
  /// 動画の入力添字（名前の自然順）
  public let videos: [Int]
  /// `videos` と同じ並びの、対応づいたチャットの入力添字（無ければ nil）
  public let pairs: [Int?]
  /// 動画に対応づかず無視するチャットの入力添字（名前の自然順）
  public let ignoredChats: [Int]
  /// 動画が1本も無いとき、チャットが1つ以上あれば、名前の自然順で先頭のチャットの入力添字
  public let soleChatIndex: Int?
  /// 入力順
  public let unsupported: [Int]
  /// 最初の1つ
  public let emojiLibrary: Int?
}

public enum SelectionPlanner {
  public static func plan(fileNames: [String]) -> SelectionPlan {
    var videoIndices: [Int] = []
    var chatIndices: [Int] = []
    var unsupported: [Int] = []
    var emojiLibrary: Int?
    for (i, name) in fileNames.enumerated() {
      let ext = (name as NSString).pathExtension
      switch PickedFileKind.classify(pathExtension: ext) {
      case .video: videoIndices.append(i)
      case .chat: chatIndices.append(i)
      case .emojiLibrary: if emojiLibrary == nil { emojiLibrary = i }
      case .unsupported: unsupported.append(i)
      }
    }

    let byName: (Int, Int) -> Bool = { NaturalOrder.areInIncreasingOrder(fileNames[$0], fileNames[$1]) }
    let videos = videoIndices.sorted(by: byName)
    let chats = chatIndices.sorted(by: byName)

    if videos.isEmpty {
      return SelectionPlan(
        videos: [], pairs: [], ignoredChats: Array(chats.dropFirst()),
        soleChatIndex: chats.first, unsupported: unsupported, emojiLibrary: emojiLibrary)
    }

    let result = VideoChatPairing.pair(
      videoFileNames: videos.map { fileNames[$0] }, chatFileNames: chats.map { fileNames[$0] })
    return SelectionPlan(
      videos: videos,
      pairs: result.chatIndexForVideo.map { $0.map { chats[$0] } },
      ignoredChats: result.unmatchedChats.map { chats[$0] },
      soleChatIndex: nil, unsupported: unsupported, emojiLibrary: emojiLibrary)
  }
}
