import Foundation
import Observation
import VLCChatCore

/// `RemoteControlController` は `AppModel` の全プロパティの初期化前に作られ、`self` を捕まえられないので、
/// 後から `AppModel` を差し込める中継を先に作ってハンドラに渡す。
@MainActor
final class NavigationRelay {
  weak var model: AppModel?
}

/// アプリ全体のモデルを束ねる。
@Observable
@MainActor
final class AppModel {
  /// SwiftVLC のバージョン。`libVLC` の版（`instance.version`）とは別物。
  static let swiftVLCVersion = "1.1.0-beta.14"

  let diagnostics: DiagnosticsModel
  let playback: PlayerModel
  let remote: RemoteControlController
  let chat = ChatModel()
  let emoji = EmojiStore()
  let playlist = PlaylistModel()
  let resume = ResumeModel()
  let settings = SettingsModel()
  private let audioSession: AudioSessionController
  private let relay: NavigationRelay

  /// 切り替えの後にPiPが使えなくなったときの開き直しの待機（Issue #12）。新しい切り替えで取り消す。
  @ObservationIgnored private var pipRecoveryTask: Task<Void, Never>?

  /// 利用者に知らせる通知の待ち行列（動画を開けなかった理由は `playback.openError` が別に持つ）。
  private(set) var notices: [String] = []

  /// 画面の確認ダイアログに出す文言。動画を開けなかった理由を先に、次に通知を1件ずつ出す。
  var alertMessage: String? { playback.openError ?? notices.first }

  init() {
    // 生成の順序（循環を避ける）：診断と音声セッション → 再生 → ロック画面 → 後付けの参照 → 開始。
    let diagnostics = DiagnosticsModel()
    let audioSession = AudioSessionController()
    let playback = PlayerModel(diagnostics: diagnostics, audioSession: audioSession)
    let relay = NavigationRelay()
    let remote = RemoteControlController(
      handlers: .init(
        play: { [weak playback] in playback?.play() },
        pause: { [weak playback] in playback?.pause() },
        toggle: { [weak playback] in playback?.togglePlayPause() },
        skip: { [weak playback] seconds in playback?.skip(seconds: seconds) },
        seek: { [weak playback] seconds in playback?.seek(toSeconds: seconds) },
        next: { [relay] in relay.model?.nextItem() },
        previous: { [relay] in relay.model?.previousItem() }
      )
    )
    playback.remote = remote
    audioSession.stateDescription = { [weak playback] in playback?.stateDescription ?? "状態=-" }
    audioSession.onDisruption = { [weak playback] disruption in playback?.audioDisruption(disruption) }

    self.diagnostics = diagnostics
    self.playback = playback
    self.remote = remote
    self.audioSession = audioSession
    self.relay = relay
    relay.model = self

    playback.resumeLookup = { [resume] identity in resume.position(for: identity) }
    playback.positionRecorder = { [resume] identity, position in resume.record(position, for: identity) }
    playback.onEnded = { [relay] identity in relay.model?.handlePlaybackEnded(identity) }
    playback.earlyAdvanceEnabled = { [settings, playlist] in settings.autoAdvance && playlist.playlist.hasNext }
    playback.onEarlyAdvance = { [relay] identity in relay.model?.handleEarlyAdvance(identity) }
    playback.navigationState = { [playlist] in
      (canGoPrevious: playlist.playlist.hasPrevious, canGoNext: playlist.playlist.hasNext)
    }

    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    let libVLC = playback.libVLCVersion ?? "—"
    diagnostics.versionText = "build \(build) / SwiftVLC \(Self.swiftVLCVersion) / libVLC \(libVLC)"
    AppLog.write("起動 build=\(build) SwiftVLC=\(Self.swiftVLCVersion) libVLC=\(libVLC)")

    audioSession.startObservingInterruptions()
    diagnostics.start()
  }

  /// 表示中の1件だけを消す。続きがあれば、次の1件が出る。
  func dismissAlert() {
    if playback.openError != nil {
      playback.dismissOpenError()
    } else if !notices.isEmpty {
      notices.removeFirst()
    }
  }

