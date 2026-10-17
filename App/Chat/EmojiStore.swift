import Foundation
import Observation
import UIKit
import VLCChatCore

/// キャッシュに入れる、デコード済みの絵文字。静止画か、2フレーム以上のGIFのアニメーション。
/// `NSCache` の値は参照型でなければならないので、`final class` にしている。
final class CachedEmoji: Sendable {
  enum Kind: Sendable {
    case still(UIImage)
    case animated(AnimatedEmoji)
  }

  let kind: Kind

  init(_ kind: Kind) {
    self.kind = kind
  }
}

/// デコード済みの絵文字画像のキャッシュと、読み込み完了の画面への通知。
///
/// `lookup(url:)` は `View` の `body` から呼ばれる。そのため `revision` 以外の保持物は
/// `@ObservationIgnored` にして、描画中の状態変更で再描画がループしないようにしている。
@Observable
@MainActor
final class EmojiStore {
  enum Lookup {
    case image(UIImage)
    /// 2フレーム以上のGIF。どのフレームを出すかは、行が時計（`EmojiAnimationClock`）から決める。
    case animated(AnimatedEmoji)
    /// 読み込み中。幅だけを確保した空白を出す。
    case pending
    /// ライブラリが無い、またはライブラリに無い（代替テキストを出す）。
    case missing
  }

  /// 絵文字の読み込みが終わるたびに（100ms以内の分をまとめて）増える。行はこれを読んで再描画される。
  private(set) var revision = 0
  private(set) var hasLibrary = false
  private(set) var libraryCount: Int?

  private let library = EmojiLibrary()
  /// 直近の1000種類までを保つ。`NSCache` は厳密なLRUではなく、メモリが逼迫すると捨てることもあるが、
  /// 捨てられても次の表示で読み直すだけなので、近似として許容する。
  /// GIFの全フレームも同じ1000種類の枠に入れ、GIF専用のメモリ上限は設けない（Issue #26の判断）。
  /// 1フレームは高さ54px・約12KBで、実データの最大120フレームでも約1.4MB。メモリ不足が実機で出たら、
  /// フレーム合計の上限を別Issueで検討する。
  private let cache = NSCache<NSString, CachedEmoji>()
  @ObservationIgnored private var missing = Set<String>()
  @ObservationIgnored private var inFlight = Set<String>()
  /// 取り込みで進める。取り込み前に始めた読み込みの古い画像をキャッシュに入れないため。
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var revisionPending = false
  @ObservationIgnored private var loggedMissing = 0
  @ObservationIgnored private var loggedAnimated = 0

  init() {
    cache.countLimit = 1000
    Task { await refreshLibraryState() }
  }

  private func refreshLibraryState() async {
    libraryCount = await library.count()
    hasLibrary = libraryCount != nil
  }

  // MARK: - 取り込み

  /// 選んだ `.sqlite` を取り込む。失敗したら投げる（今あるライブラリはそのまま）。
  func importLibrary(from url: URL) async throws {
    let started = Date()
    do {
      let result = try await library.importLibrary(from: url)
      libraryChanged()
      libraryCount = result.count
      hasLibrary = true
      AppLog.write(
        String(
          format: "絵文字ライブラリ取り込み 件数=%d サイズ=%.1fMB 所要=%.1fs", result.count, result.sizeMB,
          Date().timeIntervalSince(started)))
    } catch {
      AppLog.write("絵文字ライブラリ取り込み失敗: \(error)")
      throw error
    }
  }

  private func libraryChanged() {
    cache.removeAllObjects()
    missing.removeAll()
    inFlight.removeAll()
    generation += 1
    loggedMissing = 0
    loggedAnimated = 0
    revision += 1
  }

  // MARK: - 取り出し

  func lookup(url: String) -> Lookup {
    // `revision` と `hasLibrary` を読んで、変わったときにこの行が再描画されるようにする。
    _ = revision
    if let cached = cache.object(forKey: url as NSString) {
      switch cached.kind {
      case .still(let image): return .image(image)
      case .animated(let animated): return .animated(animated)
      }
    }
    if !hasLibrary || missing.contains(url) { return .missing }
    // 同じURLの読み込みは1回にまとめる。
    if inFlight.insert(url).inserted { startLoad(url) }
    return .pending
  }

  /// キャッシュにアニメーション絵文字として入っているか。`lookup` と違い、読み込みは始めない。
  /// 行が、時計に登録するかを決めるために使う（`ChatRowView.needsClock`）。
  func isAnimated(url: String) -> Bool {
    _ = revision
    guard let cached = cache.object(forKey: url as NSString) else { return false }
    if case .animated = cached.kind { return true }
    return false
  }

