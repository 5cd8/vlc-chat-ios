import SwiftUI
import VLCChatCore

/// 再生・シーク・速度・PiP の操作パネル。
struct ControlsView: View {
  let model: PlayerModel
  let playlist: PlaylistModel
  let onPickFile: () -> Void
  let onShowPlaylist: () -> Void
  let onShowSettings: () -> Void
  let onPrevious: () -> Void
  let onNext: () -> Void
  @State private var isScrubbing = false
  @State private var scrubPosition = 0.0
  @State private var shownPosition = 0.0
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(spacing: 12) {
      seekBar
      HStack(spacing: 24) {
        Button(action: onPrevious) { Image(systemName: "backward.end.fill").font(.title2) }
          .disabled(!playlist.playlist.hasPrevious)
          .accessibilityLabel("前の項目")
        Button { model.skip(seconds: -10) } label: { Image(systemName: "gobackward.10").font(.title) }
          .accessibilityLabel("10秒戻る")
        Button { model.togglePlayPause() } label: {
          Image(systemName: model.isPlaybackRequestedActive ? "pause.fill" : "play.fill").font(.largeTitle)
        }
        .accessibilityLabel(model.isPlaybackRequestedActive ? "一時停止" : "再生")
        Button { model.skip(seconds: 10) } label: { Image(systemName: "goforward.10").font(.title) }
          .accessibilityLabel("10秒進む")
        Button(action: onNext) { Image(systemName: "forward.end.fill").font(.title2) }
          .disabled(!playlist.playlist.hasNext)
          .accessibilityLabel("次の項目")
      }
      HStack {
        Button("ファイルを選択", action: onPickFile)
        Button(action: onShowPlaylist) { Image(systemName: "list.bullet") }
          .accessibilityLabel("プレイリスト")
        Spacer()
        Menu {
          ForEach(PlaybackSpeed.steps, id: \.self) { speed in
            Button(PlaybackSpeed.label(speed)) { model.setRate(speed) }
          }
        } label: {
          Text(PlaybackSpeed.label(model.rate))
        }
        .accessibilityLabel("再生速度 \(PlaybackSpeed.label(model.rate))")
        Button { model.startPiP() } label: { Image(systemName: "pip.enter") }
          .accessibilityLabel("ピクチャインピクチャ")
        Button(action: onShowSettings) { Image(systemName: "gearshape") }
          .accessibilityLabel("設定")
      }
      .buttonStyle(.bordered)
    }
    .padding(12)
  }

  /// 現在位置とシークバーは、補間した位置を0.1秒ごとに描く（一時停止中・停止中も動かし続けて、
  /// 一時停止中のシークや停止の反映が次の刻みで画面に出るようにする）。
  /// `TimelineView` の中に `Slider` を置くと、毎回作り直されてつまみを離した通知
  /// （`onEditingChanged(false)`）が届かず、`isScrubbing` が真のまま表示が止まった（M1実機）。
  /// そのため `Slider` は安定した位置に置き、位置は `.task` で `@State` に流し込む。
  private var seekBar: some View {
    let duration = model.duration
    return VStack(spacing: 2) {
      Slider(
        value: Binding(
          get: { isScrubbing ? scrubPosition : shownPosition },
          set: { scrubPosition = $0 }
        ),
        in: 0...(duration ?? 1)
      ) { editing in
        isScrubbing = editing
        // つまみを掴んだ瞬間に、現在位置から動き出すようにする。
        if editing { scrubPosition = shownPosition }
        // 離したとき1回だけシークする。
        if !editing {
          shownPosition = scrubPosition
          model.seek(toSeconds: scrubPosition)
        }
      }
      .disabled(duration == nil)
      .accessibilityLabel("シークバー")
      HStack {
        Text(Self.format(isScrubbing ? scrubPosition : shownPosition))
        Spacer()
        Text(duration.map(Self.format) ?? "--:--")
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
    // 背面では画面が見えないので回さない（再描画が背面の負荷を押し上げないように）。
    // inactive（コントロールセンターなどを開いている間）は画面が見えるので回す。
    .task(id: scenePhase) {
      guard scenePhase != .background else { return }
      while !Task.isCancelled {
        if !isScrubbing {
          shownPosition = model.displayPosition(at: ProcessInfo.processInfo.systemUptime)
        }
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
    // 動画を開き直したら、つまみを掴んだままの状態が残らないようにする。
    .onChange(of: model.openCount) { isScrubbing = false }
  }

  static func format(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, secs)
      : String(format: "%d:%02d", minutes, secs)
  }
}
