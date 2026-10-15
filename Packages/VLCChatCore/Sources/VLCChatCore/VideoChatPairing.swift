import Foundation

/// 動画とチャットの対応づけ。
public enum VideoChatPairing {
  /// yt-dlp系のチャット保存ツールが付ける接尾辞。`chatBaseName` はこの順に調べる。
  public static let chatSuffixes = [".live_chat", ".chat_replay", "_chat"]

  /// チャットのファイル名から、拡張子 `.json` と、末尾の定型の接尾辞を1つ除いた名前。
  public static func chatBaseName(ofFileName fileName: String) -> String {
    let withoutJSON = chatNameWithoutExtension(fileName)
    let lowered = withoutJSON.lowercased()
    for suffix in chatSuffixes where lowered.hasSuffix(suffix) {
      let trimmed = String(withoutJSON.dropLast(suffix.count))
      return trimmed.isEmpty ? withoutJSON : trimmed
    }
    return withoutJSON
  }

  /// `Swift.Result` を隠さないための名前。
  public struct PairingResult: Equatable, Sendable {
    /// 動画の添字 → チャットの添字（無ければ nil）。`videoFileNames` と同じ長さ
    public let chatIndexForVideo: [Int?]
    /// どの動画にも対応づかなかったチャットの添字（昇順）
    public let unmatchedChats: [Int]
  }

  public static func pair(videoFileNames: [String], chatFileNames: [String]) -> PairingResult {
    let videoNames = videoFileNames.map { normalized(SupportedVideo.title(fromFileName: $0)) }
    let chatPlain = chatFileNames.map { normalized(chatNameWithoutExtension($0)) }
    let chatBase = chatFileNames.map { normalized(chatBaseName(ofFileName: $0)) }

    var chatIndexForVideo = [Int?](repeating: nil, count: videoFileNames.count)
    var used = Set<Int>()

    // 動画1本・チャット1本は、名前によらず組にする（M2の挙動）。
    if videoFileNames.count == 1, chatFileNames.count == 1 {
      return PairingResult(chatIndexForVideo: [0], unmatchedChats: [])
    }

    // 1段目で拡張子だけを除いた名前を先に取らせないと、動画 `X.mp4`・`X_chat.mp4` とチャット
    // `X_chat.json` で、`X.mp4` が接尾辞を除いた名前で先に取ってしまう。
    for (v, name) in videoNames.enumerated() {
      if let c = chatPlain.indices.first(where: { !used.contains($0) && chatPlain[$0] == name }) {
        chatIndexForVideo[v] = c
        used.insert(c)
      }
    }
    for (v, name) in videoNames.enumerated() where chatIndexForVideo[v] == nil {
      if let c = chatBase.indices.first(where: { !used.contains($0) && chatBase[$0] == name }) {
        chatIndexForVideo[v] = c
        used.insert(c)
      }
    }

    let unmatched = chatFileNames.indices.filter { !used.contains($0) }
    return PairingResult(chatIndexForVideo: chatIndexForVideo, unmatchedChats: unmatched)
  }

  private static func chatNameWithoutExtension(_ fileName: String) -> String {
    if fileName.lowercased().hasSuffix(".json") { return String(fileName.dropLast(5)) }
    return fileName
  }

  /// 比べる前に NFC にそろえる。大文字小文字は区別する。
  private static func normalized(_ name: String) -> String {
    name.precomposedStringWithCanonicalMapping
  }
}
