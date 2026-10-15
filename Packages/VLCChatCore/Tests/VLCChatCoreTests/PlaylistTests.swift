import Foundation
import Testing
@testable import VLCChatCore

struct PlaylistTests {
  private func entry(_ name: String) -> PlaylistEntry {
    PlaylistEntry(videoFileName: "\(name).mp4", videoBookmark: Data([1]))
  }

  /// 項目 a〜e・現在 c（添字2）。
  private func makePlaylist(_ names: [String] = ["a", "b", "c", "d", "e"], current: String? = "c") -> Playlist {
    let entries = names.map(entry)
    let currentID = current.flatMap { name in entries.first { $0.title == name }?.id }
    return Playlist(entries: entries, currentID: currentID)
  }

  private func titles(_ playlist: Playlist) -> [String] { playlist.entries.map(\.title) }

  /// 指定した名前だけが無効な `isPlayable`。
  private func unplayable(_ names: Set<String>) -> (PlaylistEntry) -> Bool {
    { !names.contains($0.title) }
  }

  @Test("置き換えると現在は先頭、空なら nil") func replaceSelectsFirst() {
    var playlist = makePlaylist()
    let x = entry("x"), y = entry("y")
    playlist.replace(with: [x, y])
    #expect(titles(playlist) == ["x", "y"])
    #expect(playlist.current == x)
    playlist.replace(with: [])
    #expect(playlist.currentID == nil)
  }

  @Test("追記しても現在は変わらない") func appendKeepsCurrent() {
    var playlist = makePlaylist()
    playlist.append([entry("f")])
    #expect(titles(playlist).last == "f")
    #expect(playlist.current?.title == "c")
    var empty = makePlaylist(current: nil)
    empty.append([entry("f")])
    #expect(empty.currentID == nil)
  }

  @Test("現在でない項目を消すと、現在は同じ項目を指し続ける") func removeNonCurrent() {
    var playlist = makePlaylist()
    #expect(playlist.remove(at: 0) == .notCurrent)
    #expect(titles(playlist) == ["b", "c", "d", "e"])
    #expect(playlist.currentIndex == 1)
    #expect(playlist.remove(at: 3) == .notCurrent)  // d
    #expect(playlist.current?.title == "c")
  }

  @Test("現在を消すと元の次が現在になる") func removeCurrentSelectsNext() {
    var playlist = makePlaylist()
    #expect(playlist.remove(at: 2) == .current)
    #expect(titles(playlist) == ["a", "b", "d", "e"])
    #expect(playlist.current?.title == "d")
    #expect(playlist.currentIndex == 2)
  }

  @Test("末尾の現在を消すと現在なし、現在なしでは常に notCurrent") func removeLastCurrent() {
    var playlist = makePlaylist(["a", "b", "c"])
    #expect(playlist.remove(at: 2) == .current)
    #expect(playlist.currentID == nil)
    var none = makePlaylist(current: nil)
    #expect(none.remove(at: 1) == .notCurrent)
  }

  @Test("範囲外の削除は何も変えない") func removeOutOfRange() {
    var playlist = makePlaylist()
    let before = playlist
    #expect(playlist.remove(at: 9) == .notCurrent)
    #expect(playlist == before)
  }

  @Test("並べ替えても現在は同じ項目を指し続ける") func moveKeepsCurrent() {
    var down = makePlaylist()
    down.move(fromOffsets: [0], toOffset: 3)
    #expect(titles(down) == ["b", "c", "a", "d", "e"])
    #expect(down.currentIndex == 1)

    var up = makePlaylist()
    up.move(fromOffsets: [4], toOffset: 0)
    #expect(titles(up) == ["e", "a", "b", "c", "d"])
    #expect(up.currentIndex == 3)

    var many = makePlaylist()
    many.move(fromOffsets: [1, 3], toOffset: 5)
    #expect(titles(many) == ["a", "c", "e", "b", "d"])

    var same = makePlaylist()
    same.move(fromOffsets: [2], toOffset: 2)
    #expect(titles(same) == ["a", "b", "c", "d", "e"])

    var itself = makePlaylist()
    itself.move(fromOffsets: [2], toOffset: 0)
    #expect(titles(itself) == ["c", "a", "b", "d", "e"])
    #expect(itself.currentIndex == 0)
  }

