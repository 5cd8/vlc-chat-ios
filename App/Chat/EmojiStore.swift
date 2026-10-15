import Foundation
import Observation
import UIKit

/// デコード済みの絵文字画像のキャッシュと、読み込み完了の画面への通知。
///
/// `lookup(url:)` は `View` の `body` から呼ばれる。そのため `revision` 以外の保持物は
/// `@ObservationIgnored` にして、描画中の状態変更で再描画がループしないようにしている。
@Observable
@MainActor
final class EmojiStore {
  enum Lookup {
    case image(UIImage)
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
  private let cache = NSCache<NSString, UIImage>()
  @ObservationIgnored private var missing = Set<String>()
  @ObservationIgnored private var inFlight = Set<String>()
  /// 取り込みで進める。取り込み前に始めた読み込みの古い画像をキャッシュに入れないため。
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var revisionPending = false
  @ObservationIgnored private var loggedMissing = 0

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
    revision += 1
  }

  // MARK: - 取り出し

  func lookup(url: String) -> Lookup {
    // `revision` と `hasLibrary` を読んで、変わったときにこの行が再描画されるようにする。
    _ = revision
    if let image = cache.object(forKey: url as NSString) { return .image(image) }
    if !hasLibrary || missing.contains(url) { return .missing }
    // 同じURLの読み込みは1回にまとめる。
    if inFlight.insert(url).inserted { startLoad(url) }
    return .pending
  }

  private func startLoad(_ url: String) {
    let startGeneration = generation
    let library = library
    Task.detached(priority: .utility) { [weak self] in
      let data = await library.imageData(for: url)
      let image = data.flatMap { EmojiStore.makeImage(from: $0) }
      await self?.finishLoad(url: url, image: image, generation: startGeneration)
    }
  }

  private func finishLoad(url: String, image: UIImage?, generation startGeneration: Int) {
    // 取り込み前に始めた読み込みの結果は捨てる。`inFlight` や記録には触れない
    // （新しい世代の読み込みの印を消さないため）。
    guard startGeneration == generation else { return }
    inFlight.remove(url)
    if let image {
      cache.setObject(image, forKey: url as NSString)
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
    guard let source = UIImage(data: data), source.size.height > 0, source.size.width > 0 else { return nil }
    let height: CGFloat = 18
    let size = CGSize(width: source.size.width * height / source.size.height, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      source.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
