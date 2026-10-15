import Foundation
import Observation
import VLCChatCore

/// アプリ全体のモデルを束ねる。
@Observable
@MainActor
final class AppModel {
  /// SwiftVLC のバージョン。`libVLC` の版（`instance.version`）とは別物。
  static let swiftVLCVersion = "1.1.0-beta.14"

  let diagnostics: DiagnosticsModel
  let playback: PlayerModel
  let remote: RemoteControlController
  let chat = ChatModel()
  let emoji = EmojiStore()
  private let audioSession: AudioSessionController

  /// 利用者に知らせる通知の待ち行列（動画を開けなかった理由は `playback.openError` が別に持つ）。
  private(set) var notices: [String] = []

  /// 画面の確認ダイアログに出す文言。動画を開けなかった理由を先に、次に通知を1件ずつ出す。
  var alertMessage: String? { playback.openError ?? notices.first }

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
    audioSession.onDisruption = { [weak playback] disruption in playback?.audioDisruption(disruption) }

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

  /// 表示中の1件だけを消す。続きがあれば、次の1件が出る。
  func dismissAlert() {
    if playback.openError != nil {
      playback.dismissOpenError()
    } else if !notices.isEmpty {
      notices.removeFirst()
    }
  }

  /// 「ファイルを選択」の結果を、種類ごとに振り分ける。
  /// 動画を先に開いてからチャットを読む（動画を開き直すとチャットは外れるため）。
  func handlePicked(urls: [URL]) {
    var videoURL: URL?
    var chatURL: URL?
    var emojiURL: URL?
    var hasUnsupported = false
    for url in urls {
      switch PickedFileKind.classify(pathExtension: url.pathExtension) {
      case .video:
        if videoURL == nil {
          videoURL = url
        } else {
          // プレイリストはM3。複数選んだときは最初の1つだけを開く。
          AppLog.write("選択 動画 2つ目以降は開かない \(url.lastPathComponent)")
        }
      case .chat:
        if chatURL == nil { chatURL = url }
      case .emojiLibrary:
        if emojiURL == nil { emojiURL = url }
      case .unsupported:
        hasUnsupported = true
        AppLog.write("選択 未対応 \(url.path)")
      }
    }
    if hasUnsupported { notices.append("対応していない形式です") }

    var videoFailed = false
    if let videoURL {
      let before = playback.openCount
      playback.open(url: videoURL)
      let opened = playback.openCount != before
      videoFailed = !opened
      // 開けたら前のチャットを外す。差し替えに失敗して古い動画も外れたときは、チャット欄も消えるので外す。
      if opened || playback.title == nil { chat.reset() }
    }

    if let chatURL, !videoFailed {
      if playback.title == nil {
        notices.append("先に動画を開いてください")
      } else {
        AppLog.write("選択 チャット \(chatURL.path)")
        chat.load(url: chatURL)
      }
    }

    if let emojiURL {
      AppLog.write("選択 絵文字ライブラリ \(emojiURL.path)")
      Task {
        do {
          try await emoji.importLibrary(from: emojiURL)
        } catch {
          notices.append("絵文字ライブラリを読み込めませんでした")
        }
      }
    }
  }
}
