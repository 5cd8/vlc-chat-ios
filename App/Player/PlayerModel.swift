import AVFoundation
import Observation
import SwiftVLC
import UIKit
import VLCChatCore

/// 再生・補間した現在位置・PiP・状態の監視。画面、ロック画面、PiPの窓の操作は、
/// すべてこのクラスの状態（`player.stateTransitions` と各操作）を通して一致させる。
@Observable
@MainActor
final class PlayerModel {
  private(set) var player: Player?
  private(set) var setupError: String?
  private(set) var libVLCVersion: String?
  private(set) var title: String?
  private(set) var rate: Double = PlaybackSpeed.normal
  private(set) var duration: TimeInterval?
  private(set) var openError: String?
  private(set) var pip: PiPController?
  /// 動画を開くのに成功するたびに増える（画面側の状態のリセット用）。
  private(set) var openCount = 0

  /// 再生/一時停止ボタンの表示用。一時停止の要求が処理中でも、画面が揃う。
  var isPlaybackRequestedActive: Bool { player?.isPlaybackRequestedActive ?? false }

  /// `AppModel` が後付けする（ロック画面の表示を更新するため）。
  @ObservationIgnored var remote: RemoteControlController?
  @ObservationIgnored private var clock = PlaybackClock()
  @ObservationIgnored private var currentFile: ScopedFile?
  @ObservationIgnored private var pipTask: Task<Void, Never>?
  @ObservationIgnored private var possibleTask: Task<Void, Never>?
  /// 中断・経路の消失の後は、音声出力が無音のまま残る（M1実機）。次に再生が始まるとき作り直す。
  @ObservationIgnored private var needsAudioRestart = false
  /// 中断の開始で、こちらが一時停止した。終了時に `shouldResume` なら再開する。
  @ObservationIgnored private var pausedByInterruption = false
  @ObservationIgnored private let diagnostics: DiagnosticsModel
  @ObservationIgnored private let audioSession: AudioSessionController

  init(diagnostics: DiagnosticsModel, audioSession: AudioSessionController) {
    self.diagnostics = diagnostics
    self.audioSession = audioSession

    // 失敗しても .shared に戻さない。アプリ管理のときに .shared へ触れると、
    // ライブラリ管理のインスタンスが生成されてしまう。
    do {
      let instance = try VLCInstance(appleAudioSessionPolicy: .applicationManaged)
      libVLCVersion = instance.version
      player = Player(instance: instance)
    } catch {
      setupError = "VLCInstance の作成に失敗: \(error)"
      AppLog.write(setupError ?? "")
    }
    startObserving()
    observeProtectedData()
    diagnostics.playbackStateText = { [weak self] in
      self?.player.map { "状態=\($0.state)" } ?? "状態=-"
    }
  }

  // MARK: - 開く

  func dismissOpenError() {
    openError = nil
  }

