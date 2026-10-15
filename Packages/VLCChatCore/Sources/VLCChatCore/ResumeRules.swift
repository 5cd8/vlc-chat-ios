import Foundation

/// 再生位置の記憶の規則。
public enum ResumeRules {
  /// 終わりからこの秒数以内まで見ていたら、先頭から再生する。
  public static let endMargin: TimeInterval = 30
  /// これ未満の位置は、記録も復元もしない。先頭近く（1秒未満）まで戻して別の動画へ移ると
  /// 古い位置が残り、次に開いたときそこから再生される。先頭付近を記録しないための意図した挙動。
  public static let minimumPosition: TimeInterval = 1
  /// 再生開始からこの秒数を過ぎたら、復元待ちでも記録を始める。
  /// 復元できない動画（長さ不明・シーク不可）で、記録が永久に止まらないようにする。
  public static let pendingTimeout: TimeInterval = 5

  /// 復元する位置。nil なら先頭から再生する。
  public static func startPosition(saved: TimeInterval?, duration: TimeInterval?) -> TimeInterval? {
    guard let saved, saved >= minimumPosition else { return nil }
    // 長さ不明では復元しない（シークに長さが要る）。
    guard let duration, duration > 0 else { return nil }
    guard saved < duration, duration - saved > endMargin else { return nil }
    return saved
  }

  /// 復元待ちか。`secondsSincePlaying` は最初の `.playing` からの秒数（まだ再生していなければ nil）。
  public static func isResumePending(secondsSincePlaying: TimeInterval?, restoreCompleted: Bool) -> Bool {
    if restoreCompleted { return false }
    guard let secondsSincePlaying else { return true }
    return secondsSincePlaying < pendingTimeout
  }

  /// 記録してよいか。
  public static func shouldRecord(
    position: TimeInterval, isClockStopped: Bool, isResumePending: Bool, hasReachedEnd: Bool
  ) -> Bool {
    position >= minimumPosition && !isClockStopped && !isResumePending && !hasReachedEnd
  }
}