  private func notify(_ prefix: String, names: [String]) {
    var seen = Set<String>()
    let unique = names.filter { seen.insert($0).inserted }
    guard !unique.isEmpty else { return }
    notices.append("\(prefix): \(unique.joined(separator: ", "))")
  }

  // MARK: - 選択の振り分け

  /// 「ファイルを選択」の結果。動画があればプレイリストを置き換えて先頭から再生する。
  func handlePicked(urls: [URL]) {
    let plan = SelectionPlanner.plan(fileNames: urls.map(\.lastPathComponent))
    reportCommon(plan, urls)
    if let index = plan.emojiLibrary { importEmoji(urls[index]) }

    guard !plan.videos.isEmpty else {
      if let index = plan.soleChatIndex { assignChatToCurrent(urls[index]) }
      notify("対応する動画が無いチャットを無視しました", names: plan.ignoredChats.map { urls[$0].lastPathComponent })
      return
    }

    let result = playlist.replace(
      videos: plan.videos.map { urls[$0] }, chats: plan.pairs.map { $0.map { urls[$0] } })
    reportFailures(result)
    notify("対応する動画が無いチャットを無視しました", names: plan.ignoredChats.map { urls[$0].lastPathComponent })

    var excluded = Set<UUID>()
    var skippedNames: [String] = []
    var started = false
    while true {
      let step = playlist.stepFromCurrent(excluding: excluded)
      skippedNames = step.skipped.compactMap { name(at: $0) }
      guard let target = step.target else { break }
      if playItem(at: target, byUser: false) {
        started = true
        break
      }
      if let id = id(at: target) { excluded.insert(id) }
    }
    if started {
      playlist.commit()
      notify("開けない項目を飛ばしました", names: skippedNames)
    } else {
      playlist.restoreSnapshot()
      notify("開けない項目を飛ばしました", names: skippedNames)
      notices.append("再生できる項目がありません")
    }
  }

  /// 「追加」。再生位置は変えない。
  func appendPicked(urls: [URL]) {
    let plan = SelectionPlanner.plan(fileNames: urls.map(\.lastPathComponent))
    if !plan.unsupported.isEmpty { notices.append("対応していない形式です") }
    if plan.emojiLibrary != nil { notices.append("絵文字ライブラリは設定から入れ替えてください") }
    guard !plan.videos.isEmpty else {
      notices.append("追加は動画を選んでください。チャットは項目のチャットの欄から割り当てられます")
      return
    }
    let result = playlist.append(
      videos: plan.videos.map { urls[$0] }, chats: plan.pairs.map { $0.map { urls[$0] } })
    reportFailures(result)
    notify("対応する動画が無いチャットを無視しました", names: plan.ignoredChats.map { urls[$0].lastPathComponent })
    playlist.refreshValidity()
    playback.refreshRemote()
  }

  /// 項目のチャットの欄からの割り当て。現在の項目で再生中のときだけ、すぐ読み込む。
  func assignChatPicked(entryID: UUID, urls: [URL]) {
    guard let url = urls.first else { return }
    guard playlist.assignChat(entryID: entryID, url: url) else {
      notices.append("チャットを開けませんでした: \(url.lastPathComponent)")
      return
    }
    if playlist.playlist.currentID == entryID, playback.title != nil { chat.load(url: url) }
  }

  func replaceEmojiPicked(urls: [URL]) {
    guard let url = urls.first else { return }
    importEmoji(url)
  }

  private func reportCommon(_ plan: SelectionPlan, _ urls: [URL]) {
    if !plan.unsupported.isEmpty {
      notices.append("対応していない形式です")
      for index in plan.unsupported { AppLog.write("選択 未対応 \(urls[index].path)") }
    }
  }

  private func reportFailures(_ result: PlaylistModel.ReplaceResult) {
    notify("開けないファイルがありました", names: result.failedNames)
    notify("チャットを開けませんでした", names: result.failedChatNames)
  }

  private func importEmoji(_ url: URL) {
    AppLog.write("選択 絵文字ライブラリ \(url.path)")
    Task {
      do {
        try await emoji.importLibrary(from: url)
      } catch {
        notices.append("絵文字ライブラリを読み込めませんでした")
      }
    }
  }