  func open(url: URL) {
    openError = nil
    guard let player else { return }
    let file = ScopedFile(url: url)
    let sizeMB = file.fileSizeBytes.map { String(format: "%.1fMB", Double($0) / 1_048_576) } ?? "不明"
    AppLog.write("選択 \(url.path) startAccessing=\(file.didStartAccess) サイズ=\(sizeMB)")

    guard SupportedVideo.isSupported(pathExtension: url.pathExtension) else {
      // 再生中の動画はそのままにする。
      reportOpenError("対応していない形式です")
      return
    }
    do {
      try audioSession.activate()
    } catch {
      reportOpenError("音声セッションの有効化に失敗: \(error)")
      return
    }
    do {
      try player.play(url: file.url)
    } catch {
      reportOpenError("再生開始に失敗: \(error)")
      // 差し替えに失敗しても古い動画は再生を続けるが、古い動画が外れた状態（.idle/.error）なら停止扱いにする。
      if player.state == .idle || player.state == .error {
        clock.stop()
        clock.setDuration(nil)
        duration = nil
        title = nil
        currentFile = nil
        syncClockState()
        remote?.update(nil)
      }
      return
    }
    // ここまで await を挟まないので、play(url:) の直後に届く状態の通知より前に実行される。
    title = SupportedVideo.title(fromFileName: url.lastPathComponent)
    clock.stop()
    clock.setDuration(nil)
    duration = nil
    // SwiftVLC は動画を差し替えても速度を引き継ぐので、1.0に戻す。
    try? player.setPlaybackRate(PlaybackRate(Float(PlaybackSpeed.normal)))
    clock.setRate(PlaybackSpeed.normal, at: now)
    diagnostics.resetTimeStats()
    // 再生中に差し替えたとき、状態が `.playing` のまま変わらず通知が来ない場合に備える。
    // 通知が来ても `clock.play(at:)` は冪等。
    if player.state == .playing { clock.play(at: now) }
    // 古いファイルのスコープは、新しい再生を始めてから解放する。
    currentFile = file
    // 前の動画での中断・経路の消失の後始末は、新しい動画には持ち越さない。
    needsAudioRestart = false
    pausedByInterruption = false
    openCount += 1
    syncClockState()
    updateRemote()
  }

  private func reportOpenError(_ message: String) {
    openError = message
    diagnostics.reportError(message)
  }

  // MARK: - 操作

  func togglePlayPause() {
    AppLog.write("操作 togglePlayPause")
    pausedByInterruption = false
    audioSession.activateLoggingFailure()
    player?.togglePlayPause()
  }

  /// ロック画面の再生。`togglePlayPause()` は、すでに再生中のときに一時停止してしまうため使わない。
  func play() {
    guard let player else { return }
    AppLog.write("操作 play")
    pausedByInterruption = false
    switch player.state {
    case .stopped, .idle:
      audioSession.activateLoggingFailure()
      try? player.play()
    case .stopping, .error:
      break
    default:
      guard !player.isPlaybackRequestedActive else { return }
      audioSession.activateLoggingFailure()
      player.resume()
    }
  }

  func pause() {
    // ユーザーが一時停止したので、中断明けに自動で再開しない。
    pausedByInterruption = false
    guard let player, player.isPlaybackRequestedActive else { return }
    AppLog.write("操作 pause")
    player.pause()
  }

  func skip(seconds: Int) {
    guard let player else { return }
    diagnostics.resetTimeStats()
    let accepted = player.jump(by: .seconds(seconds))
    AppLog.write("操作 jump(\(seconds)) 戻り値=\(accepted)")
    guard accepted else { return }
    let at = now
    clock.seek(to: clock.position(at: at) + Double(seconds), at: at)
    syncClockState()
    updateRemote()
  }

  func seek(toSeconds seconds: Double) {
    guard let player, let duration, duration > 0 else { return }
    diagnostics.resetTimeStats()
    do {
      try player.seek(to: PlaybackPosition(seconds / duration))
      AppLog.write("操作 seek \(String(format: "%.1f", seconds))s")
    } catch {
      AppLog.write("操作 seek 失敗: \(error)")
      return
    }
    clock.seek(to: seconds, at: now)
    syncClockState()
    updateRemote()
  }

  func setRate(_ speed: Double) {
    guard let player else { return }
    diagnostics.resetTimeStats()
    do {
      try player.setPlaybackRate(PlaybackRate(Float(speed)))
      AppLog.write("操作 setPlaybackRate(\(speed))")
    } catch {
      AppLog.write("操作 setPlaybackRate 失敗: \(error)")
      return
    }
    clock.setRate(speed, at: now)
    syncClockState()
    updateRemote()
  }

  /// 時計が停止中か（動画を開いた直後から再生が始まるまで、再生が終わった後）。停止中の `displayPosition` は0を返す。
  /// `clock` は監視されないので、この値を読むときはポーリングで毎回読む。
  var isClockStopped: Bool { clock.mode == .stopped }

