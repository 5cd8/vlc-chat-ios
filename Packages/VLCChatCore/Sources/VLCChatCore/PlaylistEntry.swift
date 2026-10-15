import Foundation

/// プレイリストの1項目。Swiftの `Entry` の慣習に合わせた名前で、用語としては「プレイリスト項目」。
public struct PlaylistEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  /// 拡張子込みの動画のファイル名（一覧の表示名）。記憶の識別は、開いたURLから作る。
  public var videoFileName: String
  public var videoBookmark: Data
  public var chatFileName: String?
  public var chatBookmark: Data?

  public init(
    id: UUID = UUID(), videoFileName: String, videoBookmark: Data,
    chatFileName: String? = nil, chatBookmark: Data? = nil
  ) {
    self.id = id
    self.videoFileName = videoFileName
    self.videoBookmark = videoBookmark
    self.chatFileName = chatFileName
    self.chatBookmark = chatBookmark
  }

  /// 拡張子を除いた名前。
  public var title: String { SupportedVideo.title(fromFileName: videoFileName) }
}
