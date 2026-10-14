import Foundation
import Observation
import VLCChatCore

@Observable
@MainActor
final class DiagnosticsModel {
  /// 外れ値としてログに出す、`.timeChanged` の受信間隔（秒）
  private static let outlierInterval: TimeInterval = 1.0

  private(set) var footprintMB: Double?
  private(set) var timeStats: IntervalStats.Snapshot?
  private(set) var lastError: String?
  var pipActive = false
  /// 「build … / SwiftVLC … / libVLC …」。`AppModel` が起動時に作って渡す。
  var versionText = "—"

  @ObservationIgnored private var stats = IntervalStats()
  @ObservationIgnored private var lastTimeReceivedAt: TimeInterval?
  @ObservationIgnored private var noteDeltaMin: Double?
  @ObservationIgnored private var noteDeltaMax: Double?
  @ObservationIgnored private var timerTask: Task<Void, Never>?

  /// 1秒ごとの計測と、60秒ごとのログを始める。
  func start() {
    guard timerTask == nil else { return }
    timerTask = Task { [weak self] in
      var tick = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        tick += 1
        self.timeStats = self.stats.snapshot(now: ProcessInfo.processInfo.systemUptime)
        self.footprintMB = MemoryProbe.physFootprintMB()
        if tick % 60 == 0 { self.writePeriodicLog() }
      }
    }
  }

  func reportError(_ message: String) {
    lastError = message
    AppLog.write("エラー \(message)")
  }

  /// 再生中の `.timeChanged` の受信を記録する。
  func recordTime(mediaSeconds: TimeInterval) {
    let now = ProcessInfo.processInfo.systemUptime
    if let last = lastTimeReceivedAt, now - last > Self.outlierInterval {
      AppLog.write(String(format: "timeChanged 外れ値 受信間隔=%.3fs", now - last))
    }
    lastTimeReceivedAt = now
    stats.record(at: now, mediaTime: mediaSeconds)
  }

  /// 一時停止・シーク・速度変更などをまたいだ空白が、集計や外れ値に入らないようにする。
  func resetTimeStats() {
    stats.reset(at: ProcessInfo.processInfo.systemUptime)
    lastTimeReceivedAt = nil
    timeStats = nil
  }

  /// 補間位置と通知の差。時計が先行する偏りの大きさを見る（60秒ごとにログへ）。
  func recordNoteDelta(_ delta: Double?) {
    guard let delta else { return }
    noteDeltaMin = min(noteDeltaMin ?? delta, delta)
    noteDeltaMax = max(noteDeltaMax ?? delta, delta)
  }

  private func writePeriodicLog() {
    if let footprintMB {
      AppLog.write(String(format: "phys_footprint %.1fMB", footprintMB))
    }
    // 画面を見られない長時間の再生でも、timeChanged間隔の数値が残るようにする。
    if let timeStats {
      AppLog.write("timeChanged間隔 \(timeStats.summaryText)")
    }
    if let noteDeltaMin, let noteDeltaMax {
      AppLog.write(String(format: "補間ずれ min=%.3fs max=%.3fs", noteDeltaMin, noteDeltaMax))
      self.noteDeltaMin = nil
      self.noteDeltaMax = nil
    }
  }
}

extension IntervalStats.Snapshot {
  /// 受信時刻の差とメディア時刻の差の min/avg/max（ミリ秒）と、窓内の記録件数。
  var summaryText: String {
    func ms(_ stat: IntervalStats.Stat) -> String {
      String(format: "%.0f/%.0f/%.0f ms", stat.min * 1000, stat.avg * 1000, stat.max * 1000)
    }
    return "受信(min/avg/max) \(ms(wall)) メディア \(ms(media)) n=\(samples)"
  }
}
