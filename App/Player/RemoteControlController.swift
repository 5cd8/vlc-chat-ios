import Foundation
import MediaPlayer
import VLCChatCore

/// ロック画面・コントロールセンター・イヤホンの操作と、「再生中」の表示。
@MainActor
final class RemoteControlController {
  struct Handlers: Sendable {   // クロージャは @MainActor @Sendable（Sendableの警告を避ける）
    var play: @MainActor @Sendable () -> Void
    var pause: @MainActor @Sendable () -> Void
    var toggle: @MainActor @Sendable () -> Void
    /// 秒（負で戻る）
    var skip: @MainActor @Sendable (Int) -> Void
    /// 秒
    var seek: @MainActor @Sendable (Double) -> Void
    var next: @MainActor @Sendable () -> Void
    var previous: @MainActor @Sendable () -> Void
  }

  /// `AppModel` がアプリの生存期間中ずっと保持するので、`deinit` での `removeTarget` は書かない。
  private let tokens: [(command: MPRemoteCommand, token: Any)]

  init(handlers: Handlers) {
    tokens = Self.install(handlers: handlers)
    // 起動直後は、動画が無いので操作を無効にしておく。
    update(nil)
  }

  /// `nil` なら表示を消し、再生系と前へ・次へのコマンドを無効にする。
  func update(_ state: NowPlayingState?, canGoPrevious: Bool = false, canGoNext: Bool = false) {
    let center = MPNowPlayingInfoCenter.default()
    let commands = MPRemoteCommandCenter.shared()
    guard let state else {
      center.nowPlayingInfo = nil
      center.playbackState = .stopped
      setPlaybackCommands(enabled: false)
      commands.previousTrackCommand.isEnabled = false
      commands.nextTrackCommand.isEnabled = false
      return
    }
    commands.previousTrackCommand.isEnabled = canGoPrevious
    commands.nextTrackCommand.isEnabled = canGoNext
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: state.title,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsedForSystem,
      MPNowPlayingInfoPropertyPlaybackRate: state.rateForSystem,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
    ]
    if let duration = state.duration {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    center.nowPlayingInfo = info
    center.playbackState = state.isPlaying ? .playing : .paused
    setPlaybackCommands(enabled: true)
  }

  private func setPlaybackCommands(enabled: Bool) {
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = enabled
    commands.pauseCommand.isEnabled = enabled
    commands.togglePlayPauseCommand.isEnabled = enabled
    commands.skipForwardCommand.isEnabled = enabled
    commands.skipBackwardCommand.isEnabled = enabled
    commands.changePlaybackPositionCommand.isEnabled = enabled
  }

  /// ハンドラが呼ばれるスレッドの保証が無いので、nonisolated の文脈でクロージャを作り、
  /// `Task { @MainActor }` でメインアクターへ渡す（呼ばれるスレッドは、実機で確かめられるようログに出す）。
  private nonisolated static func install(handlers: Handlers) -> [(command: MPRemoteCommand, token: Any)] {
    let commands = MPRemoteCommandCenter.shared()
    var tokens: [(command: MPRemoteCommand, token: Any)] = []

    func add(_ command: MPRemoteCommand, name: String, _ run: @escaping @Sendable (MPRemoteCommandEvent) -> (@MainActor @Sendable () -> Void)?) {
      let token = command.addTarget { event in
        AppLog.write("操作 リモート \(name) main=\(Thread.isMainThread)")
        guard let action = run(event) else { return .commandFailed }
        Task { @MainActor in action() }
        return .success
      }
      tokens.append((command, token))
    }

    add(commands.playCommand, name: "play") { _ in handlers.play }
    add(commands.pauseCommand, name: "pause") { _ in handlers.pause }
    add(commands.togglePlayPauseCommand, name: "toggle") { _ in handlers.toggle }

    commands.skipForwardCommand.preferredIntervals = [10]
    commands.skipBackwardCommand.preferredIntervals = [10]
    // interval は、戻る側でも正の値で届く。
    add(commands.skipForwardCommand, name: "skipForward") { event in
      let seconds = Int((event as? MPSkipIntervalCommandEvent)?.interval ?? 10)
      return { handlers.skip(seconds) }
    }
    add(commands.skipBackwardCommand, name: "skipBackward") { event in
      let seconds = Int((event as? MPSkipIntervalCommandEvent)?.interval ?? 10)
      return { handlers.skip(-seconds) }
    }
    add(commands.changePlaybackPositionCommand, name: "changePlaybackPosition") { event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
      let position = event.positionTime
      return { handlers.seek(position) }
    }

    // 前へ・次への有効・無効は `update` が決める。10秒送り・戻しと両立しない端末では、
    // 10秒送り・戻しを優先する（ユーザー確定）ので、`skipForward`／`skipBackward` は無効にしない。
    add(commands.nextTrackCommand, name: "nextTrack") { _ in handlers.next }
    add(commands.previousTrackCommand, name: "previousTrack") { _ in handlers.previous }
    // 早送り・早戻しは使わない。
    commands.seekForwardCommand.isEnabled = false
    commands.seekBackwardCommand.isEnabled = false
    return tokens
  }
}
