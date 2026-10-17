import Testing
@testable import VLCChatCore

/// 期待値は規則から手計算したもの。0.0625刻みは2進で正確に表せるので `==` で比べる。
/// 各テストは、新しい `AnimationClockAccumulator()` から始める。
struct AnimationClockAccumulatorTests {
  @Test("最初の呼び出しは基準を取るだけ") func firstCallOnlyTakesBaseline() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 10)
    #expect(clock.time == 0)
  }

  @Test("差を足していく") func accumulatesDeltas() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 10)
    clock.advance(to: 10.0625)
    #expect(clock.time == 0.0625)
    clock.advance(to: 10.125)
    #expect(clock.time == 0.125)
  }

  @Test("大きな差は maxStep（既定0.1）で切る") func clampsLargeDelta() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 10)
    clock.advance(to: 10.5)
    #expect(clock.time == 0.1)
  }

  @Test("maxStep を渡せる") func customMaxStep() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 10)
    clock.advance(to: 10.5, maxStep: 0.25)
    #expect(clock.time == 0.25)
  }

  @Test("止めた後の最初の呼び出しは基準を取り直すだけ") func pauseRebases() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 10)
    clock.advance(to: 10.0625)
    clock.pause()
    clock.advance(to: 100)
    #expect(clock.time == 0.0625)
    clock.advance(to: 100.0625)
    #expect(clock.time == 0.125)
  }

  @Test("時刻が逆戻りしても進めない") func ignoresBackwardTime() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 20)
    clock.advance(to: 19)
    #expect(clock.time == 0)
    clock.advance(to: 19.0625)
    #expect(clock.time == 0.0625)
  }

  @Test("同じ時刻が2回来ても進めない") func ignoresRepeatedTimestamp() {
    var clock = AnimationClockAccumulator()
    clock.advance(to: 10)
    clock.advance(to: 10.0625)
    clock.advance(to: 10.0625)
    #expect(clock.time == 0.0625)
  }
}