  /// 動画が無くチャットだけを選んだとき。再生中の動画の項目に割り当てて読み込む。
  private func assignChatToCurrent(_ url: URL) {
    guard playback.title != nil else {
      notices.append("先に動画を開いてください")
      return
    }
    if let id = playlist.playlist.currentID, !playlist.assignChat(entryID: id, url: url) {
      notices.append("チャットの割り当てを保存できませんでした: \(url.lastPathComponent)")
    }
    AppLog.write("選択 チャット \(url.path)")
    chat.load(url: url)
  }

  // MARK: - 項目の再生

  private func id(at index: Int) -> UUID? {
    playlist.playlist.entries.indices.contains(index) ? playlist.playlist.entries[index].id : nil
  }

  private func name(at index: Int) -> String? {
    playlist.playlist.entries.indices.contains(index) ? playlist.playlist.entries[index].title : nil
  }

  /// プレイリスト画面のタップ、自動進行、前へ・次へ、置き換えから呼ぶ。成功＝動画が開けた。
  /// 失敗しても現在の項目は動かさない（開けたあとで `setCurrent` する）。
  @discardableResult
  func playItem(at index: Int, byUser: Bool, isPiPRecovery: Bool = false) -> Bool {
    guard playlist.playlist.entries.indices.contains(index) else { return false }
    let entry = playlist.playlist.entries[index]
    playback.recordPosition()
    guard playlist.isVideoPlayable(entry), let resolved = playlist.resolve(entry.videoBookmark) else {
      playlist.markVideoUnplayable(entry.id)
      if byUser { notices.append("開けませんでした: \(entry.title)") }
      return false
    }
    playlist.renewStaleBookmarks()
    let before = playback.openCount
    playback.open(url: resolved.url)
    guard playback.openCount != before else {
      // 差し替えに失敗して古い動画も外れたなら、チャット欄も空にする。
      if playback.title == nil { chat.reset() }
      return false
    }
    playlist.setCurrent(id: entry.id)
    playlist.markVideoPlayable(entry.id)
    chat.reset()
    if let data = entry.chatBookmark {
      if let chatFile = playlist.resolve(data) {
        chat.load(url: chatFile.url)
      } else {
        playlist.markChatUnplayable(entry.id)
        notices.append("チャットを開けませんでした: \(entry.chatFileName ?? "")")
      }
    }
    playback.refreshRemote()
    // 開き直し自体の後には、さらに開き直さない（一度だけ）。
    if !isPiPRecovery { schedulePiPRecovery(entryID: entry.id) }
    return true
  }

