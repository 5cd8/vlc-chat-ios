import Testing
@testable import VLCChatCore

struct IntervalStatsTests {
  @Test func 空と1件ではnil() {
    var stats = IntervalStats()
    #expect(stats.snapshot(now: 0) == nil)
    stats.record(at: 1, mediaTime: 10)
    #expect(stats.snapshot(now: 1) == nil)
  }

  @Test func 最小平均最大をwallとmediaの両方で出す() throws {
    var stats = IntervalStats()
    stats.record(at: 0, mediaTime: 10)
    stats.record(at: 1, mediaTime: 12)
    stats.record(at: 3, mediaTime: 13)
    let snapshot = try #require(stats.snapshot(now: 3))
    #expect(snapshot.samples == 3)
    // wall の間隔は 1, 2
    #expect(snapshot.wall == .init(min: 1, avg: 1.5, max: 2))
    // media の間隔は 2, 1
    #expect(snapshot.media == .init(min: 1, avg: 1.5, max: 2))
  }

  @Test func 窓の境界は含まない() throws {
    var stats = IntervalStats()
    stats.record(at: 0, mediaTime: 0)
    stats.record(at: 10, mediaTime: 10)
    stats.record(at: 20, mediaTime: 20)
    // now - 30 = 0 なので at == 0 の記録は窓の外
    let outside = try #require(stats.snapshot(now: 30))
    #expect(outside.samples == 2)
    #expect(outside.wall == .init(min: 10, avg: 10, max: 10))
    // now - 30 = -0.5 なので at == 0 の記録は窓の中
    let inside = try #require(stats.snapshot(now: 29.5))
    #expect(inside.samples == 3)
  }

  @Test func 記録時に窓より古い記録を新しい記録を基準に捨てる() {
    var stats = IntervalStats()
    stats.record(at: 0, mediaTime: 0)
    stats.record(at: 1, mediaTime: 1)
    // 40 - 30 = 10 なので 0 と 1 は捨てられ、40 の1件だけが残る
    stats.record(at: 40, mediaTime: 40)
    #expect(stats.snapshot(now: 40) == nil)
  }

  @Test func 受信時刻が前回以前の入力は捨てる() throws {
    var stats = IntervalStats()
    stats.record(at: 10, mediaTime: 0)
    stats.record(at: 9, mediaTime: 1)
    stats.record(at: 10, mediaTime: 2)
    #expect(stats.snapshot(now: 10) == nil)
    stats.record(at: 11, mediaTime: 3)
    let snapshot = try #require(stats.snapshot(now: 11))
    #expect(snapshot.samples == 2)
    #expect(snapshot.wall == .init(min: 1, avg: 1, max: 1))
    // 捨てた入力のメディア時刻は使わない（3 - 0）
    #expect(snapshot.media == .init(min: 3, avg: 3, max: 3))
  }

  @Test func メディア時刻が戻ったら窓をリセットして新しい基準にする() throws {
    var stats = IntervalStats()
    stats.record(at: 0, mediaTime: 100)
    stats.record(at: 1, mediaTime: 101)
    stats.record(at: 2, mediaTime: 50)
    // 2 の1件だけが残る
    #expect(stats.snapshot(now: 2) == nil)
    stats.record(at: 3, mediaTime: 51)
    let snapshot = try #require(stats.snapshot(now: 3))
    #expect(snapshot.samples == 2)
    #expect(snapshot.wall == .init(min: 1, avg: 1, max: 1))
    #expect(snapshot.media == .init(min: 1, avg: 1, max: 1))
  }

  @Test func reset後0_5秒間の記録は捨てる() throws {
    var stats = IntervalStats()
    stats.record(at: 1, mediaTime: 1)
    stats.reset(at: 5)
    // reset で空になる
    #expect(stats.snapshot(now: 5) == nil)
    stats.record(at: 5.25, mediaTime: 0)
    stats.record(at: 5.375, mediaTime: 0)
    #expect(stats.snapshot(now: 5.375) == nil)
    // 5.5 - 5 == 0.5 は捨てない（0.5 未満が対象）
    stats.record(at: 5.5, mediaTime: 7)
    stats.record(at: 6.5, mediaTime: 8)
    let snapshot = try #require(stats.snapshot(now: 6.5))
    #expect(snapshot.samples == 2)
    #expect(snapshot.wall == .init(min: 1, avg: 1, max: 1))
  }
}
