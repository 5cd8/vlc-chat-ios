import Testing
@testable import VLCChatCore

/// 時刻は2進で正確に表せる値（0.25・0.5・0.75）にして、しきい値0.45との大小がはっきりするようにしてある。
struct LongPressHoldTests {
  @Test("初期状態は止めておかない") func initialState() {
    let hold = LongPressHold()
    #expect(!hold.isHolding)
  }

  @Test("しきい値以上触れて離したら長押し（止めておく）") func longTouchHolds() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.touchEnded(at: 10.5)
    #expect(hold.isHolding)
  }

  @Test("しきい値より短く触れて離したら止めておかない") func shortTouchDoesNotHold() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.touchEnded(at: 10.25)
    #expect(!hold.isHolding)
  }

  @Test("長押しの後に短く触れて離すと、止めておくのをやめる（メニューを閉じるタップ）") func tapReleasesHold() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.touchEnded(at: 10.5)
    hold.touchBegan(at: 20)
    hold.touchEnded(at: 20.25)
    #expect(!hold.isHolding)
  }

  @Test("長押しの後に触れている間は、止めておいたまま") func holdsWhileNextTouchIsDown() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.touchEnded(at: 10.5)
    hold.touchBegan(at: 20)
    #expect(hold.isHolding)
  }

  @Test("長押しの後にスクロールを始めると、止めておくのをやめる") func scrollReleasesHold() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.touchEnded(at: 10.5)
    hold.scrollBegan()
    #expect(!hold.isHolding)
  }

  @Test("スクロールした後の idle では変わらない（触れた時刻が無い）") func endAfterScrollDoesNothing() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.scrollBegan()
    hold.touchEnded(at: 30)
    #expect(!hold.isHolding)
  }

  @Test("触れずに終わった通知では変わらない") func endWithoutTouchDoesNothing() {
    var hold = LongPressHold()
    hold.touchBegan(at: 10)
    hold.touchEnded(at: 10.5)
    hold.touchEnded(at: 99)
    #expect(hold.isHolding)
  }

  @Test("境界: しきい値ちょうどは長押し") func exactThresholdHolds() {
    var hold = LongPressHold()
    hold.touchBegan(at: 0)  // 0 からなら、差がしきい値そのものになる（足し引きの誤差が入らない）
    hold.touchEnded(at: LongPressHold.threshold)
    #expect(hold.isHolding)
  }
}
