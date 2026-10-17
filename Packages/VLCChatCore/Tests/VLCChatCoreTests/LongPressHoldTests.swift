import Testing
@testable import VLCChatCore

/// 各テストは、新しい `LongPressHold()` から始める。
struct LongPressHoldTests {
  @Test("初期状態は止めておかない") func initialState() {
    let hold = LongPressHold()
    #expect(!hold.isHolding)
  }

  @Test("触れただけでは止めておかない") func touchAloneDoesNotHold() {
    var hold = LongPressHold()
    hold.touchBegan()
    #expect(!hold.isHolding)
  }

  @Test("長押しが認識されたら止めておく") func recognizedLongPressHolds() {
    var hold = LongPressHold()
    hold.touchBegan()
    hold.longPressRecognized()
    #expect(hold.isHolding)
  }

  @Test("指を離しても（通知が無いので）止めておいたまま") func holdsAfterRelease() {
    var hold = LongPressHold()
    hold.touchBegan()
    hold.longPressRecognized()
    // 指を離したことは通知されない。次に触れるまで変わらない。
    #expect(hold.isHolding)
  }

  @Test("次に触れたら止めておくのをやめる（メニューを閉じるタップ）") func nextTouchReleasesHold() {
    var hold = LongPressHold()
    hold.touchBegan()
    hold.longPressRecognized()
    hold.touchBegan()
    #expect(!hold.isHolding)
  }

  @Test("次の長押しでまた止めておく") func secondLongPressHoldsAgain() {
    var hold = LongPressHold()
    hold.touchBegan()
    hold.longPressRecognized()
    hold.touchBegan()
    hold.longPressRecognized()
    #expect(hold.isHolding)
  }
}
