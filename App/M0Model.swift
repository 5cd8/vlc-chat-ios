import AVFoundation
import Observation
import SwiftVLC
import UIKit
import VLCChatCore

/// SwiftVLC の音声セッションの方針。`VLCInstance` の不変の属性なので、切り替えは次の起動から有効になる。
enum AudioPolicyChoice: String, CaseIterable {
  case library
  case application

  var label: String {
    switch self {
    case .library: "ライブラリ管理"
    case .application: "アプリ管理"
    }
  }

  static let defaultsKey = "audioPolicy"

  static var saved: AudioPolicyChoice {
    UserDefaults.standard.string(forKey: defaultsKey).flatMap(AudioPolicyChoice.init) ?? .library
  }
}

/// ブックマークを解決した結果の表示用。
struct BookmarkReport: Identifiable {
  let variant: BookmarkVariant
  var summary: String
  var id: String { variant.rawValue }
}

@Observable
@MainActor
final class M0Model {
  /// SwiftVLC のバージョン。`libVLC` の版（`instance.version`）とは別物。
  static let swiftVLCVersion = "1.1.0-beta.14"

  /// 外れ値としてログに出す、`.timeChanged` の受信間隔（秒）
  private static let outlierInterval: TimeInterval = 1.0

  let launchPolicy = AudioPolicyChoice.saved
  private(set) var player: Player?
  private(set) var setupError: String?
  private(set) var libVLCVersion = "—"

  // 選択・再生
  private(set) var pickSummary = "—"
  private(set) var timeToPlaySummary = "—"
  private(set) var playError: String?
  private(set) var bookmarkReports: [BookmarkReport] = []

  // 計測
  private(set) var timeStats: IntervalStats.Snapshot?
  private(set) var footprintMB: Double?
  private(set) var pipSummary = "—"
  private(set) var pipStartResult = "—"
  private(set) var isPlayerReady = false

  private(set) var pip: PiPController?

  @ObservationIgnored private var instance: VLCInstance?
  @ObservationIgnored private var currentFile: ScopedFile?
  @ObservationIgnored private var stats = IntervalStats()
  @ObservationIgnored private var lastTimeReceivedAt: TimeInterval?
  @ObservationIgnored private var pickReturnedAt: TimeInterval?
  @ObservationIgnored private var pipTask: Task<Void, Never>?
  @ObservationIgnored private let log = DiagnosticsLog.shared

  init() {
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    log.write("起動 build=\(appVersion) SwiftVLC=\(Self.swiftVLCVersion) 音声セッション方針=\(launchPolicy.label)")

    // 失敗しても .shared に戻さない。チェック4の結果を汚さないため。
    // アプリ管理のときに .shared へ触れると、ライブラリ管理のインスタンスが生成されてしまう。
    do {
      switch launchPolicy {
      case .library:
        instance = VLCInstance.shared
      case .application:
        instance = try VLCInstance(appleAudioSessionPolicy: .applicationManaged)
      }
    } catch {
      setupError = "VLCInstance の作成に失敗: \(error)"
      log.write(setupError ?? "")
    }
    if let instance {
      libVLCVersion = instance.version
      player = Player(instance: instance)
      isPlayerReady = true
    }

    reportBookmarks()
    startObserving()
  }

  // MARK: - 選択

  /// ピッカー（`fileImporter` か `UIDocumentPickerViewController`）がURLを返したとき。
  func didPick(url: URL, source: String) {
    pickReturnedAt = ProcessInfo.processInfo.systemUptime
    let file = ScopedFile(url: url)
    let sizeMB = file.fileSizeBytes.map { String(format: "%.1fMB", Double($0) / 1_048_576) } ?? "不明"
    let summary = "\(source): \(url.path)\nコンテナ内=\(file.isInsideAppContainer) startAccessing=\(file.didStartAccess) サイズ=\(sizeMB)"
    pickSummary = summary
    log.write("選択 \(summary.replacingOccurrences(of: "\n", with: " "))")

    play(file)
    // 作成に時間がかかっても、再生開始までの時間(経路の比較用)に入らないよう再生の後に行う。
    if file.didStartAccess {
      for variant in BookmarkVariant.allCases {
        do {
          try variant.save(for: file)
        } catch {
          log.write("ブックマーク作成失敗 \(variant.label): \(error)")
        }
      }
    } else {
      log.write("ブックマークを作らない: startAccessing=false")
    }
  }

  func didFailToPick(_ error: Error, source: String) {
    log.write("選択失敗 \(source): \(error)")
    pickSummary = "\(source): 失敗 \(error.localizedDescription)"
  }

