import Foundation
import Observation
import VLCChatCore

/// プレイリストの状態・保存・ブックマークの作成と解決・有効性の確認。
@Observable
@MainActor
final class PlaylistModel {
  struct EntryValidity: Equatable {
    var video: Bool
    /// 割り当てが無ければ nil
    var chat: Bool?
  }

  struct ResolvedFile {
    let url: URL
    let wasStale: Bool
  }

  struct ReplaceResult {
    var failedNames: [String] = []
    var failedChatNames: [String] = []
  }

  private(set) var playlist: Playlist
  private(set) var validity: [UUID: EntryValidity] = [:]

  @ObservationIgnored private let fileURL = SupportFiles.url("playlist.json")
  @ObservationIgnored private var snapshot: (playlist: Playlist, validity: [UUID: EntryValidity])?
  @ObservationIgnored private var staleVideoIDs = Set<UUID>()
  @ObservationIgnored private var staleChatIDs = Set<UUID>()

  init() {
    var loaded = Playlist()
    do {
      if let playlist = try PlaylistFile.load(from: fileURL) { loaded = playlist }
    } catch {
      AppLog.write("プレイリスト 読み込み失敗: \(error)")
      SupportFiles.quarantine(fileURL)
    }
    playlist = loaded
    AppLog.write("プレイリスト 復元 \(loaded.entries.count)件")
  }

  // MARK: - 操作

  /// 置き換え。失敗したときに戻せるよう、前の状態を保持する（`commit()` で捨てる）。
  func replace(videos: [URL], chats: [URL?]) -> ReplaceResult {
    snapshot = (playlist, validity)
    let made = makeEntries(videos: videos, chats: chats)
    playlist.replace(with: made.entries)
    validity = [:]
    AppLog.write("プレイリスト 置き換え \(made.entries.count)件")
    save()
    return made.result
  }

  func commit() {
    snapshot = nil
  }

  func restoreSnapshot() {
    guard let snapshot else { return }
    playlist = snapshot.playlist
    validity = snapshot.validity
    self.snapshot = nil
    AppLog.write("プレイリスト 置き換えを取り消し")
    save()
  }

  func append(videos: [URL], chats: [URL?]) -> ReplaceResult {
    let made = makeEntries(videos: videos, chats: chats)
    playlist.append(made.entries)
    AppLog.write("プレイリスト 追記 \(made.entries.count)件")
    save()
    return made.result
  }

  func remove(at index: Int) -> Playlist.Removal {
    let name = playlist.entries.indices.contains(index) ? playlist.entries[index].videoFileName : "-"
    let removal = playlist.remove(at: index)
    AppLog.write("プレイリスト 削除 \(name)")
    save()
    return removal
  }

  func move(fromOffsets: IndexSet, toOffset: Int) {
    playlist.move(fromOffsets: fromOffsets, toOffset: toOffset)
    AppLog.write("プレイリスト 並べ替え")
    save()
  }

  func setCurrent(id: UUID?) {
    playlist.setCurrent(id: id)
    save()
  }