  /// 補間した現在位置。UIの `TimelineView` が呼ぶ。
  func displayPosition(at uptime: TimeInterval) -> Double {
    clock.position(at: uptime)
  }

  // MARK: - 音声の中断

  /// 中断の開始では、アプリ管理の音声セッションだと SwiftVLC は一時停止しない
  /// （映像だけが進み、音声出力が止まる）。こちらで一時停止する。
  func audioDisruption(_ disruption: AudioSessionController.Disruption) {
    switch disruption {
    case .interruptionBegan:
      needsAudioRestart = true
      if let player, player.isPlaybackRequestedActive {
        pausedByInterruption = true
        AppLog.write("中断のため一時停止")
        player.pause()
      }
    case .interruptionEnded(let shouldResume):
      if shouldResume, pausedByInterruption {
        pausedByInterruption = false
        AppLog.write("中断が終わったので再開")
        play()
      }
    case .routeLost:
      // SwiftVLC が一時停止する。再開のときに音声出力を作り直す。
      needsAudioRestart = true
    }
  }

  /// 音声トラックの選択を外して付け直し、音声出力を作り直す。
  private func restartAudioOutput() {
    guard let player, let track = player.selectedAudioTrack else {
      AppLog.write("音声出力を再起動できない: 選択中の音声トラックなし")
      return
    }
    AppLog.write("音声出力を再起動")
    player.selectedAudioTrack = nil
    player.selectedAudioTrack = track
  }

  // MARK: - PiP

