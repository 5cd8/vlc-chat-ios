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
  /// 保存済みの再生位置を引く（`AppModel` が配線する）。
  @ObservationIgnored var resumeLookup: ((VideoIdentity) -> TimeInterval?)?
  @ObservationIgnored var positionRecorder: ((VideoIdentity, TimeInterval) -> Void)?
  /// 最後まで再生した（`endReached`）。
  @ObservationIgnored var onEnded: ((VideoIdentity?) -> Void)?
  /// PiP中の先行切り替えを行う条件（自動進行が有効で、次の動画がある）。`AppModel` が配線する。
  @ObservationIgnored var earlyAdvanceEnabled: (() -> Bool)?
  /// 終端の手前に達した。呼び出し側が、記憶の削除と次の動画への切り替えを行う。
  @ObservationIgnored var onEarlyAdvance: ((VideoIdentity?) -> Void)?
  /// 同じ動画で先行切り替えを一度だけ行うための印。残りが閾値の2倍を超えて戻る（シーク）と下ろす。
  @ObservationIgnored private var earlyAdvanceFired = false
  @ObservationIgnored private var earlyAdvanceTask: Task<Void, Never>?
  /// ロック画面の前へ・次への有効・無効。
  @ObservationIgnored var navigationState: (() -> (canGoPrevious: Bool, canGoNext: Bool))?
  /// 開いた動画の識別（名前＋サイズ）。サイズが取れなければ nil＝記憶しない。
  @ObservationIgnored private var currentIdentity: VideoIdentity?
  @ObservationIgnored private var savedPosition: TimeInterval?
  /// 復元が済んだ（またはしないと決まった）。
  @ObservationIgnored private var restoreCompleted = true
  /// 最初の `.playing` になった時刻（systemUptime）。
  @ObservationIgnored private var playingSince: TimeInterval?
  /// `player.isSeekable` は読まない。内部値の更新とイベント配送の順が保証されないため、イベントの値を使う。
  @ObservationIgnored private var isSeekable = false
  @ObservationIgnored private var hasReachedEnd = false
  @ObservationIgnored private var recordTask: Task<Void, Never>?
  /// 直近の映像トラックの要約（コーデック・解像度・fps）。PiPが使える動画と使えない動画を、映像の特性で
  /// 突き合わせるための暫定の診断（Issue #12 第1段階）。対策の効果を確かめた後の別PRで、配線ごと消す。
  @ObservationIgnored private var videoSummary = "-"
  @ObservationIgnored private var clock = PlaybackClock()
  @ObservationIgnored private var currentFile: ScopedFile?
  @ObservationIgnored private var pipTask: Task<Void, Never>?
  @ObservationIgnored private var possibleTask: Task<Void, Never>?
  /// 暫定の診断（Issue #12 第2段階）。差し替えのたびに、SwiftVLCがPiPを保てたか（restored）、
  /// 保てなかったか（timedOut）を残す。対策の効果を確かめた後の別PRで、配線ごと消す。
  @ObservationIgnored private var continuityTask: Task<Void, Never>?
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
    // 再生中は5秒ごとに位置を記録する。
    recordTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self else { return }
        if self.clock.mode == .playing { self.recordPosition() }
      }
    }
    earlyAdvanceTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(50))
        guard let self else { return }
        self.checkEarlyAdvance()
      }
    }
  }

  // MARK: - 開く

  func dismissOpenError() {
    openError = nil
  }

  func open(url: URL) {
    openError = nil
    guard let player else { return }
    // 別の動画に替える前に、今の動画の位置を残す。
    recordPosition()
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
        resetAfterDetach()
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
    // 記憶の状態を初期化する（`recordPosition()` を呼んだ後に `hasReachedEnd` を下ろす）。
    currentIdentity = file.fileSizeBytes.map { VideoIdentity(fileName: url.lastPathComponent, size: Int64($0)) }
    savedPosition = currentIdentity.flatMap { resumeLookup?($0) }
    restoreCompleted = savedPosition == nil
    videoSummary = "-"
    playingSince = nil
    isSeekable = false
    hasReachedEnd = false
    earlyAdvanceFired = false
    // 再生中に差し替えたとき、状態が `.playing` のまま変わらず通知が来ない場合に備える。
    // 通知が来ても `clock.play(at:)` は冪等。
    if player.state == .playing {
      clock.play(at: now)
      playingSince = now
    }
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

  /// `true` は「受け付けられた」であって「その位置に着地した」ではない。
  @discardableResult
  func seek(toSeconds seconds: Double) -> Bool {
    guard let player, let duration, duration > 0 else { return false }
    diagnostics.resetTimeStats()
    do {
      try player.seek(to: PlaybackPosition(seconds / duration))
      AppLog.write("操作 seek \(String(format: "%.1f", seconds))s")
    } catch {
      AppLog.write("操作 seek 失敗: \(error)")
      return false
    }
    clock.seek(to: seconds, at: now)
    syncClockState()
    updateRemote()
    return true
  }

  // MARK: - 停止

  /// 動画は残して停止する（M1の「終端で停止して先頭に戻る」状態）。
  func stopKeepingTitle() {
    recordPosition()
    player?.stop()
    clock.stop()
    syncClockState()
    updateRemote()
  }

  /// 動画を閉じる。チャット欄は `AppModel` 側で空にする。
  func stop() {
    recordPosition()
    player?.stop()
    resetAfterDetach()
  }

  /// ロック画面の前へ・次への有効・無効を更新する。
  func refreshRemote() {
    updateRemote()
  }

  private func resetAfterDetach() {
    clock.stop()
    clock.setDuration(nil)
    duration = nil
    title = nil
    currentFile = nil
    currentIdentity = nil
    savedPosition = nil
    restoreCompleted = true
    videoSummary = "-"
    syncClockState()
    remote?.update(nil)
  }

  /// 映像トラックの要約を求め、前回と違えばログに残す。
  /// `.tracksChanged`／`.voutChanged` を受けた時点で、SwiftVLC内部の `videoTracks` が更新済みとは限らない
  /// （`play(url:)` は一度空にする）ので、読む直前に `refreshTracks()` で読み直す。
  private func refreshVideoSummary(trigger: String) {
    guard let player else { return }
    player.refreshTracks()
    let tracks = player.videoTracks
    let summary =
      tracks.isEmpty
      ? "なし"
      : tracks.map { track in
        let codec = track.codecString ?? "?"
        let width = track.width.map(String.init) ?? "?"
        let height = track.height.map(String.init) ?? "?"
        let fps = track.frameRate.map { String(format: "%.2f", $0) } ?? "?"
        return "\(track.isSelected ? "*" : "")\(codec) \(width)x\(height) \(fps)fps"
      }.joined(separator: " / ")
    guard summary != videoSummary else { return }
    videoSummary = summary
    AppLog.write("映像 トラック \(summary) 契機=\(trigger)")
  }

  // MARK: - 先行切り替え

  /// PiP中だけ、終端の手前で次へ進む。終端ではlibVLCが映像出力を壊し、`endReached` を待つとPiPが止まる。
  /// 前面（PiPでない）では従来どおり `endReached` で進める（音声の最後を削らないため）。
  private func checkEarlyAdvance() {
    guard clock.mode == .playing, player?.state == .playing, let duration = clock.duration else { return }
    let at = now
    let position = clock.position(at: at)
    let remaining = duration - position
    // シークで戻ったときの再発火のため。この判定は発火済みの条件より先に置く。
    if earlyAdvanceFired, EarlyAdvanceRule.shouldRearm(position: position, duration: duration, rate: clock.rate) {
      earlyAdvanceFired = false
      hasReachedEnd = false
    }
    guard !earlyAdvanceFired, pip?.isActive == true, earlyAdvanceEnabled?() == true,
      EarlyAdvanceRule.shouldAdvance(position: position, duration: duration, rate: clock.rate)
    else { return }
    earlyAdvanceFired = true
    // 記憶は残さない（終端の位置を再開位置にしない）。`endReached` と同じ扱い。
    hasReachedEnd = true
    AppLog.write(
      String(format: "先行切り替え 残り=%.2fs（実時間） ", remaining / max(clock.rate, 0.01)) + (title ?? "-"))
    onEarlyAdvance?(currentIdentity)
  }

  /// 次へ進んだ後にPiPが使えなくなっているか（開き直しの対象か）。
  /// 前面かつ再生中に限る。背面やPiPの起動待ちでは開き直さない。
  func needsPiPRecovery() -> Bool {
    guard let pip, !pip.isActive, !pip.isPossible, player?.state == .playing else { return false }
    return diagnostics.scenePhaseName == "active"
  }

  /// 開き直しの判定を延ばすか（再生の準備中）。
  var needsPlaybackWait: Bool {
    guard let state = player?.state else { return false }
    return state == .opening || state == .buffering
  }

  var isPiPPossible: Bool { pip?.isPossible ?? false }

  // MARK: - 再生位置の記憶

  func recordPosition() {
    guard let identity = currentIdentity, let positionRecorder else { return }
    expireRestoreIfTimedOut()
    let at = now
    let pending = ResumeRules.isResumePending(
      secondsSincePlaying: playingSince.map { at - $0 }, restoreCompleted: restoreCompleted)
    guard
      ResumeRules.shouldRecord(
        position: clock.position(at: at), isClockStopped: clock.mode == .stopped,
        isResumePending: pending, hasReachedEnd: hasReachedEnd)
    else { return }
    positionRecorder(identity, clock.position(at: at))
  }

  /// 再生が始まり、長さが確定し、シークできるようになってから、絶対位置へシークする。
  /// `:start-time` は使わない（タイムラインが切り詰められ、表示の位置・長さがずれる）。
  /// 復元待ちの5秒を過ぎたら、復元はしないと決める。決めないと、停止後に再生ボタンで再開したとき
  /// `playingSince` が立ち直り、古い位置へ再びシークしてしまう。
  private func expireRestoreIfTimedOut() {
    guard !restoreCompleted, let since = playingSince,
      !ResumeRules.isResumePending(secondsSincePlaying: now - since, restoreCompleted: false)
    else { return }
    restoreCompleted = true
    savedPosition = nil
  }

  private func tryRestore() {
    expireRestoreIfTimedOut()
    guard !restoreCompleted, clock.mode == .playing, isSeekable, let duration, duration > 0,
      let since = playingSince,
      ResumeRules.isResumePending(secondsSincePlaying: now - since, restoreCompleted: false)
    else { return }
    guard let target = ResumeRules.startPosition(saved: savedPosition, duration: duration) else {
      restoreCompleted = true
      return
    }
    if seek(toSeconds: target) {
      restoreCompleted = true
      AppLog.write("記憶 復元 \(title ?? "-") \(String(format: "%.1f", target))s")
    }
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
    continuityTask?.cancel()
    pip = controller
    diagnostics.pipActive = controller?.isActive ?? false
    guard let controller else { return }
    AppLog.write("PiPController 取得 isPossible=\(controller.isPossible)")
    // 暫定: 動画を開き直すまでPiPが使えなくなる現象（自動PiPが起動しない）の切り分け用。
    // 可否が変わった時刻を残す。対策の効果を確かめた後の別PRで、配線ごと消す。
    possibleTask = Task { [weak self, weak controller] in
      var last = controller?.isPossible
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, let controller else { return }
        if controller.isPossible != last {
          last = controller.isPossible
          AppLog.write(
            "PiP可 変化 isPossible=\(controller.isPossible) \(self.stateDescription) 映像=\(self.videoSummary)")
        }
      }
    }
    // `self` を捕まえない（ログを書くだけ）。
    continuityTask = Task {
      for await event in controller.pipContinuityEvents {
        AppLog.write(
          "PiP継続 \(event.outcome) 経過=\(event.elapsed) 前世代=\(event.previousMediaGeneration) "
            + "後世代=\(event.mediaGeneration) 制御世代=\(event.controllerGeneration)")
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

  /// 開き直しの結果のログ用（Issue #12 の暫定の診断）。
  var pipStatusText: String {
    "isPossible=\(pip?.isPossible ?? false) isActive=\(pip?.isActive ?? false) \(stateDescription)"
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
    if !isActive { recordPosition() }
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
      case .timeChanged, .lengthChanged, .voutChanged, .encounteredError, .seekableChanged, .endReached,
        .tracksChanged: true
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
      tryRestore()
    case .lengthChanged(let length):
      clock.setDuration(Self.seconds(length))
      duration = clock.duration
      updateRemote()
      tryRestore()
    case .seekableChanged(let seekable):
      isSeekable = seekable
      tryRestore()
    case .endReached:
      hasReachedEnd = true
      AppLog.write("再生 終了 \(title ?? "-")")
      onEnded?(currentIdentity)
    case .voutChanged(let count):
      AppLog.write("voutChanged \(count)")
      if count > 0 { refreshVideoSummary(trigger: "voutChanged") }
    case .tracksChanged:
      // 音声の選択変更（`restartAudioOutput()` など）でも届くが、同じ要約はログに出ない。
      refreshVideoSummary(trigger: "tracksChanged")
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
    // 再生中に差し替えると、`open` の時点で立てた `playingSince` が本当の再生開始より早い。
    // 開くのに時間がかかる動画で復元待ちの5秒を使い切らないよう、開き直しの通知で数え直す。
    if (state == .opening || state == .stopped) && !restoreCompleted { playingSince = nil }

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
      if playingSince == nil { playingSince = now }
      hasReachedEnd = false
      tryRestore()
      // 一時停止・シークからの復帰で空白がmaxに入らないようにする。
      diagnostics.resetTimeStats()
    case .paused:
      clock.pause(at: now)
      recordPosition()
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
    let navigation = navigationState?() ?? (canGoPrevious: false, canGoNext: false)
    remote?.update(
      NowPlayingState.make(title: title, clock: clock, at: now),
      canGoPrevious: navigation.canGoPrevious, canGoNext: navigation.canGoNext)
  }

  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
