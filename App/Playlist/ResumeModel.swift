import Foundation
import Observation
import VLCChatCore

/// 再生位置の記憶。`set`／`remove` のたびに書く（1ファイルが数KBなので間引かない）。
@Observable
@MainActor
final class ResumeModel {
  private(set) var count = 0
  @ObservationIgnored private var store = ResumeStore()
  @ObservationIgnored private let fileURL = SupportFiles.url("resume.json")

  init() {
    do {
      if let loaded = try ResumeStore.load(from: fileURL) { store = loaded }
    } catch {
      AppLog.write("記憶 読み込み失敗: \(error)")
      SupportFiles.quarantine(fileURL)
    }
    count = store.count
  }

  func position(for identity: VideoIdentity) -> TimeInterval? {
    store.position(for: identity)
  }

  func record(_ position: TimeInterval, for identity: VideoIdentity) {
    store.set(position, for: identity, at: Date())
    persist()
  }

  func remove(_ identity: VideoIdentity?) {
    guard let identity, store.position(for: identity) != nil else { return }
    store.remove(identity)
    AppLog.write("記憶 削除 \(identity.fileName)")
    persist()
  }

  private func persist() {
    count = store.count
    do {
      try store.save(to: fileURL)
    } catch {
      AppLog.write("記憶 保存失敗: \(error)")
    }
  }
}
