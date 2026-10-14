import Foundation

/// 通知の到着間隔（受信時刻の差）とメディア時刻の差の、直近の窓での最小・平均・最大。
///
/// 時計は内部に持たない。`at` には `ProcessInfo.processInfo.systemUptime` など単調増加の秒を、
/// 呼び出し側が渡す。
public struct IntervalStats: Sendable {
  public struct Stat: Equatable, Sendable {
    public let min: TimeInterval
    public let avg: TimeInterval
    public let max: TimeInterval
  }

  public struct Snapshot: Equatable, Sendable {
    /// 受信時刻の差
    public let wall: Stat
    /// メディア時刻の差
    public let media: Stat
    /// 窓内の記録件数。間隔の数は `samples - 1`
    public let samples: Int
  }

  private struct Record {
    let at: TimeInterval
    let mediaTime: TimeInterval
  }

  private let window: TimeInterval
  private let discardAfterReset: TimeInterval
  private var records: [Record] = []
  private var lastResetAt: TimeInterval?

  public init(window: TimeInterval = 30, discardAfterReset: TimeInterval = 0.5) {
    self.window = window
    self.discardAfterReset = discardAfterReset
  }

  public mutating func record(at: TimeInterval, mediaTime: TimeInterval) {
    // シーク直後は、シーク前に溜まっていた通知が reset の後に届く。その分を捨てる。
    if let lastResetAt, at - lastResetAt < discardAfterReset { return }
    if let last = records.last {
      // 受信時刻が逆行した（同値も含む）入力は、その1件を捨てる。
      if at <= last.at { return }
      // アプリを経由しない後方シーク（PiPのスキップなど）。捨てると元の位置を追い越すまで
      // 全件が捨てられるので、新しい基準にして窓をリセットする。
      if mediaTime < last.mediaTime { records.removeAll() }
    }
    records.append(Record(at: at, mediaTime: mediaTime))
    records.removeAll { $0.at <= at - window }
  }

  /// 窓は `at > now - window` の記録（境界は含まない）。窓内に2件未満なら `nil`。
  public func snapshot(now: TimeInterval) -> Snapshot? {
    let inWindow = records.filter { $0.at > now - window }
    guard inWindow.count >= 2 else { return nil }
    let pairs = zip(inWindow, inWindow.dropFirst())
    return Snapshot(
      wall: Self.stat(pairs.map { $1.at - $0.at }),
      media: Self.stat(pairs.map { $1.mediaTime - $0.mediaTime }),
      samples: inWindow.count
    )
  }

  public mutating func reset(at: TimeInterval) {
    records.removeAll()
    lastResetAt = at
  }

  private static func stat(_ intervals: [TimeInterval]) -> Stat {
    Stat(
      min: intervals.min() ?? 0,
      avg: intervals.reduce(0, +) / Double(intervals.count),
      max: intervals.max() ?? 0
    )
  }
}
