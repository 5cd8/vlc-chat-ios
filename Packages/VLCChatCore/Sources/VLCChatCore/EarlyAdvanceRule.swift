import Foundation

/// PiP中の自動進行で、動画の終わりの手前に先行して次へ進むかの規則。
///
/// 動画の終端では、libVLCが映像出力を壊し、PiPがその場で止まる。`endReached` を待つと間に合わない
/// （映像出力が壊れた後の差し替えは、SwiftVLCがPiPを保つ対象外）。再生の途中の差し替えなら保たれるので、
/// 終端の手前で次へ進む。
public enum EarlyAdvanceRule {
  /// 終わりまで残りこの実時間（秒）になったら、先行して次へ進む。実機（iPhone 16）では、0.5秒で4/4、
  /// 0.3秒で5/5、PiPが保たれた。これ以上縮めても得られるのは終端の0.1秒ほどなので、0.3秒で確定する。
  public static let marginSeconds: TimeInterval = 0.3
  /// 再生が始まってすぐの誤発火を防ぐ。
  public static let minimumPlayed: TimeInterval = 1.0

  /// `position`・`duration` はメディアの秒。`rate` は再生速度（残りを実時間にするために使う）。
  /// 残りが負（長さを超えた）のときは偽。実際には時計が長さで切り詰めるので、残りは0で真になる。
  public static func shouldAdvance(position: TimeInterval, duration: TimeInterval?, rate: Double) -> Bool {
    guard let duration, duration > 0, rate > 0 else { return false }
    let remaining = duration - position
    return remaining >= 0 && remaining <= marginSeconds * rate && position >= minimumPlayed
  }

  /// 先行切り替えの後に手前へシークして終端が遠ざかったか（印を下ろして再び先行できるようにする）。
  /// 閾値の2倍を超えて離れたときだけ真にし、閾値の付近での揺れで再発火しないようにする。
  public static func shouldRearm(position: TimeInterval, duration: TimeInterval, rate: Double) -> Bool {
    duration - position > marginSeconds * rate * 2
  }
}
