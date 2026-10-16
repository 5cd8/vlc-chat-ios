import Foundation
import Testing
@testable import VLCChatCore

struct PlaylistFileTests {
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("playlist-\(UUID().uuidString).json")
  }

  @Test("保存して読み戻すと同じ内容") func roundTrips() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let withChat = PlaylistEntry(
      videoFileName: "動画1.mkv", videoBookmark: Data([1, 2, 3]),
      chatFileName: "動画1.live_chat.json", chatBookmark: Data([4, 5]))
    let withoutChat = PlaylistEntry(videoFileName: "b.mp4", videoBookmark: Data([9]))
    let playlist = Playlist(entries: [withChat, withoutChat], currentID: withoutChat.id)
    try PlaylistFile.save(playlist, to: url)
    #expect(try PlaylistFile.load(from: url) == playlist)
  }

  @Test("ファイルが無ければ nil") func missingFileIsNil() throws {
    #expect(try PlaylistFile.load(from: tempURL()) == nil)
  }

  @Test("壊れたJSONと新しい版は読めない") func rejectsCorruptAndNewerVersion() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{".utf8).write(to: url)
    #expect(throws: PlaylistFile.LoadError.unreadable) { try PlaylistFile.load(from: url) }
    try Data(#"{"version":2,"entries":[],"currentID":null}"#.utf8).write(to: url)
    #expect(throws: PlaylistFile.LoadError.unreadable) { try PlaylistFile.load(from: url) }
  }

  @Test("項目に無い currentID は読み込み時に nil になる") func dropsDanglingCurrentID() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let json = #"{"version":1,"entries":[],"currentID":"\#(UUID().uuidString)"}"#
    try Data(json.utf8).write(to: url)
    #expect(try PlaylistFile.load(from: url)?.currentID == nil)
  }

  @Test("上書き保存すると2回目の内容になる") func overwrites() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let first = Playlist(entries: [PlaylistEntry(videoFileName: "1.mp4", videoBookmark: Data())])
    let second = Playlist(entries: [PlaylistEntry(videoFileName: "2.mp4", videoBookmark: Data())])
    try PlaylistFile.save(first, to: url)
    try PlaylistFile.save(second, to: url)
    #expect(try PlaylistFile.load(from: url) == second)
  }
}
