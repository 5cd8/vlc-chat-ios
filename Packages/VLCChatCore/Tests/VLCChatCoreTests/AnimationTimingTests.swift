import Testing
@testable import VLCChatCore

/// 期待値は規則から手計算したもの。2進で正確に表せる値（0.25・0.5・0.9375）は `==` で、
/// それ以外（0.01・0.02・0.1・周期0.6）は `abs(a - b) < 1e-9` で比べる。
struct AnimationTimingTests {
  private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

  @Test("10ms以下は100msにし、それ以外はそのまま") func normalizesShortDelays() {
    #expect(near(AnimationTiming.normalizedDelay(0), 0.1))
    #expect(near(AnimationTiming.normalizedDelay(0.01), 0.1))  // 境界
    #expect(near(AnimationTiming.normalizedDelay(0.02), 0.02))
    #expect(near(AnimationTiming.normalizedDelay(0.1), 0.1))
  }

  @Test("読み取れない遅延（負・NaN）も100ms") func normalizesInvalidDelays() {
    #expect(near(AnimationTiming.normalizedDelay(-1), 0.1))
    #expect(near(AnimationTiming.normalizedDelay(.nan), 0.1))
  }

  @Test("時刻に対応するフレームを選ぶ（遅延 0.25・0.5・0.25）") func choosesFrameByTime() {
    let timing = AnimationTiming(rawDelays: [0.25, 0.5, 0.25])
    #expect(timing.loopDuration == 1.0)
    #expect(timing.frameIndex(at: 0) == 0)
    #expect(timing.frameIndex(at: 0.25) == 1)  // 境界ちょうどは次のフレーム
    #expect(timing.frameIndex(at: 0.5) == 1)
    #expect(timing.frameIndex(at: 0.75) == 2)
    #expect(timing.frameIndex(at: 0.9375) == 2)  // 周期の直前
    #expect(timing.frameIndex(at: 1.0) == 0)  // 1周して折り返す
    #expect(timing.frameIndex(at: 2.5) == 1)  // 2.5を1.0で割った余りは0.5
  }

  @Test("負・NaN・無限大の時刻は先頭フレーム") func invalidTimesChooseFirstFrame() {
    let timing = AnimationTiming(rawDelays: [0.25, 0.5, 0.25])
    #expect(timing.frameIndex(at: -1) == 0)
    #expect(timing.frameIndex(at: .nan) == 0)
    #expect(timing.frameIndex(at: .infinity) == 0)
  }

  @Test("遅延0は100msとして数える") func zeroDelayCountsAsHundredMilliseconds() {
    let timing = AnimationTiming(rawDelays: [0.0, 0.5])  // 正規化で [0.1, 0.5]
    #expect(near(timing.loopDuration, 0.6))
    #expect(timing.frameIndex(at: 0.1) == 1)
  }

  @Test("フレームが無ければ添字0・周期0") func emptyTiming() {
    let timing = AnimationTiming(rawDelays: [])
    #expect(timing.frameIndex(at: 5) == 0)
    #expect(timing.loopDuration == 0)
  }
}
