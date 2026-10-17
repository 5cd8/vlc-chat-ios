/// 長押しの後に、次に触れるまでGIFのアニメを止めておくための状態（Issue #26）。
///
/// SwiftUIの `textSelection` のメニューは、指を離した後に出る。その間にアニメの更新が再開すると、
/// メニューがすぐ閉じてしまう。そこで、長押しが認識されたら、次に触れるまで止めておく。
/// 次に触れた時点で、前のメニューは（その触れ方で）閉じるので、止めておく理由がなくなる。
///
/// スクロール状態（`ScrollPhase`）では判定できない。動かさずに触れ続けても `tracking` にならず、
/// `idle` から `interacting` に変わるだけで、長押しの認識とも結びつかないため（m4-3 の実機ログ）。
public struct LongPressHold: Equatable, Sendable {
  /// 長押しの後、まだ次に触れていない（アニメを止めておく）か。
  public private(set) var isHolding = false

  public init() {}

  /// 新しく触れた。前の長押しのメニューは、この触れ方で閉じる。
  public mutating func touchBegan() {
    isHolding = false
  }

  /// 長押しが認識された（動かさずに、一定時間触れ続けた）。
  public mutating func longPressRecognized() {
    isHolding = true
  }
}
