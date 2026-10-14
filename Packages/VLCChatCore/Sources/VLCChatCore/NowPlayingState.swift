import Foundation

/// ロック画面・コントロールセンターに出す情報。
public struct NowPlayingState: Equatable, Sendable {
  public let title: String
  /// nil なら長さを出さない
  public let duration: TimeInterval?
  public let position: TimeInterval
  /// ユーザーが選んだ再生速度
  public let rate: Double
  public let isPlaying: Bool

  public init(title: String, duration: TimeInterval?, position: TimeInterval, rate: Double, isPlaying: Bool) {
    self.title = title
    self.duration = duration
    self.position = position
    self.rate = rate
    self.isPlaying = isPlaying
  }

  /// 0 以上、`duration` があればそれ以下。
  public var elapsedForSystem: TimeInterval {
    let nonNegative = max(0, position)
    guard let duration else { return nonNegative }
    return min(nonNegative, duration)
  }

  /// システムは経過時間をこの速度で自分で進める。一時停止中は 0。
  public var rateForSystem: Double { isPlaying ? rate : 0 }

  /// `title` が nil なら nil（ロック画面に出す動画が無い）。
  public static func make(title: String?, clock: PlaybackClock, at: TimeInterval) -> NowPlayingState? {
    guard let title else { return nil }
    return NowPlayingState(
      title: title,
      duration: clock.duration,
      position: clock.position(at: at),
      rate: clock.rate,
      isPlaying: clock.mode == .playing
    )
  }
}
