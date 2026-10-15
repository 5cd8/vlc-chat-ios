import Foundation
import Testing
@testable import VLCChatCore

struct ResumeStoreTests {
  private let date = Date(timeIntervalSinceReferenceDate: 1000)
  private let video = VideoIdentity(fileName: "a.mp4", size: 100)

  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID().uuidString).json")
  }

  @Test("記録した位置を取り出せ、上書きでき、消せる") func setOverwriteRemove() {
    var store = ResumeStore()
    store.set(10, for: video, at: date)
    #expect(store.position(for: video) == 10)
    store.set(20, for: video, at: date)
    #expect(store.position(for: video) == 20)
    #expect(store.count == 1)
    store.remove(video)
    #expect(store.position(for: video) == nil)
    #expect(store.count == 0)
  }

  @Test("サイズだけが違う動画は別物") func differentSizeIsDifferentVideo() {
    var store = ResumeStore()
    store.set(10, for: video, at: date)
    #expect(store.position(for: VideoIdentity(fileName: "a.mp4", size: 101)) == nil)
  }

  @Test("NFDの名前でもNFCで記録した位置が取れる") func normalizedNamesMatch() {
    var store = ResumeStore()
    store.set(7, for: VideoIdentity(fileName: "が.mp4", size: 1), at: date)
    #expect(store.position(for: VideoIdentity(fileName: "か\u{3099}.mp4", size: 1)) == 7)
  }

  @Test("保存して読み戻すと同じ内容") func roundTrips() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    var store = ResumeStore()
    store.set(10, for: video, at: date)
    store.set(20, for: VideoIdentity(fileName: "日本語.mkv", size: 5), at: date)
    try store.save(to: url)
    #expect(try ResumeStore.load(from: url) == store)
  }

  @Test("ファイルが無ければ nil、壊れていれば throws") func loadMissingAndCorrupt() throws {
    #expect(try ResumeStore.load(from: tempURL()) == nil)
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{".utf8).write(to: url)
    #expect(throws: (any Error).self) { try ResumeStore.load(from: url) }
  }
}
