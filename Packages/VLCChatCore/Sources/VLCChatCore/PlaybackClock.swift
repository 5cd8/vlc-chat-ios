import Foundation

/// libVLC の `timeChanged`（約260ms間隔）から、UI・ロック画面・チャット同期が使う滑らかな現在位置を作る。
///
/// 時計は内部に持たない。`at` には `ProcessInfo.processInfo.systemUptime` など単調増加の秒を、
/// 呼び出し側が渡す。
public struct PlaybackClock: Sendable {
  public enum Mode: Sendable, Equatable { case stopped, paused, playing }

  public private(set) var mode: Mode = .stopped
  public private(set) var rate: Double = 1.0
  public private(set) var duration: TimeInterval?
  /// 直近の通知の `t` − 受け入れ前の位置（診断用）。各呼び出しの先頭で `nil` に戻し、
  /// 受け入れた通知と、小さな後退を無視した通知で更新する。停止中に無視した通知と、
  /// シーク待ちで捨てた通知では `nil` のまま。
  public private(set) var lastNoteDelta: TimeInterval?

  private let seekSettleTolerance: TimeInterval
  private let seekSettleTimeout: TimeInterval
  private let backwardTolerance: TimeInterval
  private let discontinuityThreshold: TimeInterval

  private var anchorMedia: TimeInterval = 0
  private var anchorUptime: TimeInterval = 0
  private var pendingSeek: (target: TimeInterval, requestedAt: TimeInterval)?
  private var awaitingFirstNote = false

  public init(
    seekSettleTolerance: TimeInterval = 1.0,
    seekSettleTimeout: TimeInterval = 2.0,
    backwardTolerance: TimeInterval = 0.5,
    discontinuityThreshold: TimeInterval = 1.0
  ) {
    self.seekSettleTolerance = seekSettleTolerance
    self.seekSettleTimeout = seekSettleTimeout
    self.backwardTolerance = backwardTolerance
    self.discontinuityThreshold = discontinuityThreshold
  }

  /// 0 以下は不明扱い（長さの無い動画で libVLC が 0 や -1 を返す）。
  public mutating func setDuration(_ duration: TimeInterval?) {
    if let duration, duration > 0 {
      self.duration = duration
    } else {
      self.duration = nil
    }
  }

  /// libVLC の時刻通知を取り込む。位置が不連続に跳んだとき、または止まっていた位置から動き出す
  /// 通知を受け入れたときに `true` を返す（ロック画面の経過時間を直す合図）。
  @discardableResult
  public mutating func noteMediaTime(_ mediaTime: TimeInterval, at: TimeInterval) -> Bool {
    lastNoteDelta = nil
    // 判定の順：①停止中 ②シーク待ち ③最初の通知 ④一時停止中 ⑤再生中の通常の規則
    if mode == .stopped { return false }
    let current = position(at: at)
    let delta = mediaTime - current

    if let pendingSeek {
      guard abs(mediaTime - pendingSeek.target) <= seekSettleTolerance
        || at - pendingSeek.requestedAt >= seekSettleTimeout
      else {
        // シーク前に溜まっていた通知
        return false
      }
      adopt(mediaTime, at: at)
      lastNoteDelta = delta
      return true
    }
    if awaitingFirstNote {
      adopt(mediaTime, at: at)
      lastNoteDelta = delta
      return true
    }
    lastNoteDelta = delta
    if mode == .playing, delta < 0, -delta <= backwardTolerance {
      // 表示が一瞬戻るのを防ぐ。基準は変えない。
      return false
    }
    adopt(mediaTime, at: at)
    return abs(delta) > discontinuityThreshold
  }

  public mutating func play(at: TimeInterval) {
    // stateTransitions は同じ状態を2回通知し得る。基準を更新すると補間の進みが消えて位置が戻る。
    guard mode != .playing else { return }
    mode = .playing
    anchorUptime = at
    awaitingFirstNote = true
  }

  public mutating func pause(at: TimeInterval) {
    guard mode == .playing else { return }
    anchorMedia = position(at: at)
    mode = .paused
  }

  public mutating func stop() {
    mode = .stopped
    anchorMedia = 0
    pendingSeek = nil
    awaitingFirstNote = false
  }

  public mutating func seek(to target: TimeInterval, at: TimeInterval) {
    // 停止中に待ちを作ると、次の再生の通知を捨て続ける。
    guard mode != .stopped else { return }
    anchorMedia = min(max(target, 0), duration ?? .infinity)
    anchorUptime = at
    pendingSeek = (anchorMedia, at)
    awaitingFirstNote = false
  }

  public mutating func setRate(_ rate: Double, at: TimeInterval) {
    anchorMedia = position(at: at)
    anchorUptime = at
    self.rate = rate
  }

  public func position(at: TimeInterval) -> TimeInterval {
    let raw: TimeInterval
    switch mode {
    case .stopped:
      return 0
    case .paused:
      raw = anchorMedia
    case .playing:
      // 最初の通知までと、シーク先に着地するまでは進めない（先に進んでから戻るのを防ぐ）。
      if awaitingFirstNote || pendingSeek != nil {
        raw = anchorMedia
      } else {
        raw = anchorMedia + max(0, at - anchorUptime) * rate
      }
    }
    return max(0, min(raw, duration ?? .infinity))
  }

  private mutating func adopt(_ mediaTime: TimeInterval, at: TimeInterval) {
    anchorMedia = mediaTime
    anchorUptime = at
    pendingSeek = nil
    awaitingFirstNote = false
  }
}
