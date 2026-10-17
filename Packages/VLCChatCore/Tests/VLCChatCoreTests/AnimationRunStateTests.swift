import Testing
@testable import VLCChatCore

/// 各テストは、新しい `AnimationRunState()` から始める。
/// 変更を伴う呼び出しの結果は、いったん定数に受けてから比べる（`#expect` の中で状態を変えない）。
struct AnimationRunStateTests {
  @Test("初期状態は止まっている") func initialState() {
    let state = AnimationRunState()
    #expect(!state.isRunning)
    #expect(!state.gateOpen)
    #expect(state.demand == 0)
  }

  @Test("ゲートが閉じたままの登録では動かず、開けると動く") func gateOpensAfterDemand() {
    var state = AnimationRunState()
    let added = state.addDemand()
    #expect(added == .none)
    #expect(!state.isRunning)
    let opened = state.setGateOpen(true)
    #expect(opened == .start)
    #expect(state.isRunning)
  }

  @Test("開けただけでは動かず、最初の登録で動く") func firstDemandStarts() {
    var state = AnimationRunState()
    let opened = state.setGateOpen(true)  // demand が 0
    #expect(opened == .none)
    let first = state.addDemand()
    #expect(first == .start)
    let second = state.addDemand()
    #expect(second == .none)
    #expect(state.demand == 2)
  }

  @Test("最後の解除で止まる") func lastRemovalStops() {
    var state = AnimationRunState()
    state.setGateOpen(true)
    state.addDemand()
    state.addDemand()
    let first = state.removeDemand()
    #expect(first == .none)
    #expect(state.demand == 1)
    let last = state.removeDemand()
    #expect(last == .stop)
    #expect(state.demand == 0)
  }

  @Test("登録が0のときの解除は何もしない（負にならない）") func removingAtZeroDoesNothing() {
    var state = AnimationRunState()
    let closed = state.removeDemand()
    #expect(closed == .none)
    #expect(state.demand == 0)
    state.setGateOpen(true)
    let open = state.removeDemand()
    #expect(open == .none)
    #expect(state.demand == 0)
  }

  @Test("ゲートを閉じると止まる") func closingGateStops() {
    var state = AnimationRunState()
    state.setGateOpen(true)
    let started = state.addDemand()
    #expect(started == .start)
    let closed = state.setGateOpen(false)
    #expect(closed == .stop)
    let closedAgain = state.setGateOpen(false)
    #expect(closedAgain == .none)
  }

  @Test("同じ値のゲートは何もしない") func sameGateValueDoesNothing() {
    var state = AnimationRunState()
    state.setGateOpen(true)
    let started = state.addDemand()
    #expect(started == .start)
    let openedAgain = state.setGateOpen(true)
    #expect(openedAgain == .none)
  }

  @Test("止めた後にゲートを開けると、また動く（PiPや背面からの復帰）") func resumesWhenGateReopens() {
    var state = AnimationRunState()
    state.setGateOpen(true)
    state.addDemand()
    let closed = state.setGateOpen(false)
    #expect(closed == .stop)
    let reopened = state.setGateOpen(true)
    #expect(reopened == .start)
  }

  @Test("ゲートが閉じている間の増減では遷移しない") func demandChangesWhileGateClosed() {
    var state = AnimationRunState()
    let first = state.addDemand()
    let second = state.addDemand()
    let removed = state.removeDemand()
    #expect(first == .none)
    #expect(second == .none)
    #expect(removed == .none)
    #expect(state.demand == 1)
    let opened = state.setGateOpen(true)
    #expect(opened == .start)
  }
}
