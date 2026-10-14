import SwiftUI
import VLCChatCore

/// 再生・シーク・速度・PiP の操作パネル。
struct ControlsView: View {
  let model: PlayerModel
  let onPickFile: () -> Void
  @State private var isScrubbing = false
  @State private var scrubPosition = 0.0

  var body: some View {
    VStack(spacing: 12) {
      seekBar
      HStack(spacing: 28) {
        Button { model.skip(seconds: -10) } label: { Image(systemName: "gobackward.10").font(.title) }
          .accessibilityLabel("10秒戻る")
        Button { model.togglePlayPause() } label: {
          Image(systemName: model.isPlaybackRequestedActive ? "pause.fill" : "play.fill").font(.largeTitle)
        }
        .accessibilityLabel(model.isPlaybackRequestedActive ? "一時停止" : "再生")
        Button { model.skip(seconds: 10) } label: { Image(systemName: "goforward.10").font(.title) }
          .accessibilityLabel("10秒進む")
      }
      HStack {
        Button("ファイルを選択", action: onPickFile)
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
      }
      .buttonStyle(.bordered)
    }
    .padding(12)
  }

  /// 現在位置とシークバーは、補間した位置を0.1秒ごとに描く（一時停止中・停止中も動かし続けて、
  /// 一時停止中のシークや停止の反映が次の刻みで画面に出るようにする）。
  private var seekBar: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
      let position = model.displayPosition(at: ProcessInfo.processInfo.systemUptime)
      let duration = model.duration
      VStack(spacing: 2) {
        Slider(
          value: Binding(
            get: { isScrubbing ? scrubPosition : position },
            set: { scrubPosition = $0 }
          ),
          in: 0...(duration ?? 1)
        ) { editing in
          isScrubbing = editing
          // つまみを掴んだ瞬間に、現在位置から動き出すようにする。
          if editing { scrubPosition = model.displayPosition(at: ProcessInfo.processInfo.systemUptime) }
          // 離したとき1回だけシークする。
          if !editing { model.seek(toSeconds: scrubPosition) }
        }
        .disabled(duration == nil)
        .accessibilityLabel("シークバー")
        HStack {
          Text(Self.format(isScrubbing ? scrubPosition : position))
          Spacer()
          Text(duration.map(Self.format) ?? "--:--")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      }
    }
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
