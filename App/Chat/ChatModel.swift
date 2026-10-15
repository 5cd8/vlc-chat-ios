import Darwin
import Foundation
import Observation
import VLCChatCore

/// 読み込んだチャットと、再生位置に合わせた表示の末尾。
@Observable
@MainActor
final class ChatModel {
  enum LoadState: Equatable {
    case none
    case loading
    case loaded(count: Int, format: ChatFormat)
    case failed
  }

  private(set) var state: LoadState = .none
  private(set) var store: ChatStore?
  /// 表示の末尾（`store.window(endIndex:)` が表示する範囲）。
  private(set) var endIndex = 0
  /// 診断シートに出す、直近の読み込みの要約。
  private(set) var loadSummary: String?

  /// 古い読み込みの結果を捨てるための世代。動画の切り替えや再読み込みで進める。
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  /// 読み込み中でも動画の再生は止めない（別スレッドで読む）。進行中の読み込みは取り消して破棄する。
  func load(url: URL) {
    loadTask?.cancel()
    generation += 1
    let gen = generation
    store = nil
    endIndex = 0
    loadSummary = nil
    state = .loading

    let file = ScopedFile(url: url)
    let name = url.lastPathComponent
    let sizeMB = file.fileSizeBytes.map { String(format: "%.1fMB", Double($0) / 1_048_576) } ?? "不明"
    AppLog.write("チャット読み込み 開始 \(name) サイズ=\(sizeMB) startAccessing=\(file.didStartAccess)")

    // `Task.detached` が返すタスク自身を持つので、`cancel()` が読み込みの `Task.isCancelled` に届く。
    loadTask = Task.detached(priority: .utility) { [weak self] in
      let started = Date()
      let memoryBefore = MemoryProbe.physFootprintMB()
      var peak = memoryBefore ?? 0
      let outcome: Result<ChatLoadResult, Error>
      do {
        let source = try FileByteSource(url: file.url)
        let result = try ChatLoader.load(
          from: source,
          isCancelled: { Task.isCancelled },
          progress: { _ in
            if let current = MemoryProbe.physFootprintMB() { peak = max(peak, current) }
          }
        )
        outcome = .success(result)
      } catch {
        outcome = .failure(error)
      }
      let elapsed = Date().timeIntervalSince(started)
      let memoryAfter = MemoryProbe.physFootprintMB()
      // 読み込み中の一時オブジェクトで膨らんだ空きページを、OSへ返す。返した後の値との差で、
      // 増えた分が実際に保持されているのか、解放済みで空いているだけなのかが分かる。
      malloc_zone_pressure_relief(nil, 0)
      let memoryReleased = MemoryProbe.physFootprintMB()
      // ファイルのスコープは、読み終えるまで保つ。
      withExtendedLifetime(file) {}
      let memoryText = String(
        format: "メモリ=%.0f→%.0fMB（ピーク%.0fMB、解放後%.0fMB）", memoryBefore ?? 0, memoryAfter ?? 0,
        max(peak, memoryAfter ?? 0), memoryReleased ?? 0)
      await self?.finish(generation: gen, name: name, outcome: outcome, elapsed: elapsed, memoryText: memoryText)
    }
  }

  private func finish(
    generation gen: Int, name: String, outcome: Result<ChatLoadResult, Error>, elapsed: TimeInterval, memoryText: String
  ) {
    // 動画の切り替えや再読み込みの後に届いた結果は捨てる。
    guard gen == generation else {
      AppLog.write("チャット読み込み 破棄（古い読み込み） \(name)")
      return
    }
    switch outcome {
    case .success(let result):
      let formatText = result.format == .youTube ? "YouTube" : "Twitch"
      let summary = String(
        format: "形式=%@ 件数=%d 除外=%d 所要=%.1fs %@", formatText, result.store.count, result.skipped, elapsed, memoryText)
      store = result.store
      endIndex = 0
      state = .loaded(count: result.store.count, format: result.format)
      loadSummary = summary
      AppLog.write("チャット読み込み 完了 \(summary)")
    case .failure(let error):
      if let loaderError = error as? ChatLoaderError, loaderError == .cancelled {
        AppLog.write("チャット読み込み 取り消し \(name)")
        return
      }
      state = .failed
      loadSummary = "読み込み失敗"
      AppLog.write("チャット読み込み 失敗: \(error)")
    }
  }

  /// チャット欄を空に戻す（動画を開き直したとき）。進行中の読み込みは取り消して、結果を捨てる。
  func reset() {
    loadTask?.cancel()
    loadTask = nil
    generation += 1
    store = nil
    endIndex = 0
    state = .none
    loadSummary = nil
  }

  /// 再生位置（秒）に合わせて表示の末尾を進める。変わらないときは何もしない（画面を更新しない）。
  func updatePosition(seconds: Int) {
    guard let store else { return }
    let end = store.endIndex(atSeconds: seconds)
    if end != endIndex { endIndex = end }
  }
}
