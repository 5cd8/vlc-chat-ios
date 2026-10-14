import Foundation
import Observation

/// アプリ全体のモデルを束ねる。
@Observable
@MainActor
final class AppModel {
  /// SwiftVLC のバージョン。`libVLC` の版（`instance.version`）とは別物。
  static let swiftVLCVersion = "1.1.0-beta.14"

  let diagnostics: DiagnosticsModel
  let playback: PlayerModel
  let remote: RemoteControlController
  private let audioSession: AudioSessionController

  init() {
    // 生成の順序（循環を避ける）：診断と音声セッション → 再生 → ロック画面 → 後付けの参照 → 開始。
    let diagnostics = DiagnosticsModel()
    let audioSession = AudioSessionController()
    let playback = PlayerModel(diagnostics: diagnostics, audioSession: audioSession)
    let remote = RemoteControlController(
      handlers: .init(
        play: { [weak playback] in playback?.play() },
        pause: { [weak playback] in playback?.pause() },
        toggle: { [weak playback] in playback?.togglePlayPause() },
        skip: { [weak playback] seconds in playback?.skip(seconds: seconds) },
        seek: { [weak playback] seconds in playback?.seek(toSeconds: seconds) }
      )
    )
    playback.remote = remote
    audioSession.stateDescription = { [weak playback] in playback?.stateDescription ?? "状態=-" }

    self.diagnostics = diagnostics
    self.playback = playback
    self.remote = remote
    self.audioSession = audioSession

    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    let libVLC = playback.libVLCVersion ?? "—"
    diagnostics.versionText = "build \(build) / SwiftVLC \(Self.swiftVLCVersion) / libVLC \(libVLC)"
    AppLog.write("起動 build=\(build) SwiftVLC=\(Self.swiftVLCVersion) libVLC=\(libVLC)")

    audioSession.startObservingInterruptions()
    diagnostics.start()
  }
}