  /// 切り替えの後、PiPが使えない状態（`isPossible == false`）になっていたら、同じ動画を一度だけ開き直す。
  /// 実機では、開き直す以外にPiPを戻せた操作が無かった（Issue #12）。
  /// 判定は項目のIDで照合し、待つ間にユーザーが別の動画へ替えていたら何もしない。
  private func schedulePiPRecovery(entryID: UUID) {
    pipRecoveryTask?.cancel()
    pipRecoveryTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(1.5))
        // 準備中（まだ再生が始まっていない）なら、判定を延ばす。
        var waited = 0.0
        while let self, self.playback.needsPlaybackWait, waited < 3 {
          try await Task.sleep(for: .milliseconds(500))
          waited += 0.5
        }
      } catch {
        return
      }
      guard let self, self.playlist.playlist.currentID == entryID else { return }
      guard self.playback.needsPiPRecovery() else {
        if !self.playback.isPiPPossible {
          AppLog.write("PiP回復 見送り 理由=\(self.playback.pipStatusText)")
        }
        return
      }
      guard let index = self.playlist.playlist.entries.firstIndex(where: { $0.id == entryID }) else { return }
      AppLog.write("PiP回復 開き直し \(self.playback.pipStatusText)")
      guard self.playItem(at: index, byUser: false, isPiPRecovery: true) else {
        AppLog.write("PiP回復 失敗")
        return
      }
      do {
        try await Task.sleep(for: .seconds(2))
      } catch {
        return
      }
      AppLog.write("PiP回復 結果 \(self.playback.pipStatusText)")
    }
  }

  // MARK: - 自動進行・前へ・次へ

  func nextItem() {
    advance(stopsWhenNone: false) { self.playlist.nextStep(excluding: $0) }
  }

  func previousItem() {
    advance(stopsWhenNone: false) { self.playlist.previousStep(excluding: $0) }
  }

  /// 有効な項目が見つかるまで探す。開けなかった項目は `excluded` に溜めて再探索する。
  /// 有効な項目が無いとき、手で押した前へ・次へは再生中の動画を止めない（ユーザー確定）。
  /// 最後まで再生した後の自動進行は、もう再生が終わっているので停止状態にする。
  private func advance(stopsWhenNone: Bool, silent: Bool = false, _ step: (Set<UUID>) -> Playlist.Step) {
    var excluded = Set<UUID>()
    while true {
      let result = step(excluded)
      let skippedNames = result.skipped.compactMap { name(at: $0) }
      guard let target = result.target else {
        // 有効な項目が無ければ停止する（動画は閉じない）。端の項目で押したときは何もしない。
        if !result.skipped.isEmpty, !silent {
          if stopsWhenNone { playback.stopKeepingTitle() }
          notify("開けない項目を飛ばしました", names: skippedNames)
          notices.append("再生できる項目がありません")
        }
        return
      }
      if playItem(at: target, byUser: false) {
        notify("開けない項目を飛ばしました", names: skippedNames)
        return
      }
      if let id = id(at: target) { excluded.insert(id) }
    }
  }

  /// 最後まで再生した。記憶を消し、設定が許せば次の項目へ進む。
  func handlePlaybackEnded(_ identity: VideoIdentity?) {
    resume.remove(identity)
    guard settings.autoAdvance, playlist.playlist.hasNext else { return }
    advance(stopsWhenNone: true) { self.playlist.nextStep(excluding: $0) }
  }

  /// PiP中、終端の手前で次へ進む。開ける項目が無くても通知も停止もしない（動画はそのまま終端まで再生され、
  /// 終端の `handlePlaybackEnded` が従来どおり扱う）。ただし開くこと自体に失敗した場合は、
  /// 手動の切り替えと同じく `openError` のアラートが出る。
  func handleEarlyAdvance(_ identity: VideoIdentity?) {
    resume.remove(identity)
    advance(stopsWhenNone: false, silent: true) { self.playlist.nextStep(excluding: $0) }
  }

  // MARK: - プレイリスト画面の操作

  /// 左スワイプの削除。大きい添字から消し、すべて消し終えてから現在が消えたかを1回だけ判断する。
  func removeEntries(at offsets: IndexSet) {
    var currentRemoved = false
    for index in offsets.sorted(by: >) {
      if playlist.remove(at: index) == .current { currentRemoved = true }
    }
    if currentRemoved { followRemovedCurrent() }
    playback.refreshRemote()
  }

  private func followRemovedCurrent() {
    // 起動直後（動画を開いていない）は、現在を付け替えるだけで音は出さない。
    guard playback.title != nil else { return }
    // 停止中に付け替えだけにすると、画面の動画（削除した項目）と現在の項目が食い違い、
    // 「次へ」が1項目飛ぶ。音を出さずに動画を閉じる。
    if playback.isClockStopped {
      playback.stop()
      chat.reset()
      return
    }
    var excluded = Set<UUID>()
    var skippedNames: [String] = []
    while true {
      let step = playlist.stepFromCurrent(excluding: excluded)
      skippedNames = step.skipped.compactMap { name(at: $0) }
      guard let target = step.target else { break }
      if playItem(at: target, byUser: false) {
        notify("開けない項目を飛ばしました", names: skippedNames)
        return
      }
      if let id = id(at: target) { excluded.insert(id) }
    }
    // 削除した動画や、現在の項目と食い違う動画を再生し続けない。
    playback.stop()
    chat.reset()
    notify("開けない項目を飛ばしました", names: skippedNames)
  }

  func moveEntries(fromOffsets: IndexSet, toOffset: Int) {
    playlist.move(fromOffsets: fromOffsets, toOffset: toOffset)
    playback.refreshRemote()
  }
}