  private func startLoad(_ url: String) {
    let startGeneration = generation
    let library = library
    Task.detached(priority: .utility) { [weak self] in
      let data = await library.imageData(for: url)
      let started = Date()
      let emoji = data.flatMap { EmojiStore.makeEmoji(from: $0) }
      let decodeSeconds = Date().timeIntervalSince(started)
      await self?.finishLoad(url: url, emoji: emoji, generation: startGeneration, decodeSeconds: decodeSeconds)
    }
  }

  private func finishLoad(url: String, emoji: CachedEmoji?, generation startGeneration: Int, decodeSeconds: TimeInterval) {
    // 取り込み前に始めた読み込みの結果は捨てる。`inFlight` や記録には触れない
    // （新しい世代の読み込みの印を消さないため）。
    guard startGeneration == generation else { return }
    inFlight.remove(url)
    if let emoji {
      cache.setObject(emoji, forKey: url as NSString)
      if case .animated(let animated) = emoji.kind, loggedAnimated < 20 {
        loggedAnimated += 1
        // 1枚＝先頭フレームのバイト数。遅延の正規化・フレーム数・1フレームの大きさを、実機で代表GIFと突き合わせる手がかり。
        let frameBytes = animated.frames[0].cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        AppLog.write(
          String(
            format: "GIF絵文字 url=%@ フレーム=%d 周期=%.2fs 1枚=%dバイト 所要=%.0fms", url, animated.frames.count,
            animated.timing.loopDuration, frameBytes, decodeSeconds * 1000))
      }
    } else {
      missing.insert(url)
      if loggedMissing < 20 {
        loggedMissing += 1
        AppLog.write("絵文字なし url=\(url)")
      }
    }
    scheduleRevision()
  }

  private func scheduleRevision() {
    guard !revisionPending else { return }
    revisionPending = true
    Task {
      try? await Task.sleep(for: .milliseconds(100))
      revisionPending = false
      revision += 1
    }
  }

  /// 高さ18ptに描き直す。`Text(Image(uiImage:))` は `UIImage.size`（pt＝px÷scale）で描かれ、
  /// `preparingThumbnail(of:)` は拡大を保証しないので、描き直して大きさを揃える。
  /// 画面のスケールは3固定（iPhoneのみの前提）。
  nonisolated static func makeImage(from data: Data) -> UIImage? {
    guard let source = UIImage(data: data), let size = targetSize(for: source) else { return nil }
    return redraw(source, size: size)
  }

  /// 2フレーム以上のGIFはアニメーション絵文字に、それ以外（PNG・JPEG・1フレームのGIF、
  /// 途中でデコードに失敗したGIF）は従来どおりの静止画（`makeImage`）にする。
  nonisolated static func makeEmoji(from data: Data) -> CachedEmoji? {
    if let animated = makeAnimated(from: data) { return CachedEmoji(.animated(animated)) }
    return makeImage(from: data).map { CachedEmoji(.still($0)) }
  }

  /// GIFを1フレームずつ取り出して、静止画と同じ描き直しを通す。描き直す大きさは先頭フレームから1回だけ決め、
  /// 全フレームに使う（フレームごとに幅がぶれて、行が揺れるのを避ける）。
  /// 元の大きさのフレームを溜めないよう、1枚ごとに `autoreleasepool` で中間オブジェクトを手放す。
  nonisolated private static func makeAnimated(from data: Data) -> AnimatedEmoji? {
    guard let source = GifSource(data: data), source.frameCount > 1 else { return nil }
    var frames: [UIImage] = []
    var rawDelays: [TimeInterval] = []
    var size: CGSize?
    for index in 0..<source.frameCount {
      let frame: UIImage? = autoreleasepool { () -> UIImage? in
        guard let cgImage = source.frame(at: index) else { return nil }
        let image = UIImage(cgImage: cgImage)
        guard let target = size ?? targetSize(for: image) else { return nil }
        size = target
        return redraw(image, size: target)
      }
      guard let frame else { return nil }
      frames.append(frame)
      rawDelays.append(source.rawDelay(at: index))
    }
    return AnimatedEmoji(frames: frames, timing: AnimationTiming(rawDelays: rawDelays))
  }

  /// 高さ18ptで、縦横比を保った大きさ。画像が空なら nil。
  nonisolated private static func targetSize(for source: UIImage) -> CGSize? {
    guard source.size.height > 0, source.size.width > 0 else { return nil }
    let height: CGFloat = 18
    return CGSize(width: source.size.width * height / source.size.height, height: height)
  }

  nonisolated private static func redraw(_ source: UIImage, size: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      source.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