  func playBookmark(_ variant: BookmarkVariant) {
    guard let result = variant.resolve() else {
      pickSummary = "ブックマーク(\(variant.label)): 保存なし"
      return
    }
    switch result {
    case .success(let resolved):
      let file = ScopedFile(url: resolved.url)
      pickSummary = "ブックマーク(\(variant.label)): \(resolved.url.path)\nisStale=\(resolved.isStale) startAccessing=\(file.didStartAccess)"
      log.write("ブックマーク再生 \(pickSummary.replacingOccurrences(of: "\n", with: " "))")
      pickReturnedAt = ProcessInfo.processInfo.systemUptime
      play(file)
    case .failure(let error):
      pickSummary = "ブックマーク(\(variant.label)): 解決失敗 \(error.localizedDescription)"
      log.write(pickSummary)
    }
  }

  private func play(_ file: ScopedFile) {
    guard let player else { return }
    playError = nil
    timeToPlaySummary = "—"
    resetStats()
    do {
      try activateAudioSessionIfAppManaged()
      try player.play(url: file.url)
      // 古いファイルのスコープは、新しい再生を始めてから解放する。
      currentFile = file
    } catch {
      playError = "\(error)"
      pickReturnedAt = nil
      log.write("再生開始失敗: \(error)")
    }
  }

  // MARK: - 音声セッション（アプリ管理のとき）

  /// アプリ管理では SwiftVLC が音声セッションを有効化しない（中断明けも再有効化しない）ので、
  /// 再生を始める・再開する前に自分で有効化する。ライブラリ管理では何もしない。
  private func activateAudioSessionIfAppManaged() throws {
    guard launchPolicy == .application else { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .moviePlayback)
    try session.setActive(true)
  }

  private func activateAudioSessionIfAppManagedLoggingFailure() {
    do {
      try activateAudioSessionIfAppManaged()
    } catch {
      log.write("音声セッションの有効化に失敗: \(error)")
    }
  }

  // MARK: - 操作

  func togglePlayPause() {
    log.write("操作 togglePlayPause")
    activateAudioSessionIfAppManagedLoggingFailure()
    player?.togglePlayPause()
  }

  func jump(seconds: Int) {
    guard let player else { return }
    resetStats()
    let accepted = player.jump(by: .seconds(seconds))
    log.write("操作 jump(\(seconds)) 戻り値=\(accepted)")
  }

  func seek(fraction: Double) {
    guard let player else { return }
    resetStats()
    do {
      try player.seek(to: PlaybackPosition(fraction))
      log.write("操作 seek fraction=\(fraction)")
    } catch {
      log.write("操作 seek 失敗: \(error)")
    }
  }

  func setRate(_ rate: PlaybackRate) {
    guard let player else { return }
    resetStats()
    do {
      try player.setPlaybackRate(rate)
      log.write("操作 setPlaybackRate(\(rate.rawValue))")
    } catch {
      log.write("操作 setPlaybackRate 失敗: \(error)")
    }
  }

  func setAudioPolicy(_ choice: AudioPolicyChoice) {
    UserDefaults.standard.set(choice.rawValue, forKey: AudioPolicyChoice.defaultsKey)
    log.write("音声セッション方針を保存 \(choice.label)（次の起動から有効）")
  }

  // MARK: - PiP

  func attachPiP(_ controller: PiPController?) {
    pipTask?.cancel()
    pip = controller
    guard let controller else { return }
    log.write("PiPController 取得 isPossible=\(controller.isPossible)")
    pipTask = Task { [weak self] in
      for await envelope in controller.pipEventEnvelopes {
        guard let self else { return }
        let text = "\(envelope.event) cause=\(envelope.stopCause.map(String.init(describing:)) ?? "-")"
        self.pipSummary = text
        self.log.write("PiPイベント \(text)")
      }
    }
  }

  func startPiP() {
    guard let pip else {
      pipStartResult = "PiPController なし"
      return
    }
    let result = pip.toggleReportingStartResult()
    pipStartResult = result.map(String.init(describing:)) ?? "停止した"
    log.write("PiP toggle 結果=\(pipStartResult) isPossible=\(pip.isPossible) isActive=\(pip.isActive)")
  }

  // MARK: - 情報パネル

  var fraction: Double {
    guard let player, let duration = player.duration, Self.seconds(duration) > 0 else { return 0 }
    return min(max(Self.seconds(player.currentTime) / Self.seconds(duration), 0), 1)
  }

  var trackSummary: String {
    guard let player else { return "—" }
    let video = player.videoTracks.map { "\($0.codecString ?? "不明") \($0.width ?? 0)x\($0.height ?? 0)" }
    let audio = player.audioTracks.map { "\($0.codecString ?? "不明")" }
    return "映像: \(video.isEmpty ? "なし" : video.joined(separator: ", "))\n音声: \(audio.isEmpty ? "なし" : audio.joined(separator: ", "))"
  }

  var appVersionText: String {
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "build \(build) / SwiftVLC \(Self.swiftVLCVersion) / libVLC \(libVLCVersion)"
  }

