import Foundation
import ImageIO
import UniformTypeIdentifiers

/// GIFのフレームと遅延を、ImageIOで1枚ずつ読む窓口。デコード済みの全フレームを保持しない
/// （呼び出し側が1枚ずつ取り出して縮め、元の大きさのフレームを溜めないため）。
/// `CGImageSource` は `Sendable` ではないので、この型も `Sendable` にしない（1つのタスクの中で使い切る）。
public struct GifSource {
  private let source: CGImageSource
  public let frameCount: Int

  /// GIFでない・開けない・フレームが0枚のときは nil。
  public init?(data: Data) {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
      let type = CGImageSourceGetType(source),
      (type as String) == UTType.gif.identifier
    else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else { return nil }
    self.source = source
    self.frameCount = count
  }

  /// `kCGImagePropertyGIFDictionary` の中から、Unclamped → DelayTime → 0 の順に読む（秒）。
  /// `DelayTime` は下限でクランプされるので、10ms以下の扱いは呼び出し側（`AnimationTiming`）で決める。
  /// 範囲外の添字は 0。
  public func rawDelay(at index: Int) -> TimeInterval {
    guard index >= 0, index < frameCount,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
      let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else { return 0 }
    if let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue {
      return unclamped
    }
    if let clamped = (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue {
      return clamped
    }
    return 0
  }

  /// 範囲外の添字は nil。デコード結果を `CGImageSource` に溜めさせない。
  public func frame(at index: Int) -> CGImage? {
    guard index >= 0, index < frameCount else { return nil }
    return CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary)
  }
}
