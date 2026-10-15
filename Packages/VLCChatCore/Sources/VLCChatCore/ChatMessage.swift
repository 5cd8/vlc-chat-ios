/// 投稿者の種別。装飾の色分けに使う。
public enum ChatRole: UInt8, Sendable {
  case normal = 0
  case moderator = 1
  case owner = 2
}

/// 本文の1区間。
public enum ChatRun: Equatable, Sendable {
  case text(String)
  /// 画像の絵文字。`url` は絵文字ライブラリのキー、`alt` はライブラリに無いときの代替テキスト（空もあり得る）。
  case emoji(url: String, alt: String)
}

public struct ChatMessage: Equatable, Sendable {
  /// 動画開始からの秒（整数）。
  public let timeSeconds: Int
  public let author: String
  public let role: ChatRole
  public let runs: [ChatRun]

  public init(timeSeconds: Int, author: String, role: ChatRole, runs: [ChatRun]) {
    self.timeSeconds = timeSeconds
    self.author = author
    self.role = role
    self.runs = runs
  }
}