  /// チャットを割り当てる。ブックマークを作れなければ false。
  func assignChat(entryID: UUID, url: URL) -> Bool {
    let file = ScopedFile(url: url)
    guard let bookmark = try? file.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return false }
    let name = url.lastPathComponent
    playlist.updateEntry(id: entryID) {
      $0.chatFileName = name
      $0.chatBookmark = bookmark
    }
    validity[entryID]?.chat = true
    AppLog.write("プレイリスト チャット割り当て \(entryID.uuidString.prefix(8)) \(name)")
    save()
    return true
  }

  func markVideoUnplayable(_ id: UUID) {
    validity[id, default: EntryValidity(video: false, chat: nil)].video = false
  }

  func markVideoPlayable(_ id: UUID) {
    validity[id, default: EntryValidity(video: true, chat: nil)].video = true
  }

  func markChatUnplayable(_ id: UUID) {
    validity[id, default: EntryValidity(video: true, chat: false)].chat = false
  }

  // MARK: - 次・前の探索

  // `playItem` が失敗しても現在の項目は動かないので、失敗した項目は呼び出し側が `excluding` に溜めて再探索する。
  // 溜めないと、読めるのに `open` が失敗する項目を返し続けて無限ループになる。
  func nextStep(excluding: Set<UUID> = []) -> Playlist.Step {
    finish(playlist.nextStep { playable($0, excluding) })
  }

  func previousStep(excluding: Set<UUID> = []) -> Playlist.Step {
    finish(playlist.previousStep { playable($0, excluding) })
  }

  func stepFromCurrent(excluding: Set<UUID> = []) -> Playlist.Step {
    finish(playlist.stepFromCurrent { playable($0, excluding) })
  }

  private func playable(_ entry: PlaylistEntry, _ excluding: Set<UUID>) -> Bool {
    !excluding.contains(entry.id) && isVideoPlayable(entry)
  }

  private func finish(_ step: Playlist.Step) -> Playlist.Step {
    for index in step.skipped where playlist.entries.indices.contains(index) {
      markVideoUnplayable(playlist.entries[index].id)
    }
    renewStaleBookmarks()
    return step
  }

  // MARK: - ブックマーク

  func resolve(_ data: Data) -> ResolvedFile? {
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else { return nil }
    return ResolvedFile(url: url, wasStale: stale)
  }

  func isVideoPlayable(_ entry: PlaylistEntry) -> Bool {
    guard let resolved = resolve(entry.videoBookmark) else { return false }
    if resolved.wasStale { staleVideoIDs.insert(entry.id) }
    return Self.isReadable(resolved.url)
  }

  private func isChatReadable(_ entry: PlaylistEntry) -> Bool? {
    guard let data = entry.chatBookmark else { return nil }
    guard let resolved = resolve(data) else { return false }
    if resolved.wasStale { staleChatIDs.insert(entry.id) }
    return Self.isReadable(resolved.url)
  }

  private static func isReadable(_ url: URL) -> Bool {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    return FileManager.default.isReadableFile(atPath: url.path)
  }

  /// 全項目の動画とチャットの有効性を求める。数十項目なので同期で行う。
  func refreshValidity() {
    var result: [UUID: EntryValidity] = [:]
    for entry in playlist.entries {
      result[entry.id] = EntryValidity(video: isVideoPlayable(entry), chat: isChatReadable(entry))
    }
    validity = result
    renewStaleBookmarks()
  }

  /// 失効したブックマークを作り直す。探索・走査の後にまとめて行う。名前が変わっていれば表示名も更新する。
  func renewStaleBookmarks() {
    guard !staleVideoIDs.isEmpty || !staleChatIDs.isEmpty else { return }
    let videoIDs = staleVideoIDs, chatIDs = staleChatIDs
    staleVideoIDs = []
    staleChatIDs = []
    for entry in playlist.entries {
      if videoIDs.contains(entry.id), let renewed = renewed(entry.videoBookmark) {
        playlist.updateEntry(id: entry.id) {
          $0.videoBookmark = renewed.data
          $0.videoFileName = renewed.name
        }
        AppLog.write("プレイリスト ブックマーク 失効 \(renewed.name)（更新）")
      }
      if chatIDs.contains(entry.id), let data = entry.chatBookmark, let renewed = renewed(data) {
        playlist.updateEntry(id: entry.id) {
          $0.chatBookmark = renewed.data
          $0.chatFileName = renewed.name
        }
      }
    }
    save()
  }

  private func renewed(_ data: Data) -> (data: Data, name: String)? {
    guard let resolved = resolve(data) else { return nil }
    let didStart = resolved.url.startAccessingSecurityScopedResource()
    defer { if didStart { resolved.url.stopAccessingSecurityScopedResource() } }
    guard
      let fresh = try? resolved.url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return nil }
    return (fresh, resolved.url.lastPathComponent)
  }

  // MARK: - 内部

  private func makeEntries(videos: [URL], chats: [URL?]) -> (entries: [PlaylistEntry], result: ReplaceResult) {
    var entries: [PlaylistEntry] = []
    var result = ReplaceResult()
    for (index, videoURL) in videos.enumerated() {
      // アクセスしている間にブックマークを作る。
      let video = ScopedFile(url: videoURL)
      guard
        let videoBookmark = try? video.url.bookmarkData(
          options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      else {
        result.failedNames.append(videoURL.lastPathComponent)
        continue
      }
      var entry = PlaylistEntry(videoFileName: videoURL.lastPathComponent, videoBookmark: videoBookmark)
      if index < chats.count, let chatURL = chats[index] {
        let chat = ScopedFile(url: chatURL)
        if let chatBookmark = try? chat.url.bookmarkData(
          options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        {
          entry.chatFileName = chatURL.lastPathComponent
          entry.chatBookmark = chatBookmark
        } else {
          result.failedChatNames.append(chatURL.lastPathComponent)
        }
      }
      entries.append(entry)
    }
    return (entries, result)
  }

  private func save() {
    do {
      try PlaylistFile.save(playlist, to: fileURL)
    } catch {
      AppLog.write("プレイリスト 保存 失敗: \(error)")
    }
  }
}
