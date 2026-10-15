import AVFoundation

/// アプリ管理の音声セッション。
///
/// `VLCInstance(appleAudioSessionPolicy: .applicationManaged)` のとき、SwiftVLCもlibVLCも
/// `AVAudioSession` を有効化せず、中断明けにも再有効化しない。再生を始める・再開する前に、
/// このクラスで有効化する。
@MainActor
final class AudioSessionController {
  /// 音声の中断・経路の消失。`AppModel` が `PlayerModel` に結ぶ。
  enum Disruption {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// 有線・Bluetoothのイヤホンが外れた（`oldDeviceUnavailable`）
    case routeLost
  }

  /// 中断のログに添える再生状態。`AppModel` が結ぶ。
  var stateDescription: @MainActor () -> String = { "-" }
  var onDisruption: @MainActor (Disruption) -> Void = { _ in }

  private var observationTask: Task<Void, Never>?
  private var routeTask: Task<Void, Never>?

  func activate() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .moviePlayback)
    try session.setActive(true)
  }

  func activateLoggingFailure() {
    do {
      try activate()
    } catch {
      AppLog.write("音声セッションの有効化に失敗: \(error)")
    }
  }

  /// 中断の開始・終了をログに書き、終了のときに有効化し直す。監視はここ1か所だけ（二重に登録しない）。
  func startObservingInterruptions() {
    guard observationTask == nil else { return }
    observationTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
        guard let self else { return }
        let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let label: String
        switch rawType {
        case AVAudioSession.InterruptionType.began.rawValue: label = "began"
        case AVAudioSession.InterruptionType.ended.rawValue: label = "ended"
        default: label = "不明"
        }
        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
        if rawType == AVAudioSession.InterruptionType.ended.rawValue {
          self.activateLoggingFailure()
        }
        AppLog.write("音声セッションの中断 \(label) shouldResume=\(shouldResume) 状態=\(self.stateDescription())")
        switch rawType {
        case AVAudioSession.InterruptionType.began.rawValue: self.onDisruption(.interruptionBegan)
        case AVAudioSession.InterruptionType.ended.rawValue: self.onDisruption(.interruptionEnded(shouldResume: shouldResume))
        default: break
        }
      }
    }
    routeTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
        guard let self else { return }
        let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        AppLog.write("音声経路の変更 reason=\(reason.map { "\($0)" } ?? "不明") 状態=\(self.stateDescription())")
        if reason == .oldDeviceUnavailable { self.onDisruption(.routeLost) }
      }
    }
  }
}
