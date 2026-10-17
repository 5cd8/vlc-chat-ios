import Foundation

/// 長押しの後に、次に触れるまでGIFのアニメを止めておくための判定（Issue #26）。
///
/// SwiftUIの `textSelection` は、同じスクロール領域の中で更新が続くと、選択のメニューを閉じてしまう。
/// 長押しで出るメニューは指を離した後に出るので、指を離してスクロール状態が `idle` に戻った途端に
/// アニメが動き出すと、メニューがすぐ閉じる。そこで、動かさずに `threshold` 以上触れていた後は、
/// 次に触れる（短く触れて離す、またはスクロールを始める）まで止めたままにする。
public struct LongPressHold: Equatable, Sendable {
  /// これ以上、動かさずに触れていたら長押しとみなす（秒）。システムの長押し認識（0.5秒）より少し短くして、
  /// 認識の時点で `idle` に戻る場合も、離したときに `idle` に戻る場合も、同じように拾う。
  public static let threshold: TimeInterval = 0.45

  /// 長押しの後、まだ次に触れていない（アニメを止めておく）か。
  public private(set) var isHolding = false
  private var touchStartedAt: TimeInterval?

  public init() {}

  /// 指が触れた（スクロールビューが操作を追い始めた）。
  public mutating func touchBegan(at now: TimeInterval) {
    touchStartedAt = now
  }

  /// 動かさずに操作が終わった（`tracking` から `idle` に戻った）。
  /// `threshold` 以上触れていたら長押し。そうでなければ（短く触れて離した）止めておかない。
  /// 触れた時刻が分からないとき（スクロールの後など）は変えない。
  public mutating func touchEnded(at now: TimeInterval) {
    guard let start = touchStartedAt else { return }
    touchStartedAt = nil
    isHolding = now - start >= Self.threshold
  }

  /// スクロールが始まった。選択のメニューはスクロールで閉じるので、止めておく理由がなくなる。
  public mutating func scrollBegan() {
    touchStartedAt = nil
    isHolding = false
  }
}
