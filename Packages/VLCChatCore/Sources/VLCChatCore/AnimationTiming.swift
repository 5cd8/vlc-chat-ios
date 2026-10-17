import Foundation

/// アニメーション画像の各フレームの表示時間と、時刻から表示するフレームを選ぶ規則。
/// 遅延は、10ms以下を100msとして扱う。WebKit・Firefoxが採る慣習で、遅延が0や1センチ秒のGIFが
/// 最大速度で回って見えるのを避ける。常に無限ループする。
public struct AnimationTiming: Equatable, Sendable {
  /// 正規化後の各フレームの表示時間。
  public let delays: [TimeInterval]
  /// 1周の長さ。`delays` の合計（累積の最後の値そのもの。別の足し算で求めると誤差で食い違うため）。
  public let loopDuration: TimeInterval
  /// 各フレームの終了時刻の累積。
  private let ends: [TimeInterval]

  public init(rawDelays: [TimeInterval]) {
    let normalized = rawDelays.map(Self.normalizedDelay)
    var ends: [TimeInterval] = []
    var total: TimeInterval = 0
    for delay in normalized {
      total += delay
      ends.append(total)
    }
    self.delays = normalized
    self.ends = ends
    self.loopDuration = ends.last ?? 0
  }

  /// 10ms以下（読み取れない値を含む）は100ms。境界の比較にはImageIOが返すDoubleの誤差を見込む。
  public static func normalizedDelay(_ raw: TimeInterval) -> TimeInterval {
    raw.isFinite && raw > 0.01 + 1e-6 ? raw : 0.1
  }

  /// `time` が属するフレームの添字。1周で折り返し、境界ちょうどは次のフレームに属する。
  /// 負の値・非有限（NaN・無限大）は0。フレームが無ければ0。
  public func frameIndex(at time: TimeInterval) -> Int {
    guard let last = ends.last, time.isFinite, time > 0 else { return 0 }
    let position = time.truncatingRemainder(dividingBy: last)
    // `ends[i] > position` となる最初の添字を二分探索する。
    var low = 0
    var high = ends.count
    while low < high {
      let middle = (low + high) / 2
      if ends[middle] > position {
        high = middle
      } else {
        low = middle + 1
      }
    }
    // 誤差で範囲外を読まないための保険。
    return min(low, ends.count - 1)
  }
}