  func sceneDidChange(isActive: Bool, name: String) {
    // ロック検知の通知はパスコード設定時にしか届かないので、前面復帰時の状態もここに残す。
    let state = player.map { "\($0.state) 時間=\($0.currentTime.formatted)" } ?? "-"
    log.write("画面 \(name) 状態=\(state)")
    // 前面に戻ったときは、再生中なら画面を消さない状態に戻す。
    UIApplication.shared.isIdleTimerDisabled = isActive && player?.state == .playing
  }

  // MARK: - 内部

  private func resetStats() {
    stats.reset(at: ProcessInfo.processInfo.systemUptime)
    lastTimeReceivedAt = nil
    timeStats = nil
  }

  private func recordTime(_ time: Duration) {
    guard player?.state == .playing else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if let last = lastTimeReceivedAt, now - last > Self.outlierInterval {
      log.write(String(format: "timeChanged 外れ値 受信間隔=%.3fs", now - last))
    }
    lastTimeReceivedAt = now
    stats.record(at: now, mediaTime: Self.seconds(time))
  }

  private func reportBookmarks() {
    bookmarkReports = BookmarkVariant.allCases.map { variant in
      guard let result = variant.resolve() else {
        return BookmarkReport(variant: variant, summary: "保存なし")
      }
      switch result {
      case .success(let resolved):
        let file = ScopedFile(url: resolved.url)
        let summary = "\(resolved.url.path)\nisStale=\(resolved.isStale) startAccessing=\(file.didStartAccess)"
        log.write("ブックマーク解決 \(variant.label) \(summary.replacingOccurrences(of: "\n", with: " "))")
        return BookmarkReport(variant: variant, summary: summary)
      case .failure(let error):
        log.write("ブックマーク解決失敗 \(variant.label): \(error)")
        return BookmarkReport(variant: variant, summary: "解決失敗 \(error.localizedDescription)")
      }
    }
  }

  private func startObserving() {
    if let player {
      // 既定の events は .newest(64) で取りこぼし得るので、必要な3種だけを通す unbounded にする。
      let events = player.events(policy: .unbounded) { event in
        switch event {
        case .timeChanged, .voutChanged, .encounteredError: true
        default: false
        }
      }
      Task { [weak self] in
        for await event in events {
          switch event {
          case .timeChanged(let time):
            self?.recordTime(time)
          case .voutChanged(let count):
            self?.log.write("voutChanged \(count)")
          case .encounteredError:
            self?.log.write("encounteredError")
          default:
            break
          }
        }
      }
      Task { [weak self] in
        for await state in player.stateTransitions {
          self?.stateDidChange(state)
        }
      }
    }
    Task { [weak self] in
      var tick = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        tick += 1
        self.timeStats = self.stats.snapshot(now: ProcessInfo.processInfo.systemUptime)
        self.footprintMB = DiagnosticsLog.physFootprintMB()
        if tick % 60 == 0 {
          if let mb = self.footprintMB {
            self.log.write(String(format: "phys_footprint %.1fMB", mb))
          }
          // 画面を見られない長時間の再生でも、C（timeChanged間隔）の数値が残るようにする。
          if let snapshot = self.timeStats {
            self.log.write("timeChanged間隔 \(snapshot.summaryText)")
          }
        }
      }
    }
    observeSystemNotifications()
  }

  private func stateDidChange(_ state: PlayerState) {
    log.write("状態 \(state)")
    UIApplication.shared.isIdleTimerDisabled = (state == .playing)
    // 一時停止などをまたいだ空白が、再開直後の外れ値として記録されないようにする。
    if state != .playing { lastTimeReceivedAt = nil }
    if state == .playing {
      // 一時停止・シークからの復帰で空白がmaxに入らないようにする。
      resetStats()
      if let returned = pickReturnedAt {
        let text = String(format: "%.3fs", ProcessInfo.processInfo.systemUptime - returned)
        timeToPlaySummary = text
        log.write("再生開始までの時間 \(text)")
        pickReturnedAt = nil
      }
    }
  }

  private func observeSystemNotifications() {
    let center = NotificationCenter.default
    let names: [(Notification.Name, String)] = [
      (UIApplication.protectedDataWillBecomeUnavailableNotification, "ロックを検知(protectedDataWillBecomeUnavailable)"),
      (UIApplication.protectedDataDidBecomeAvailableNotification, "ロック解除を検知(protectedDataDidBecomeAvailable)"),
      (AVAudioSession.interruptionNotification, "音声セッションの中断")
    ]
    for (name, label) in names {
      Task { [weak self] in
        for await notification in center.notifications(named: name) {
          let detail = notification.userInfo?[AVAudioSessionInterruptionTypeKey].map { " type=\($0)" } ?? ""
          let interruptionType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
          if interruptionType == AVAudioSession.InterruptionType.ended.rawValue {
            self?.activateAudioSessionIfAppManagedLoggingFailure()
          }
          let state = self?.player?.state
          self?.log.write("\(label)\(detail) 状態=\(state.map(String.init(describing:)) ?? "-")")
        }
      }
    }
  }

  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
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
