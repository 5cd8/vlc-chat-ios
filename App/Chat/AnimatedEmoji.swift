import UIKit
import VLCChatCore

/// 高さ18ptに描き直した全フレームと、その表示時間。作った後は変えない。
final class AnimatedEmoji: Sendable {
  let frames: [UIImage]
  /// `frames.count` と同じ数の遅延を持つ。
  let timing: AnimationTiming

  init(frames: [UIImage], timing: AnimationTiming) {
    precondition(!frames.isEmpty && frames.count == timing.delays.count)
    self.frames = frames
    self.timing = timing
  }

  /// 経過時間 `time`（秒、0以上）に表示するフレーム。常に無限ループする。
  func frame(at time: TimeInterval) -> UIImage {
    frames[timing.frameIndex(at: time)]
  }
}
