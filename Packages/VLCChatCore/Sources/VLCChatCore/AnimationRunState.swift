/// 時計を動かすかどうか: ゲート（`EmojiAnimationGate`）が開いていて、動かす行が1つ以上ある。
/// 状態が変わったときだけ、動かす／止めるの遷移を返す。
public struct AnimationRunState: Equatable, Sendable {
  public enum Transition: Equatable, Sendable {
    case none
    case start
    case stop
  }

  public private(set) var gateOpen = false
  /// 動かす行の数。
  public private(set) var demand = 0
  public var isRunning: Bool { gateOpen && demand > 0 }

  public init() {}

  @discardableResult
  public mutating func setGateOpen(_ open: Bool) -> Transition {
    apply { $0.gateOpen = open }
  }

  @discardableResult
  public mutating func addDemand() -> Transition {
    apply { $0.demand += 1 }
  }

  /// `demand` が0のときは何もしない（負にならない）。
  @discardableResult
  public mutating func removeDemand() -> Transition {
    apply { if $0.demand > 0 { $0.demand -= 1 } }
  }

  private mutating func apply(_ change: (inout AnimationRunState) -> Void) -> Transition {
    let wasRunning = isRunning
    change(&self)
    switch (wasRunning, isRunning) {
    case (false, true): return .start
    case (true, false): return .stop
    default: return .none
    }
  }
}
