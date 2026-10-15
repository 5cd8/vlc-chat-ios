import Foundation

public enum SupportedVideo {
  public static let extensions: Set<String> = ["mp4", "mov", "webm", "mkv"]

  /// 大文字小文字を区別しない。
  public static func isSupported(pathExtension: String) -> Bool {
    extensions.contains(pathExtension.lowercased())
  }

  /// 最後の拡張子だけを除く。
  public static func title(fromFileName name: String) -> String {
    (name as NSString).deletingPathExtension
  }
}
