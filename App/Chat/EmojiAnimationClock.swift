import Observation
import QuartzCore
import VLCChatCore

/// GIF絵文字のアニメの時計。動いている間だけ `time` が進む。
///
/// 動かすのは、ゲート（`EmojiAnimationGate`、`ChatPanelView` が渡す）が開いていて、かつ動かす行が
/// 1つ以上登録されているときだけ。GIFが画面に無いチャットで、主スレッドを毎秒60回起こし続けないため。
/// 追跡されるのは `time` だけ。画面外の行は `time` を読まないので、時計が進んでも再描画されない。
@Observable
@MainActor
final class EmojiAnimationClock {
  /// 動いていた時間の合計（秒）。止まっている間は変わらない。
  private(set) var time: TimeInterval = 0

  /// `CADisplayLink` が動いているか。診断ログが読む。
  var isRunning: Bool { runState.isRunning }
  /// 登録中の行の数。診断ログが読む。
  var demandCount: Int { runState.demand }

  @ObservationIgnored private var runState = AnimationRunState()
  @ObservationIgnored private var accumulator = AnimationClockAccumulator()
  @ObservationIgnored private var link: CADisplayLink?
  @ObservationIgnored private var ticker: Ticker?

  func setGateOpen(_ open: Bool) {
    apply(runState.setGateOpen(open))
  }

  /// 動かす行（見えていて、アニメ絵文字を含む）の登録。登録した行は、必ず `removeDemand` で解除する。
  func addDemand() {
    apply(runState.addDemand())
  }

  func removeDemand() {
    apply(runState.removeDemand())
  }

  private func apply(_ transition: AnimationRunState.Transition) {
    switch transition {
    case .none:
      break
    case .start:
      start()
    case .stop:
      stop()
    }
  }

  private func start() {
    guard link == nil else { return }
    let ticker = Ticker { [weak self] timestamp in self?.fire(timestamp: timestamp) }
    let link = CADisplayLink(target: ticker, selector: #selector(Ticker.fire(_:)))
    // GIFの遅延は中央値40ms。30Hzだと33msと67msが交互に出て不揃いに見えるので、60Hzを希望する。
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    self.ticker = ticker
    self.link = link
  }

  private func stop() {
    link?.invalidate()
    link = nil
    ticker = nil
    accumulator.pause()
  }

  private func fire(timestamp: CFTimeInterval) {
    accumulator.advance(to: timestamp)
    // 基準を取るだけの呼び出しでは代入しない（`@Observable` が同じ値の代入を通知するかに依存しないため）。
    if accumulator.time != time { time = accumulator.time }
  }
}

/// `CADisplayLink` は `NSObject` のターゲットを要るので、呼び出しをクロージャへ中継する。
/// `link.add(to: .main, ...)` なので、呼び出しはメインスレッド。
@MainActor
private final class Ticker: NSObject {
  private let onFire: (CFTimeInterval) -> Void

  init(onFire: @escaping (CFTimeInterval) -> Void) {
    self.onFire = onFire
  }

  @objc func fire(_ link: CADisplayLink) {
    onFire(link.timestamp)
  }
}
