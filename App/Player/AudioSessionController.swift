import AVFoundation

/// アプリ管理の音声セッション。
///
/// `VLCInstance(appleAudioSessionPolicy: .applicationManaged)` のとき、SwiftVLCもlibVLCも
/// `AVAudioSession` を有効化せず、中断明けにも再有効化しない。再生を始める・再開する前に、
/// このクラスで有効化する。
@MainActor
final class AudioSessionController {
  /// 中断のログに添える再生状態。`AppModel` が結ぶ。
  var stateDescription: @MainActor () -> String = { "-" }

  private var observationTask: Task<Void, Never>?

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
        if rawType == AVAudioSession.InterruptionType.ended.rawValue {
          self.activateLoggingFailure()
        }
        AppLog.write("音声セッションの中断 \(label) 状態=\(self.stateDescription())")
      }
    }
  }
}
