/// 「ファイルを選択」で選んだファイルの種類。拡張子だけで決める（大文字小文字を区別しない）。
public enum PickedFileKind: Equatable, Sendable {
  case video
  /// チャットのJSON（YouTube／Twitch）
  case chat
  /// 絵文字ライブラリ（SQLite）
  case emojiLibrary
  case unsupported

  public static func classify(pathExtension: String) -> PickedFileKind {
    if SupportedVideo.isSupported(pathExtension: pathExtension) { return .video }
    switch pathExtension.lowercased() {
    case "json": return .chat
    case "sqlite": return .emojiLibrary
    default: return .unsupported
    }
  }
}
