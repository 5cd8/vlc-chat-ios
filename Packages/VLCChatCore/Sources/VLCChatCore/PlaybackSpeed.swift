import Foundation

public enum PlaybackSpeed {
  public static let steps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  public static let normal: Double = 1.0

  /// 例: 0.5 → "0.5x"、1.0 → "1x"、1.25 → "1.25x"。
  /// `String(describing:)` はロケールに依存しない（小数点は常に `.`）。
  public static func label(_ speed: Double) -> String {
    var text = String(describing: speed)
    if text.hasSuffix(".0") { text.removeLast(2) }
    return text + "x"
  }
}
