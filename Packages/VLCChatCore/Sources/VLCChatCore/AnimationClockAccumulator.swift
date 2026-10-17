import Foundation

/// 表示のタイムスタンプ（`CADisplayLink.timestamp`）の列から、止まっている間を除いた経過秒を作る。
/// 1回の進みは `maxStep` までにする（停止からの再開や、主スレッドの停滞で、アニメが飛ばないように）。
public struct AnimationClockAccumulator: Sendable {
  public private(set) var time: TimeInterval = 0
  private var lastTimestamp: TimeInterval?

  public init() {}

  /// 最初の呼び出し（または `pause()` の後の最初）は、基準を取るだけで `time` を進めない。
  /// 差が0以下（同じ時刻、または時刻が逆戻りした）ときも進めず、基準だけを更新する。
  public mutating func advance(to timestamp: TimeInterval, maxStep: TimeInterval = 0.1) {
    let previous = lastTimestamp
    lastTimestamp = timestamp
    guard let previous else { return }
    let delta = timestamp - previous
    guard delta > 0 else { return }
    time += min(delta, maxStep)
  }

  /// 止める。次の `advance` は基準を取り直す。`time` は保つ。
  public mutating func pause() {
    lastTimestamp = nil
  }
}
