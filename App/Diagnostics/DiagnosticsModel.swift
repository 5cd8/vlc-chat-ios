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
  /// 最後に通知された `scenePhase`（"active" / "inactive" / "background"）。負荷のログに添える。
  var scenePhaseName = "active"
  /// 負荷のログに添える再生状態。`PlayerModel` が結ぶ。
  @ObservationIgnored var playbackStateText: @MainActor () -> String = { "-" }
  /// 負荷のログに添えるGIF絵文字のアニメの状態（動作中／停止と、動かす行の数）。`AppModel` が結ぶ。
  @ObservationIgnored var animationStateText: @MainActor () -> String = { "GIF=-" }
  /// 「build … / SwiftVLC … / libVLC …」。`AppModel` が起動時に作って渡す。
  var versionText = "—"

  @ObservationIgnored private var stats = IntervalStats()
  @ObservationIgnored private var lastTimeReceivedAt: TimeInterval?
  @ObservationIgnored private var noteDeltaMin: Double?
  @ObservationIgnored private var noteDeltaMax: Double?
  @ObservationIgnored private var timerTask: Task<Void, Never>?
  @ObservationIgnored private var lastLoadSampleAt: TimeInterval?
  @ObservationIgnored private var lastLoadCPUSeconds: Double?

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
        if tick % 20 == 0 { self.writeLoadLog() }
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

  /// 場面（前面・PiP・背面）ごとの負荷を比べるための、20秒ごとのログ（恒久的に残す。
  /// 背面で映像のデコードを止める改善の効果も、このログで確かめる）。
  /// CPUは直近の20秒間の平均で、1コア分を100%とする（複数コアを使うと100%を超える）。
  private func writeLoadLog() {
    let now = ProcessInfo.processInfo.systemUptime
    let cpu = CPUProbe.processCPUSeconds()
    defer {
      lastLoadSampleAt = now
      lastLoadCPUSeconds = cpu
    }
    guard let lastAt = lastLoadSampleAt, let lastCPU = lastLoadCPUSeconds, now > lastAt else { return }
    let percent = (cpu - lastCPU) / (now - lastAt) * 100
    let scene = pipActive ? "PiP" : (scenePhaseName == "background" ? "背面" : (scenePhaseName == "active" ? "前面" : "inactive"))
    let thermal: String
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: thermal = "nominal"
    case .fair: thermal = "fair"
    case .serious: thermal = "serious"
    case .critical: thermal = "critical"
    @unknown default: thermal = "不明"
    }
    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? " 低電力モード" : ""
    AppLog.write(
      String(
        format: "負荷 CPU=%.0f%% 熱=%@%@ 場面=%@ %@ %@", percent, thermal, lowPower, scene, playbackStateText(),
        animationStateText()))
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