  @Test("範囲外の添字は無視し、移動先は末尾に丸める") func moveClampsInputs() {
    var outOfRange = makePlaylist()
    outOfRange.move(fromOffsets: [9], toOffset: 0)
    #expect(titles(outOfRange) == ["a", "b", "c", "d", "e"])

    var beyondEnd = makePlaylist()
    beyondEnd.move(fromOffsets: [0], toOffset: 9)
    #expect(titles(beyondEnd) == ["b", "c", "d", "e", "a"])
  }

  @Test("次へは無効な項目を飛ばす") func nextStepSkipsUnplayable() {
    let playlist = makePlaylist()
    #expect(playlist.nextStep(isPlayable: unplayable(["d"])) == Playlist.Step(target: 4, skipped: [3]))
    #expect(playlist.nextStep(isPlayable: unplayable(["d", "e"])) == Playlist.Step(target: nil, skipped: [3, 4]))
    let last = makePlaylist(current: "e")
    #expect(last.nextStep(isPlayable: unplayable([])) == Playlist.Step(target: nil, skipped: []))
  }

  @Test("前へは無効な項目を飛ばす") func previousStepSkipsUnplayable() {
    let playlist = makePlaylist()
    #expect(playlist.previousStep(isPlayable: unplayable(["b"])) == Playlist.Step(target: 0, skipped: [1]))
    #expect(makePlaylist(current: "a").previousStep(isPlayable: unplayable([])) == Playlist.Step(target: nil, skipped: []))
    #expect(makePlaylist(current: nil).previousStep(isPlayable: unplayable([])) == Playlist.Step(target: nil, skipped: []))
  }

  @Test("現在の項目そのものから探し始める") func stepFromCurrent() {
    let playlist = makePlaylist()
    #expect(playlist.stepFromCurrent(isPlayable: unplayable([])) == Playlist.Step(target: 2, skipped: []))
    #expect(playlist.stepFromCurrent(isPlayable: unplayable(["c"])) == Playlist.Step(target: 3, skipped: [2]))
    #expect(
      playlist.stepFromCurrent(isPlayable: unplayable(["c", "d", "e"])) == Playlist.Step(target: nil, skipped: [2, 3, 4]))
    #expect(
      makePlaylist(current: nil).stepFromCurrent(isPlayable: unplayable([])) == Playlist.Step(target: nil, skipped: []))
  }

  @Test("前へ・次へが使えるかは現在の位置で決まる") func hasPreviousAndNext() {
    #expect(!makePlaylist(current: "a").hasPrevious)
    #expect(makePlaylist(current: "a").hasNext)
    #expect(makePlaylist(current: "e").hasPrevious)
    #expect(!makePlaylist(current: "e").hasNext)
    #expect(!makePlaylist(current: nil).hasPrevious)
    #expect(!makePlaylist(current: nil).hasNext)
    #expect(!makePlaylist(["a"], current: "a").hasPrevious)
    #expect(!makePlaylist(["a"], current: "a").hasNext)
  }

  @Test("項目の更新は並びと現在を変えない") func updateEntryKeepsOrder() {
    var playlist = makePlaylist()
    let id = playlist.entries[0].id
    playlist.updateEntry(id: id) { $0.chatFileName = "a.json" }
    #expect(playlist.entries[0].chatFileName == "a.json")
    #expect(titles(playlist) == ["a", "b", "c", "d", "e"])
    #expect(playlist.current?.title == "c")
    let before = playlist
    playlist.updateEntry(id: UUID()) { $0.chatFileName = "x" }
    #expect(playlist == before)
  }

  @Test("拡張子の前の名前をタイトルにする") func titleDropsLastExtension() {
    #expect(PlaylistEntry(videoFileName: "a.b.mp4", videoBookmark: Data()).title == "a.b")
  }

  @Test("現在の設定は存在する id だけを受け付ける") func setCurrent() {
    var playlist = makePlaylist()
    let target = playlist.entries[4].id
    playlist.setCurrent(id: target)
    #expect(playlist.current?.title == "e")
    playlist.setCurrent(id: UUID())
    #expect(playlist.current?.title == "e")
    playlist.setCurrent(id: nil)
    #expect(playlist.currentID == nil)
  }
}