  func attachPiP(_ controller: PiPController?) {
    pipTask?.cancel()
    possibleTask?.cancel()
    pip = controller
    diagnostics.pipActive = controller?.isActive ?? false
    guard let controller else { return }
    AppLog.write("PiPController 取得 isPossible=\(controller.isPossible)")
    // 暫定: 動画を開き直すまでPiPが使えなくなる現象（自動PiPが起動しない）の切り分け用。
    // 可否が変わった時刻を残す。原因が分かったら、配線ごと消す。
    possibleTask = Task { [weak self, weak controller] in
      var last = controller?.isPossible
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, let controller else { return }
        if controller.isPossible != last {
          last = controller.isPossible
          AppLog.write("PiP可 変化 isPossible=\(controller.isPossible) \(self.stateDescription)")
        }
      }
    }
    pipTask = Task { [weak self] in
      for await envelope in controller.pipEventEnvelopes {
        guard let self else { return }
        let cause = envelope.stopCause.map(String.init(describing:)) ?? "-"
        AppLog.write("PiPイベント \(envelope.event) cause=\(cause)")
        self.diagnostics.pipActive = controller.isActive
      }
    }
  }

  func startPiP() {
    guard let pip else {
      AppLog.write("PiP toggle: PiPController なし")
      return
    }
    let result = pip.toggleReportingStartResult()
    let text = result.map(String.init(describing:)) ?? "停止した"
    AppLog.write("PiP toggle 結果=\(text) isPossible=\(pip.isPossible) isActive=\(pip.isActive)")
  }

  func sceneDidChange(isActive: Bool, name: String) {
    // ロック検知の通知はパスコード設定時にしか届かないので、前面復帰時の状態もここに残す。
    AppLog.write("画面 \(name) \(stateDescription) PiP可=\(pip?.isPossible ?? false)")
    diagnostics.scenePhaseName = name
    // 前面に戻ったときは、再生中なら画面を消さない状態に戻す。
    UIApplication.shared.isIdleTimerDisabled = isActive && player?.state == .playing
  }

  /// ログに添える「状態=… 時間=…」。
  var stateDescription: String {
    guard let player else { return "状態=-" }
    return "状態=\(player.state) 時間=\(String(format: "%.1f", clock.position(at: now)))s"
  }

  // MARK: - 状態の監視

  private func startObserving() {
    guard let player else { return }
    // 既定の events は .newest(64) で取りこぼし得るので、必要な種類だけを通す unbounded にする。
    let envelopes = player.eventEnvelopes(policy: .unbounded) { envelope in
      switch envelope.event {
      case .timeChanged, .lengthChanged, .voutChanged, .encounteredError: true
      default: false
      }
    }
    Task { [weak self] in
      for await envelope in envelopes {
        self?.handle(envelope)
      }
    }
    Task { [weak self] in
      for await state in player.stateTransitions {
        self?.stateDidChange(state)
      }
    }
  }

  private func handle(_ envelope: PlayerEventEnvelope) {
    // 前の動画の残りの通知が、新しい動画の位置を汚さないようにする。
    guard let player, envelope.playbackGeneration == player.generation else { return }
    switch envelope.event {
    case .timeChanged(let time):
      let seconds = Self.seconds(time)
      // 状態によらず時計に渡す。停止中は時計が無視し、一時停止中の通知は権威のある値として受け入れる。
      let jumped = clock.noteMediaTime(seconds, at: now)
      // 補間が先行する偏りを見るため、通常の規則の範囲の通知（跳びでも動き出しでもない）だけを集計する。
      // 一時停止中の通知の差は、一時停止が反映されるまでの遅れを表すので入れない。
      if !jumped, clock.mode == .playing { diagnostics.recordNoteDelta(clock.lastNoteDelta) }
      // 間隔の集計には、再生中の通知だけを入れる。
      if clock.mode == .playing { diagnostics.recordTime(mediaSeconds: seconds) }
      // PiPの窓のスキップなど、アプリを通らない位置の跳びを、ロック画面に反映する。
      if jumped { updateRemote() }
    case .lengthChanged(let length):
      clock.setDuration(Self.seconds(length))
      duration = clock.duration
      updateRemote()
    case .voutChanged(let count):
      AppLog.write("voutChanged \(count)")
    case .encounteredError:
      diagnostics.reportError("encounteredError")
    default:
      break
    }
  }

  private func stateDidChange(_ state: PlayerState) {
    // PiPの窓の再生/一時停止・スキップは、画面のボタンと違い「操作」の行を通らない。
    // 状態の変化がアプリの操作かPiP側の操作かを、ログから切り分けられるようPiPの有無を添える。
    AppLog.write("状態 \(state) PiP=\(pip?.isActive == true ? "表示中" : "なし")")
    UIApplication.shared.isIdleTimerDisabled = (state == .playing)

    switch state {
    case .opening, .buffering, .playing:
      // アプリ管理では、PiPの窓の再生操作や中断明けの再開は音声セッションを有効にしない。
      audioSession.activateLoggingFailure()
    default:
      break
    }
    if state == .playing {
      pausedByInterruption = false
      if needsAudioRestart {
        needsAudioRestart = false
        restartAudioOutput()
      }
    }
    switch state {
    case .playing:
      clock.play(at: now)
      // 一時停止・シークからの復帰で空白がmaxに入らないようにする。
      diagnostics.resetTimeStats()
    case .paused:
      clock.pause(at: now)
    case .stopped, .idle, .error:
      clock.stop()
    default:
      // .opening / .buffering / .stopping では時計を変えない。
      break
    }
    syncClockState()
    updateRemote()
  }

  private func observeProtectedData() {
    let center = NotificationCenter.default
    let names: [(Notification.Name, String)] = [
      (UIApplication.protectedDataWillBecomeUnavailableNotification, "ロックを検知(protectedDataWillBecomeUnavailable)"),
      (UIApplication.protectedDataDidBecomeAvailableNotification, "ロック解除を検知(protectedDataDidBecomeAvailable)")
    ]
    for (name, label) in names {
      Task { [weak self] in
        for await _ in center.notifications(named: name) {
          guard let self else { return }
          AppLog.write("\(label) \(self.stateDescription)")
        }
      }
    }
  }

  // MARK: - 内部

  private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  private func syncClockState() {
    rate = clock.rate
  }

  private func updateRemote() {
    remote?.update(NowPlayingState.make(title: title, clock: clock, at: now))
  }

  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
